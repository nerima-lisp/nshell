#!/usr/bin/env python3

import argparse
import json
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path


FUNCTION = "(defun %process-input-event (event)"
TARGET = "          (multiple-value-bind (new-state output-event)\n              (reduce-input-state *input-state* event)"
FAULT_QUERY = (
    '(when (eq :ctrl-f (nshell.domain.input:key-event-type event)) '
    '(error "Q08_TEST_CONDITION"))'
)


def run_paredit(arguments: list[str]) -> str:
    result = subprocess.run(
        ["paredit", *arguments],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout


def prepare_source(source_root: Path, destination: Path) -> None:
    source_root = source_root.resolve(strict=True)
    destination = destination.resolve()
    if source_root == destination or source_root in destination.parents:
        raise ValueError("destination must be outside the source tree")
    if destination.exists():
        raise ValueError("destination already exists")

    shutil.copytree(
        source_root,
        destination,
        ignore=shutil.ignore_patterns(".git", ".jj", ".hg", ".svn"),
        copy_function=shutil.copy,
    )
    target = destination / "src/presentation/repl.lisp"
    source = target.read_text(encoding="utf-8")
    if source.count(FUNCTION) != 1:
        raise ValueError("expected one %process-input-event definition")
    start = source.index(FUNCTION)
    end = source.find("\n(defun ", start + len(FUNCTION))
    if end < 0:
        end = len(source)
    function_body = source[start:end]
    if function_body.count(TARGET) != 1:
        raise ValueError("expected one reducer call in %process-input-event")
    if "Q08_TEST_CONDITION" in function_body:
        raise ValueError("fault injection is already present")
    run_paredit(["inspect", "check", "--file", str(target)])

    target.chmod(target.stat().st_mode | stat.S_IWUSR)
    target.parent.chmod(target.parent.stat().st_mode | stat.S_IWUSR | stat.S_IXUSR)
    with tempfile.TemporaryDirectory(prefix="nshell-q08-fault-") as temporary:
        temporary_path = Path(temporary)
        form_path = temporary_path / "fault-form.lisp"
        ring_path = temporary_path / "kill-ring.json"
        insertion_indent = len(TARGET) - len(TARGET.lstrip())
        fault_form = (
            "(when (eq :ctrl-f\n"
            + " " * (insertion_indent + 10)
            + "(nshell.domain.input:key-event-type event))\n"
            + " " * (insertion_indent + 2)
            + '(error "Q08_TEST_CONDITION"))\n'
        )
        form_path.write_text(fault_form, encoding="utf-8")
        run_paredit(["inspect", "check", "--file", str(form_path)])
        kill_preview = run_paredit(
            [
                "edit",
                "kill",
                "--file",
                str(form_path),
                "--path",
                "0",
                "--ring",
                str(ring_path),
                "--to-ring",
                "--diff",
            ]
        )
        if "Q08_TEST_CONDITION" not in kill_preview:
            raise ValueError("paredit kill preview did not select the fault form")
        run_paredit(
            [
                "edit",
                "kill",
                "--file",
                str(form_path),
                "--path",
                "0",
                "--ring",
                str(ring_path),
                "--to-ring",
                "--write",
            ]
        )

        line_number = source.count("\n", 0, start + function_body.index(TARGET)) + 1
        line_start = source.rfind("\n", 0, start + function_body.index(TARGET)) + 1
        column = (
            start
            + function_body.index(TARGET)
            + TARGET.index("(")
            - line_start
            + 1
        )
        selection = f"{line_number}:{column}"
        preview = run_paredit(
            [
                "edit",
                "yank",
                "--file",
                str(target),
                "--line-column",
                selection,
                "--placement",
                "before",
                "--ring",
                str(ring_path),
                "--diff",
            ]
        )
        if "Q08_TEST_CONDITION" not in preview:
            raise ValueError("paredit preview did not contain the fault form")
        run_paredit(
            [
                "edit",
                "yank",
                "--file",
                str(target),
                "--line-column",
                selection,
                "--placement",
                "before",
                "--ring",
                str(ring_path),
                "--write",
            ]
        )
    run_paredit(["inspect", "check", "--file", str(target)])

    patched = target.read_text(encoding="utf-8")
    if patched.count("Q08_TEST_CONDITION") != 1:
        raise ValueError("expected one injected Q08_TEST_CONDITION")
    if "*input-state*" in fault_form:
        raise ValueError("fault injection must not mutate input state")
    patched_function_start = patched.index(FUNCTION)
    patched_function_end = patched.find("\n(defun ", patched_function_start + len(FUNCTION))
    if patched_function_end < 0:
        patched_function_end = len(patched)
    patched_function = patched[patched_function_start:patched_function_end]
    condition_index = patched_function.find("Q08_TEST_CONDITION")
    reducer_index = patched_function.find(TARGET)
    progn_index = patched_function.find("(progn")
    if progn_index < 0 or not progn_index < condition_index < reducer_index:
        raise ValueError("fault injection must immediately precede the reducer")
    resolution = json.loads(
        run_paredit(
            [
                "inspect",
                "resolve",
                "--file",
                str(target),
                "--query",
                FAULT_QUERY,
                "--output",
                "json",
            ]
        )
    )
    if resolution["matchCount"] != 1:
        raise ValueError("expected one complete Ctrl-f fault form")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_root", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    prepare_source(arguments.source_root, arguments.destination)


if __name__ == "__main__":
    main()
