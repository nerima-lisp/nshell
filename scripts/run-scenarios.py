#!/usr/bin/env python3
"""Run the declarative batch and tmux PTY scenario corpus."""

from __future__ import annotations

import argparse
import json
import os
import re
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SCENARIO_DIR = ROOT / "t" / "scenarios"
EXPECTED_SCENARIOS_FILE = "expected-scenarios.json"
MAX_TIMEOUT_SECONDS = 60
MAX_REPEAT = 10
MAX_OUTPUT_BYTES = 1_048_576
ENVIRONMENT_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
TMUX_KEY = re.compile(r"[A-Za-z0-9+-]+\Z")
SHIFTED_KEY_TEXT = {
    "1": "!",
    "2": "@",
    "3": "#",
    "4": "$",
    "5": "%",
    "6": "^",
    "7": "&",
    "8": "*",
    "9": "(",
    "0": ")",
    "-": "_",
    "+": "*",
}
TMUX_KEY_ECHO_TEXT = {
    "Space": " ",
    "Tab": "\t",
    "Enter": "\r\n",
    "Escape": "\x1b",
    "BSpace": "\x7f",
    "BTab": "\x1b[Z",
    "Up": "\x1b[A",
    "Down": "\x1b[B",
    "Right": "\x1b[C",
    "Left": "\x1b[D",
    "Home": "\x1b[H",
    "End": "\x1b[F",
    "IC": "\x1b[2~",
    "Insert": "\x1b[2~",
    "DC": "\x1b[3~",
    "Delete": "\x1b[3~",
    "PPage": "\x1b[5~",
    "PageUp": "\x1b[5~",
    "PgUp": "\x1b[5~",
    "NPage": "\x1b[6~",
    "PageDown": "\x1b[6~",
    "PgDn": "\x1b[6~",
    "F1": "\x1bOP",
    "F2": "\x1bOQ",
    "F3": "\x1bOR",
    "F4": "\x1bOS",
    "F5": "\x1b[15~",
    "F6": "\x1b[17~",
    "F7": "\x1b[18~",
    "F8": "\x1b[19~",
    "F9": "\x1b[20~",
    "F10": "\x1b[21~",
    "F11": "\x1b[23~",
    "F12": "\x1b[24~",
}


class ScenarioError(Exception):
    """A scenario could not be prepared or executed."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ScenarioError(message)


def _pane_exit_status(status: str, dead_signal: str, scenario_id: str) -> int:
    if status:
        try:
            return int(status)
        except ValueError as error:
            raise ScenarioError(f"{scenario_id}: tmux reported an invalid exit status") from error
    if dead_signal:
        try:
            signum = signal.Signals[f"SIG{dead_signal.upper()}"].value
        except KeyError as error:
            raise ScenarioError(f"{scenario_id}: tmux reported an invalid exit signal") from error
        return 128 + signum
    raise ScenarioError(f"{scenario_id}: tmux reported an invalid exit status")


def _relative_path(root: Path, value: Any, label: str) -> Path:
    _require(isinstance(value, str) and value != "", f"{label} must be a non-empty path")
    relative = Path(value)
    _require(not relative.is_absolute(), f"{label} must be relative: {value!r}")
    resolved_root = root.resolve()
    resolved = (resolved_root / relative).resolve()
    _require(
        resolved == resolved_root or resolved.is_relative_to(resolved_root),
        f"{label} escapes its scenario directory: {value!r}",
    )
    return resolved


def _scenario_files(directory: Path) -> list[Path]:
    _require(directory.is_dir(), f"scenario directory does not exist: {directory}")
    manifest = (directory / EXPECTED_SCENARIOS_FILE).resolve()
    paths = sorted(
        path for path in directory.rglob("*.json")
        if path.is_file() and path.resolve() != manifest
    )
    _require(paths, f"scenario directory contains no JSON scenarios: {directory}")
    return paths


def _verify_expected_scenarios(directory: Path, scenarios_by_path: dict[Path, dict[str, Any]]) -> None:
    manifest_path = directory / EXPECTED_SCENARIOS_FILE
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ScenarioError(f"cannot read expected-scenarios manifest {manifest_path}: {error}") from error
    _require(isinstance(manifest, dict), f"{manifest_path} must contain a JSON object")
    _require(manifest.get("version") == 1, f"{manifest_path}: version must be 1")
    entries = manifest.get("scenarios")
    _require(isinstance(entries, list) and entries,
             f"{manifest_path}: scenarios must be a non-empty array")

    expected_by_path: dict[Path, dict[str, Any]] = {}
    expected_ids: set[str] = set()
    for entry in entries:
        _require(isinstance(entry, dict), f"{manifest_path}: each scenario entry must be an object")
        _require(set(entry) == {"id", "uc", "path"},
                 f"{manifest_path}: each entry must define exactly id, uc, and path")
        scenario_id = entry["id"]
        _require(isinstance(scenario_id, str) and scenario_id,
                 f"{manifest_path}: scenario id must be a non-empty string")
        _require(scenario_id not in expected_ids,
                 f"{manifest_path}: duplicate scenario id: {scenario_id}")
        expected_ids.add(scenario_id)
        uc_ids = entry["uc"]
        _require(isinstance(uc_ids, list) and uc_ids,
                 f"{manifest_path}: {scenario_id}: uc must be a non-empty array")
        _require(all(isinstance(uc, str) and uc for uc in uc_ids),
                 f"{manifest_path}: {scenario_id}: each uc must be a non-empty string")
        _require(len(set(uc_ids)) == len(uc_ids),
                 f"{manifest_path}: {scenario_id}: duplicate uc id")
        scenario_path = _relative_path(directory, entry["path"], f"{manifest_path}: scenario path")
        _require(scenario_path.suffix == ".json" and scenario_path.is_file(),
                 f"{manifest_path}: {scenario_id}: scenario file does not exist: {entry['path']!r}")
        _require(scenario_path not in expected_by_path,
                 f"{manifest_path}: duplicate scenario path: {entry['path']!r}")
        expected_by_path[scenario_path] = entry

    actual_paths = set(scenarios_by_path)
    expected_paths = set(expected_by_path)
    missing_paths = sorted(path.relative_to(directory).as_posix() for path in expected_paths - actual_paths)
    unexpected_paths = sorted(path.relative_to(directory).as_posix() for path in actual_paths - expected_paths)
    _require(
        not missing_paths and not unexpected_paths,
        "scenario file set does not match expected-scenarios manifest: "
        f"missing={missing_paths}, unexpected={unexpected_paths}",
    )
    _require(
        len(scenarios_by_path) == len(entries),
        f"scenario count was {len(scenarios_by_path)}, expected {len(entries)}",
    )
    actual_ids = {scenario["id"] for scenario in scenarios_by_path.values()}
    _require(actual_ids == expected_ids,
             f"scenario id set does not match manifest: expected={sorted(expected_ids)}, actual={sorted(actual_ids)}")
    for scenario_path, scenario in scenarios_by_path.items():
        expected = expected_by_path[scenario_path]
        _require(scenario["id"] == expected["id"],
                 f"{scenario_path}: id was {scenario['id']!r}, expected {expected['id']!r}")
        _require(set(scenario["uc"]) == set(expected["uc"]),
                 f"{scenario_path}: uc was {sorted(scenario['uc'])}, expected {sorted(expected['uc'])}")


def _load_scenarios(directory: Path, mode: str, selected_ids: set[str]) -> list[dict[str, Any]]:
    scenarios: list[dict[str, Any]] = []
    scenarios_by_path: dict[Path, dict[str, Any]] = {}
    ids: set[str] = set()
    for path in _scenario_files(directory):
        try:
            scenario = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ScenarioError(f"cannot read {path}: {error}") from error
        _require(isinstance(scenario, dict), f"{path} must contain a JSON object")
        scenario_id = scenario.get("id")
        _require(isinstance(scenario_id, str) and scenario_id, f"{path} has no non-empty id")
        _require(scenario_id not in ids, f"duplicate scenario id: {scenario_id}")
        ids.add(scenario_id)
        _validate_scenario(scenario, path)
        scenarios_by_path[path.resolve()] = scenario
        if mode != "all" and scenario["mode"] != mode:
            continue
        if selected_ids and scenario_id not in selected_ids:
            continue
        scenarios.append(scenario)

    missing_ids = selected_ids - ids
    _require(not missing_ids, f"unknown scenario id(s): {', '.join(sorted(missing_ids))}")
    if mode == "all" and not selected_ids:
        _verify_expected_scenarios(directory.resolve(), scenarios_by_path)
    _require(scenarios, "scenario selection is empty")
    return scenarios


def _validate_scenario(scenario: dict[str, Any], path: Path) -> None:
    scenario_id = scenario.get("id", path.name)
    _require(scenario.get("mode") in ("batch", "pty"), f"{scenario_id}: mode must be batch or pty")
    load_config = scenario.get("load_config", False)
    _require(isinstance(load_config, bool), f"{scenario_id}: load_config must be a boolean")
    _require(not load_config or scenario["mode"] == "pty",
             f"{scenario_id}: load_config is supported only for pty scenarios")
    private_mode = scenario.get("private_mode", False)
    _require(isinstance(private_mode, bool), f"{scenario_id}: private_mode must be a boolean")
    _require(not private_mode or scenario["mode"] == "pty",
             f"{scenario_id}: private_mode is supported only for pty scenarios")
    _require(
        isinstance(scenario.get("uc"), list) and scenario["uc"],
        f"{scenario_id}: uc must be a non-empty array",
    )
    for uc in scenario["uc"]:
        _require(isinstance(uc, str) and uc, f"{scenario_id}: each uc must be a non-empty string")

    environment = scenario.get("environment", {})
    _require(isinstance(environment, dict), f"{scenario_id}: environment must be an object")
    variables = environment.get("variables", {})
    _require(isinstance(variables, dict), f"{scenario_id}: environment.variables must be an object")
    for name, value in variables.items():
        _require(
            isinstance(name, str) and ENVIRONMENT_NAME.fullmatch(name),
            f"{scenario_id}: invalid environment variable name {name!r}",
        )
        _require(isinstance(value, str), f"{scenario_id}: environment variable {name} must be a string")
        _require(name not in ("HOME", "TMPDIR", "TMUX", "TMUX_PANE"),
                 f"{scenario_id}: set {name} through the scenario environment, not variables")
    _relative_path(Path("/scenario"), environment.get("home", "home"), f"{scenario_id}: home")
    _relative_path(Path("/scenario"), environment.get("cwd", "work"), f"{scenario_id}: cwd")
    terminal_size = environment.get("terminal_size", {"columns": 80, "rows": 24})
    _require(isinstance(terminal_size, dict), f"{scenario_id}: terminal_size must be an object")
    for dimension in ("columns", "rows"):
        value = terminal_size.get(dimension)
        _require(
            isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 512,
            f"{scenario_id}: terminal_size.{dimension} must be between 1 and 512",
        )

    preconditions = scenario.get("preconditions", {})
    _require(isinstance(preconditions, dict), f"{scenario_id}: preconditions must be an object")
    fixtures = preconditions.get("files", [])
    _require(isinstance(fixtures, list), f"{scenario_id}: preconditions.files must be an array")
    for fixture in fixtures:
        _require(isinstance(fixture, dict), f"{scenario_id}: each precondition file must be an object")
        _relative_path(Path("/scenario"), fixture.get("path"), f"{scenario_id}: precondition file")
        _require(isinstance(fixture.get("content", ""), str),
                 f"{scenario_id}: precondition file content must be a string")

    if scenario["mode"] == "batch":
        invocation = scenario.get("invocation")
        _require(isinstance(invocation, dict), f"{scenario_id}: invocation must be an object")
        kind = invocation.get("kind")
        _require(kind in ("command", "stdin", "script"),
                 f"{scenario_id}: invocation.kind must be command, stdin, or script")
        _require(isinstance(invocation.get("text"), str), f"{scenario_id}: invocation.text must be a string")
        if kind == "script":
            _relative_path(Path("/scenario"), invocation.get("path"), f"{scenario_id}: script path")
    else:
        sessions = _pty_sessions(scenario)
        for session in sessions:
            _require(isinstance(session["prompt"], str) and session["prompt"],
                     f"{scenario_id}: PTY sessions must set a unique prompt")
            steps = session["steps"]
            _require(isinstance(steps, list) and steps,
                     f"{scenario_id}: pty steps must be a non-empty array")
            for step in steps:
                _require(isinstance(step, dict), f"{scenario_id}: each pty step must be an object")
                kind = step.get("type")
                _require(kind in ("keys", "paste", "key", "wait", "wait_exit"),
                         f"{scenario_id}: unsupported pty step type {kind!r}")
                if kind in ("keys", "paste"):
                    _require(isinstance(step.get("text"), str), f"{scenario_id}: {kind} requires text")
                if kind == "key":
                    key = step.get("key")
                    _require(isinstance(key, str) and TMUX_KEY.fullmatch(key),
                             f"{scenario_id}: invalid tmux key {key!r}")
                if kind == "wait":
                    _require(isinstance(step.get("contains"), str) and step["contains"],
                             f"{scenario_id}: wait requires a non-empty contains string")
                if kind in ("wait", "wait_exit"):
                    timeout = step.get("timeout_seconds", 10)
                    _require(
                        isinstance(timeout, (int, float))
                        and not isinstance(timeout, bool)
                        and 0 < timeout <= MAX_TIMEOUT_SECONDS,
                        f"{scenario_id}: step timeout_seconds must be in (0, {MAX_TIMEOUT_SECONDS}]",
                    )
            _require(
                steps[-1]["type"] in ("wait", "wait_exit")
                and all(step["type"] != "wait_exit" for step in steps[:-1]),
                f"{scenario_id}: end pty steps with wait or wait_exit, and make wait_exit last",
            )

    expected_failure = scenario.get("expected_failure")
    if expected_failure is not None:
        _require(isinstance(expected_failure, dict), f"{scenario_id}: expected_failure must be an object")
        reason = expected_failure.get("reason")
        _require(isinstance(reason, str) and reason.strip(),
                 f"{scenario_id}: expected_failure.reason must be non-empty")
    _require(isinstance(scenario.get("expected"), dict), f"{scenario_id}: expected must be an object")
    timeout = scenario.get("timeout_seconds", 30)
    _require(
        isinstance(timeout, (int, float))
        and not isinstance(timeout, bool)
        and 0 < timeout <= MAX_TIMEOUT_SECONDS,
        f"{scenario_id}: timeout_seconds must be in (0, {MAX_TIMEOUT_SECONDS}]",
    )
    expected = scenario["expected"]
    _require("exit_code" in expected, f"{scenario_id}: expected.exit_code is required")
    if scenario["mode"] == "pty":
        for session in _pty_sessions(scenario):
            session_scenario = dict(scenario)
            session_scenario["steps"] = session["steps"]
            session_environment = dict(scenario["environment"])
            session_variables = dict(session_environment.get("variables", {}))
            session_variables["NSHELL_PROMPT"] = session["prompt"]
            session_environment["variables"] = session_variables
            session_scenario["environment"] = session_environment
            _validate_pty_match_sources(session_scenario)
    output_checks = {"stdout", "stderr"} if scenario["mode"] == "batch" else {"stream", "screen"}
    effects = expected.get("side_effects", {})
    _require(isinstance(effects, dict), f"{scenario_id}: side_effects must be an object")
    has_effect_check = bool(effects.get("files")) or effects.get("history") is not None
    has_output_check = any(expected.get(key) is not None for key in output_checks)
    _require(
        has_output_check or "exit_code" in expected or has_effect_check,
        f"{scenario_id}: expected must define an output, exit-code, or side-effect check",
    )
    if "exit_code" in expected:
        _require(isinstance(expected["exit_code"], int) and not isinstance(expected["exit_code"], bool),
                 f"{scenario_id}: expected.exit_code must be an integer")
        if scenario["mode"] == "pty":
            _require(
                all(session["steps"][-1]["type"] == "wait_exit" for session in _pty_sessions(scenario)),
                f"{scenario_id}: PTY exit-code checks require a final wait_exit step",
            )


def _pty_sessions(scenario: dict[str, Any]) -> list[dict[str, Any]]:
    sessions = scenario.get("sessions")
    if sessions is None:
        return [{
            "id": "default",
            "prompt": scenario.get("environment", {}).get("variables", {}).get("NSHELL_PROMPT"),
            "steps": scenario.get("steps"),
        }]

    _require("steps" not in scenario, f"{scenario['id']}: use either pty steps or sessions")
    _require(isinstance(sessions, list) and len(sessions) >= 2,
             f"{scenario['id']}: sessions must contain at least two PTY sessions")
    ids: set[str] = set()
    prompts: set[str] = set()
    for session in sessions:
        _require(isinstance(session, dict), f"{scenario['id']}: each session must be an object")
        session_id = session.get("id")
        _require(isinstance(session_id, str) and session_id,
                 f"{scenario['id']}: each session requires a non-empty id")
        _require(session_id not in ids, f"{scenario['id']}: duplicate session id {session_id!r}")
        ids.add(session_id)
        prompt = session.get("prompt")
        _require(isinstance(prompt, str) and prompt,
                 f"{scenario['id']}: each session requires a non-empty prompt")
        _require(prompt not in prompts, f"{scenario['id']}: PTY session prompts must be unique")
        prompts.add(prompt)
        _require(isinstance(session.get("steps"), list),
                 f"{scenario['id']}: each session requires a steps array")
    return sessions


def _validate_pty_match_sources(scenario: dict[str, Any]) -> None:
    scenario_id = scenario["id"]
    prompt = scenario["environment"].get("variables", {}).get("NSHELL_PROMPT", "")

    def reject_overlap(label: str, marker: str, sources: list[tuple[str, str]]) -> None:
        for source_name, source in sources:
            if marker and marker in source:
                raise ScenarioError(
                    f"{scenario_id}: PTY {label} marker {marker!r} can be satisfied by {source_name}; "
                    "use a marker unique to shell output"
                )

    inputs: list[str] = []
    for step in scenario["steps"]:
        if step["type"] == "wait":
            sources = [("input echo", text) for text in inputs]
            sources.append(("prompt redraw", prompt))
            reject_overlap("wait", step["contains"], sources)
        if step["type"] in ("keys", "paste"):
            inputs.append(step["text"])
        elif step["type"] == "key":
            inputs.extend(_tmux_key_echo_sources(step["key"]))

    sources = [("input echo", text) for text in inputs]
    sources.append(("prompt redraw", prompt))
    expected = scenario["expected"]
    for output_name in ("stream", "screen"):
        check = expected.get(output_name)
        if not isinstance(check, dict):
            continue
        matches: list[str] = []
        equals = check.get("equals")
        if isinstance(equals, str):
            matches.append(equals)
        contains = check.get("contains", [])
        if isinstance(contains, list):
            matches.extend(value for value in contains if isinstance(value, str))
        for marker in matches:
            reject_overlap(f"{output_name} expectation", marker, sources)


def _tmux_key_echo_sources(key: str) -> list[str]:
    modifiers = []
    base_key = key
    while "-" in base_key:
        modifier, remainder = base_key.split("-", 1)
        if modifier not in ("C", "M", "S"):
            break
        modifiers.append(modifier)
        base_key = remainder

    text = base_key if len(base_key) == 1 else TMUX_KEY_ECHO_TEXT.get(base_key)
    if text is None:
        return []

    if "S" in modifiers and len(text) == 1:
        text = text.upper() if text.isalpha() else SHIFTED_KEY_TEXT.get(text, text)
    if "C" in modifiers:
        if len(text) != 1:
            return []
        codepoint = ord(text.upper())
        if codepoint > 95:
            return []
        text = chr(codepoint & 0x1F)
    if "M" in modifiers:
        text = "\x1b" + text

    sources = [text]
    if text.startswith("\x1b"):
        sources.append("^[" + text[1:])
    if text == "\t":
        sources.append("^I")
    if text == "\x7f":
        sources.append("^?")
    if len(text) == 1 and 0 < ord(text) < 32:
        sources.append("^" + chr(ord(text) + 64))
    return sources


def _environment(scenario: dict[str, Any], root: Path) -> tuple[dict[str, str], Path, Path]:
    settings = scenario.get("environment", {})
    home = _relative_path(root, settings.get("home", "home"), f"{scenario['id']}: home")
    cwd = _relative_path(root, settings.get("cwd", "work"), f"{scenario['id']}: cwd")
    tmpdir = root / "tmp"
    for directory in (
        home,
        cwd,
        tmpdir,
        home / ".config",
        home / ".cache",
        home / ".local" / "share",
        home / ".local" / "state",
    ):
        directory.mkdir(parents=True, exist_ok=True)
    env = {
        "HOME": str(home),
        "PATH": "/usr/bin:/bin",
        "TERM": "xterm-256color",
        "LANG": "C",
        "LC_ALL": "C",
        "TMPDIR": str(tmpdir),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
        "XDG_STATE_HOME": str(home / ".local" / "state"),
    }
    env.update(settings.get("variables", {}))
    extra_path = os.environ.get("NSHELL_SCENARIO_EXTRA_PATH")
    has_explicit_path = "PATH" in settings.get("variables", {})
    if scenario["mode"] == "batch" and extra_path and not has_explicit_path:
        env["PATH"] = os.pathsep.join((env["PATH"], extra_path))
    return env, home, cwd


def _write_preconditions(scenario: dict[str, Any], root: Path) -> None:
    for fixture in scenario.get("preconditions", {}).get("files", []):
        path = _relative_path(root, fixture["path"], f"{scenario['id']}: precondition file")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(fixture.get("content", ""), encoding="utf-8")


def _assert_text(label: str, actual: str, expected: Any, failures: list[str]) -> None:
    if expected is None:
        return
    _require(isinstance(expected, dict), f"{label} expectation must be an object")
    if "equals" in expected:
        _require(isinstance(expected["equals"], str), f"{label}.equals must be a string")
        if actual != expected["equals"]:
            failures.append(f"{label} did not equal the expected text")
    contains = expected.get("contains", [])
    excludes = expected.get("excludes", [])
    _require(isinstance(contains, list) and all(isinstance(item, str) for item in contains),
             f"{label}.contains must be an array of strings")
    _require(isinstance(excludes, list) and all(isinstance(item, str) for item in excludes),
             f"{label}.excludes must be an array of strings")
    _require(
        "equals" in expected or bool(contains) or bool(excludes),
        f"{label} expectation must define a non-empty text check",
    )
    _require(all(item for item in contains + excludes), f"{label} text checks must be non-empty")
    for item in contains:
        if item not in actual:
            failures.append(f"{label} did not contain {item!r}")
    for item in excludes:
        if item in actual:
            failures.append(f"{label} unexpectedly contained {item!r}")


def _assert_side_effects(expected: dict[str, Any], cwd: Path, home: Path,
                         failures: list[str], scenario_id: str) -> None:
    side_effects = expected.get("side_effects", {})
    _require(isinstance(side_effects, dict), f"{scenario_id}: side_effects must be an object")
    files = side_effects.get("files", [])
    _require(isinstance(files, list), f"{scenario_id}: side_effects.files must be an array")
    for effect in files:
        _require(isinstance(effect, dict), f"{scenario_id}: each file effect must be an object")
        path = _relative_path(cwd, effect.get("path"), f"{scenario_id}: side-effect file")
        exists = effect.get("exists", True)
        _require(isinstance(exists, bool), f"{scenario_id}: file exists must be boolean")
        if path.exists() != exists:
            failures.append(f"file {effect.get('path')!r} existence was {path.exists()}, expected {exists}")
            continue
        if not exists:
            continue
        _require(path.is_file(), f"{scenario_id}: expected side effect is not a regular file: {effect['path']}")
        content = path.read_text(encoding="utf-8", errors="replace")
        text_check = {
            key: effect[key] for key in ("equals", "contains", "excludes") if key in effect
        }
        if text_check:
            _assert_text(f"file {effect['path']!r}", content, text_check, failures)

    history = side_effects.get("history")
    if history is not None:
        _require(isinstance(history, dict), f"{scenario_id}: side_effects.history must be an object")
        path = _relative_path(home, history.get("path"), f"{scenario_id}: history path")
        exists = history.get("exists", True)
        _require(isinstance(exists, bool), f"{scenario_id}: history exists must be boolean")
        if path.exists() != exists:
            failures.append(f"history {history.get('path')!r} existence was {path.exists()}, expected {exists}")
        elif exists:
            _require(path.is_file(), f"{scenario_id}: expected history is not a regular file")
            content = path.read_text(encoding="utf-8", errors="replace")
            text_check = {
                key: history[key] for key in ("equals", "contains", "excludes") if key in history
            }
            if text_check:
                _assert_text(f"history {history['path']!r}", content, text_check, failures)


def _binary_args(scenario: dict[str, Any], cwd: Path) -> tuple[list[str], bytes]:
    invocation = scenario["invocation"]
    kind = invocation["kind"]
    text = invocation["text"]
    if kind == "command":
        return ["--no-config", "-c", text], b""
    if kind == "stdin":
        return ["--no-config"], text.encode("utf-8")
    script = _relative_path(cwd, invocation["path"], f"{scenario['id']}: script path")
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text(text, encoding="utf-8")
    return [str(script)], b""


def _kill_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def _run_batch(scenario: dict[str, Any], binary: Path) -> tuple[str, str, int, list[str]]:
    with tempfile.TemporaryDirectory(prefix="nshell-scenario-") as temporary:
        root = Path(temporary)
        env, home, cwd = _environment(scenario, root)
        _write_preconditions(scenario, root)
        arguments, stdin = _binary_args(scenario, cwd)
        timeout = scenario.get("timeout_seconds", 30)
        try:
            process = subprocess.Popen(
                [str(binary), *arguments],
                cwd=cwd,
                env=env,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
        except OSError as error:
            raise ScenarioError(f"{scenario['id']}: could not start nshell: {error}") from error
        try:
            stdout, stderr = process.communicate(stdin, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            _kill_process_group(process)
            stdout, stderr = process.communicate()
            raise ScenarioError(
                f"{scenario['id']}: batch process exceeded {timeout:g}s; "
                f"stdout={(stdout or b'').decode('utf-8', errors='replace')[-2000:]!r}; "
                f"stderr={(stderr or b'').decode('utf-8', errors='replace')[-2000:]!r}"
            ) from error
        stdout_text = stdout.decode("utf-8", errors="replace")
        stderr_text = stderr.decode("utf-8", errors="replace")
        failures = _check_expected(scenario, stdout_text, stderr_text, process.returncode, home, cwd)
        return stdout_text, stderr_text, process.returncode, failures


def _nshell_command(binary: Path, scenario: dict[str, Any]) -> list[str]:
    command = [str(binary)]
    if not scenario.get("load_config", False):
        command.append("--no-config")
    if scenario.get("private_mode", False):
        command.append("--private")
    return command


class TmuxSession:
    def __init__(self, scenario: dict[str, Any], binary: Path, root: Path,
                 env: dict[str, str], cwd: Path):
        self.scenario = scenario
        self.root = root
        self.env = os.environ.copy()
        self.env["TMUX_TMPDIR"] = str(root)
        self.socket = "ns-" + uuid.uuid4().hex[:10]
        self.channel = "exit-" + uuid.uuid4().hex[:12]
        self.pane = ""
        self.stream = bytearray()
        self.fifo_fd = -1
        self.server_started = False
        self.exit_waiter: subprocess.Popen[bytes] | None = None
        self.deadline_seconds = scenario.get("timeout_seconds", 45)
        self._validate_timeout(self.deadline_seconds, scenario["id"])
        self.deadline = time.monotonic() + self.deadline_seconds

        environment = scenario.get("environment", {})
        size = environment.get("terminal_size", {"columns": 80, "rows": 24})
        command = ["/usr/bin/env", "-i"]
        command.extend(f"{name}={value}" for name, value in sorted(env.items()))
        command.extend(_nshell_command(binary, scenario))
        shell_command = "exec " + shlex.join(command)

        try:
            self._tmux(["start-server", ";", "set-option", "-s", "exit-empty", "off"])
            self.server_started = True
            self._tmux(["set-option", "-g", "remain-on-exit", "on"])
            self._tmux(["set-hook", "-g", "pane-died", f"wait-for -S {self.channel}"])
            self.exit_waiter = subprocess.Popen(
                self._tmux_argv(["wait-for", self.channel]),
                env=self.env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.fifo_path = root / f"pane-output-{self.socket}"
            os.mkfifo(self.fifo_path, 0o600)
            self.fifo_fd = os.open(self.fifo_path, os.O_RDWR | os.O_NONBLOCK)
            result = self._tmux([
                "new-session", "-d", "-P", "-F", "#{pane_id}",
                "-s", "scenario", "-x", str(size["columns"]), "-y", str(size["rows"]),
                "-c", str(cwd), shell_command,
            ])
            self.pane = result.stdout.decode("utf-8", errors="replace").strip()
            _require(self.pane.startswith("%"), f"{scenario['id']}: tmux did not return a pane id")
            self._tmux(["pipe-pane", "-o", "-t", self.pane, f"cat > {shlex.quote(str(self.fifo_path))}"])

            prompt = env["NSHELL_PROMPT"]
            start = len(self.stream)
            self.send_key("Enter")
            self.wait_for(prompt, start, 10)
        except BaseException as error:
            try:
                self.close()
            except ScenarioError as cleanup_error:
                raise error from cleanup_error
            raise

    @staticmethod
    def _validate_timeout(value: Any, scenario_id: str) -> None:
        _require(
            isinstance(value, (int, float))
            and not isinstance(value, bool)
            and 0 < value <= MAX_TIMEOUT_SECONDS,
            f"{scenario_id}: timeout_seconds must be in (0, {MAX_TIMEOUT_SECONDS}]",
        )

    def _tmux_argv(self, arguments: list[str]) -> list[str]:
        return ["tmux", "-f", "/dev/null", "-L", self.socket, *arguments]

    def _tmux(self, arguments: list[str], input_text: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
        try:
            result = subprocess.run(
                self._tmux_argv(arguments),
                input=input_text,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=self.env,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ScenarioError(f"{self.scenario['id']}: tmux command failed: {error}") from error
        if result.returncode != 0:
            message = result.stderr.decode("utf-8", errors="replace").strip()
            raise ScenarioError(f"{self.scenario['id']}: tmux command failed: {message}")
        return result

    def send_text(self, text: str) -> None:
        self._tmux(["send-keys", "-l", "-t", self.pane, text])

    def send_key(self, key: str) -> None:
        self._tmux(["send-keys", "-t", self.pane, key])

    def paste(self, text: str) -> None:
        buffer_name = "scenario-" + uuid.uuid4().hex[:10]
        self._tmux(["load-buffer", "-b", buffer_name, "-"], text.encode("utf-8"))
        try:
            self._tmux(["paste-buffer", "-p", "-b", buffer_name, "-t", self.pane])
        finally:
            self._tmux(["delete-buffer", "-b", buffer_name])

    def _read(self, timeout: float) -> bytes:
        readable, _, _ = select.select([self.fifo_fd], [], [], timeout)
        if not readable:
            return b""
        remaining = MAX_OUTPUT_BYTES - len(self.stream)
        try:
            data = os.read(self.fifo_fd, min(65536, remaining + 1))
        except BlockingIOError:
            return b""
        if data:
            if len(data) > remaining:
                raise ScenarioError(f"{self.scenario['id']}: PTY output limit exceeded")
            self.stream.extend(data)
        return data

    def drain(self) -> None:
        while self._read(0):
            pass

    def _capture(self) -> str:
        try:
            result = self._tmux(["capture-pane", "-p", "-t", self.pane])
        except ScenarioError:
            return "<pane no longer available>"
        return result.stdout.decode("utf-8", errors="replace")

    def wait_for(self, text: str, start: int, timeout: float) -> int:
        self._validate_timeout(timeout, self.scenario["id"])
        needle = text.encode("utf-8")
        deadline = min(self.deadline, time.monotonic() + timeout)
        while True:
            position = bytes(self.stream).find(needle, start)
            if position >= 0:
                return position + len(needle)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                screen = self._capture()
                raise ScenarioError(
                    f"{self.scenario['id']}: timed out waiting for {text!r}; "
                    f"current screen:\n{screen}"
                )
            self._read(remaining)

    def wait_exit(self, timeout: float) -> int:
        _require(self.exit_waiter is not None, f"{self.scenario['id']}: tmux exit waiter is missing")
        try:
            stdout, stderr = self.exit_waiter.communicate(timeout=min(timeout, self.deadline - time.monotonic()))
        except subprocess.TimeoutExpired as error:
            screen = self._capture()
            raise ScenarioError(
                f"{self.scenario['id']}: timed out waiting for nshell exit; current screen:\n{screen}"
            ) from error
        _require(self.exit_waiter.returncode == 0,
                 f"{self.scenario['id']}: tmux exit wait failed: "
                 f"{stderr.decode('utf-8', errors='replace').strip()}")
        result = self._tmux([
            "display-message", "-p", "-t", self.pane,
            "#{pane_dead_status} #{pane_dead_signal}",
        ])
        status, separator, dead_signal = result.stdout.decode("ascii").rstrip("\r\n").partition(" ")
        _require(bool(separator), f"{self.scenario['id']}: tmux reported an invalid exit status")
        return _pane_exit_status(status, dead_signal, self.scenario["id"])

    def capture_screen(self) -> str:
        return self._capture()

    def close(self) -> None:
        if self.exit_waiter is not None and self.exit_waiter.poll() is None:
            self.exit_waiter.terminate()
            try:
                self.exit_waiter.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.exit_waiter.kill()
                self.exit_waiter.wait()
        cleanup_error = None
        if self.server_started:
            try:
                self._tmux(["kill-server"])
            except ScenarioError as error:
                cleanup_error = error
        if self.fifo_fd >= 0:
            os.close(self.fifo_fd)
            self.fifo_fd = -1
        if cleanup_error is not None:
            raise cleanup_error


def _run_pty(scenario: dict[str, Any], binary: Path) -> tuple[str, str, int, list[str]]:
    _require(shutil.which("tmux") is not None, f"{scenario['id']}: tmux is required for PTY scenarios")
    with tempfile.TemporaryDirectory(prefix="nshell-scenario-") as temporary:
        root = Path(temporary)
        env, home, cwd = _environment(scenario, root)
        _write_preconditions(scenario, root)
        sessions: list[tuple[TmuxSession, dict[str, Any]]] = []
        exit_codes: list[int] = []
        try:
            for spec in _pty_sessions(scenario):
                session_scenario = dict(scenario)
                session_scenario["id"] = f"{scenario['id']}:{spec['id']}"
                session_scenario["steps"] = spec["steps"]
                session_environment = dict(scenario["environment"])
                session_variables = dict(session_environment.get("variables", {}))
                session_variables["NSHELL_PROMPT"] = spec["prompt"]
                session_environment["variables"] = session_variables
                session_scenario["environment"] = session_environment
                session_env = env.copy()
                session_env["NSHELL_PROMPT"] = spec["prompt"]
                session = TmuxSession(session_scenario, binary, root, session_env, cwd)
                sessions.append((session, spec))
            for session, _ in sessions:
                session.deadline = time.monotonic() + session.deadline_seconds

            for session, spec in sessions:
                for step in spec["steps"]:
                    kind = step["type"]
                    if kind == "keys":
                        session.send_text(step["text"])
                    elif kind == "paste":
                        session.paste(step["text"])
                    elif kind == "key":
                        session.send_key(step["key"])
                    elif kind == "wait":
                        session.wait_for(step["contains"], len(session.stream), step.get("timeout_seconds", 10))
                    elif kind == "wait_exit":
                        exit_codes.append(session.wait_exit(step.get("timeout_seconds", 10)))
                        session.drain()
            total_output = sum(len(session.stream) for session, _ in sessions)
            _require(total_output <= MAX_OUTPUT_BYTES, f"{scenario['id']}: PTY output limit exceeded")
            stream = "\n".join(
                bytes(session.stream).decode("utf-8", errors="replace") for session, _ in sessions
            )
            screen = "\n".join(session.capture_screen() for session, _ in sessions)
            exit_code = next((code for code in exit_codes if code != 0), exit_codes[-1] if exit_codes else -1)
            failures = _check_expected(
                scenario, stream, screen, exit_code, home, cwd
            )
        finally:
            for session, _ in reversed(sessions):
                session.close()
        return stream, screen, exit_code, failures


def _check_expected(scenario: dict[str, Any], first: str, second: str, exit_code: int,
                    home: Path, cwd: Path) -> list[str]:
    expected = scenario["expected"]
    failures: list[str] = []
    if scenario["mode"] == "batch":
        stdout, stderr = first, second
        _assert_text("stdout", stdout, expected.get("stdout"), failures)
        _assert_text("stderr", stderr, expected.get("stderr"), failures)
    else:
        stream, screen = first, second
        _assert_text("PTY stream", stream, expected.get("stream"), failures)
        _assert_text("PTY screen", screen, expected.get("screen"), failures)
    if "exit_code" in expected and exit_code != expected["exit_code"]:
        failures.append(f"exit code was {exit_code}, expected {expected['exit_code']}")
    _assert_side_effects(expected, cwd, home, failures, scenario["id"])
    return failures


def _run_once(scenario: dict[str, Any], binary: Path) -> tuple[str, str]:
    _, _, _, failures = _run_batch(scenario, binary) if scenario["mode"] == "batch" else _run_pty(scenario, binary)
    expected_failure = scenario.get("expected_failure")
    if expected_failure is not None:
        if failures:
            return "XFAIL", f"{expected_failure['reason']} Failed: {'; '.join(failures)}"
        return "XPASS", f"expected failure now satisfies all assertions: {expected_failure['reason']}"
    if failures:
        return "FAIL", "; ".join(failures)
    return "PASS", ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path, help="path to the nshell executable")
    parser.add_argument("--scenario-dir", type=Path, default=DEFAULT_SCENARIO_DIR)
    parser.add_argument("--mode", choices=("all", "batch", "pty"), default="all")
    parser.add_argument("--scenario-id", action="append", default=[])
    parser.add_argument("--repeat", type=int, default=1)
    arguments = parser.parse_args()

    if not 1 <= arguments.repeat <= MAX_REPEAT:
        parser.error(f"--repeat must be between 1 and {MAX_REPEAT}")
    binary = arguments.binary.resolve()
    if not binary.is_file() or binary.stat().st_size == 0 or not os.access(binary, os.X_OK):
        parser.error(f"--binary must be a non-empty executable file: {binary}")

    try:
        scenarios = _load_scenarios(arguments.scenario_dir.resolve(), arguments.mode, set(arguments.scenario_id))
        summary = {"PASS": 0, "XFAIL": 0, "XPASS": 0, "FAIL": 0}
        for scenario in scenarios:
            for iteration in range(1, arguments.repeat + 1):
                try:
                    status, detail = _run_once(scenario, binary)
                except ScenarioError as error:
                    status, detail = "FAIL", str(error)
                summary[status] += 1
                suffix = f" run={iteration}/{arguments.repeat}" if arguments.repeat > 1 else ""
                line = f"{status} {scenario['id']}{suffix}"
                if detail:
                    line += f": {detail}"
                print(line)
        total = sum(summary.values())
        print(
            "SCENARIO_SUMMARY "
            f"selected={len(scenarios)} runs={total} "
            f"pass={summary['PASS']} xfail={summary['XFAIL']} "
            f"xpass={summary['XPASS']} fail={summary['FAIL']}"
        )
        return int(summary["XPASS"] > 0 or summary["FAIL"] > 0)
    except ScenarioError as error:
        print(f"SCENARIO_ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
