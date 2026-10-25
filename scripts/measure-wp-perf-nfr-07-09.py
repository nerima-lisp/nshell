#!/usr/bin/env python3
"""Measure NFR-07 through NFR-09 for an explicitly selected nshell revision."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import platform
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path
from statistics import median
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SEED = 0x6D2B79F5
NFR07_RSS_LIMIT_MIB = 150.0
NFR09_COVERAGE_LIMIT = 85.0
NFR09_NEW_CODE_LIMIT = 90.0
PTY_ROWS = 24
PTY_COLUMNS = 100
CPR_QUERY = b"\x1b[6n"
CPR_RESPONSE = b"\x1b[1;1R"
DEBUGGER_PATTERNS = (
    re.compile(r"debugger invoked", re.IGNORECASE),
    re.compile(r"entering debugger", re.IGNORECASE),
    re.compile(r"\bdebug[0-9]*>"),
    re.compile(r"backtrace for:", re.IGNORECASE),
    re.compile(r"unhandled\s+[A-Z][A-Z0-9-]+", re.IGNORECASE),
)
DUMP_PATTERNS = (
    re.compile(r"core dumped", re.IGNORECASE),
    re.compile(r"segmentation fault", re.IGNORECASE),
    re.compile(r"fatal error", re.IGNORECASE),
    re.compile(r"bus error", re.IGNORECASE),
)


class MeasurementError(RuntimeError):
    pass


def uptime_snapshot() -> dict[str, Any]:
    try:
        completed = subprocess.run(
            ["uptime"], capture_output=True, text=True, errors="replace", timeout=5
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"raw": None, "load_average": None, "error": str(exc)}

    raw = completed.stdout.strip() or completed.stderr.strip()
    match = re.search(r"load averages?:\s*([0-9]+(?:\.[0-9]+)?)[, ]+([0-9]+(?:\.[0-9]+)?)[, ]+([0-9]+(?:\.[0-9]+)?)", raw, re.IGNORECASE)
    return {
        "raw": raw,
        "load_average": [float(value) for value in match.groups()] if match else None,
        "exit_status": completed.returncode,
    }


def append_log(path: Path, title: str, body: str) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(f"\n===== {title} =====\n")
        stream.write(body)
        if body and not body.endswith("\n"):
            stream.write("\n")


def temporary_parent() -> Path:
    parent = Path(tempfile.gettempdir()).resolve()
    if parent == ROOT or ROOT in parent.parents:
        parent = Path("/tmp").resolve()
    if parent == ROOT or ROOT in parent.parents:
        raise MeasurementError(f"temporary directory is inside the repository: {parent}")
    return parent


def run_process(
    command: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    timeout_seconds: float,
) -> dict[str, Any]:
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        errors="replace",
        start_new_session=True,
    )
    timed_out = False
    cleanup_timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = process.communicate(timeout=2)
            except subprocess.TimeoutExpired as exc:
                cleanup_timed_out = True
                stdout = exc.stdout or ""
                stderr = exc.stderr or ""
                if isinstance(stdout, bytes):
                    stdout = stdout.decode(errors="replace")
                if isinstance(stderr, bytes):
                    stderr = stderr.decode(errors="replace")
    return {
        "exit_status": process.returncode,
        "timed_out": timed_out,
        "cleanup_timed_out": cleanup_timed_out,
        "stdout": stdout,
        "stderr": stderr,
    }


def operation(
    name: str,
    action: Callable[[], dict[str, Any]],
    log_path: Path,
) -> dict[str, Any]:
    before = uptime_snapshot()
    started = time.monotonic()
    try:
        details = action()
        status = details.pop("status", "success")
        error = None
    except Exception as exc:  # preserve the operation failure in the report
        details = {}
        status = "error"
        error = f"{type(exc).__name__}: {exc}"
        append_log(log_path, f"{name} error", error)
    result = {
        "name": name,
        "status": status,
        "uptime_before": before,
        "uptime_after": uptime_snapshot(),
        "elapsed_seconds": round(time.monotonic() - started, 3),
        **details,
    }
    if error:
        result["error"] = error
    return result


def read_until_marker(
    master_fd: int, marker: bytes, timeout: float
) -> tuple[bytes, int]:
    deadline = time.monotonic() + timeout
    captured = bytearray()
    cpr_queries_answered = 0
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        readable, _, _ = select.select([master_fd], [], [], min(remaining, 0.25))
        if not readable:
            continue
        try:
            chunk = os.read(master_fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        captured.extend(chunk)
        query_count = captured.count(CPR_QUERY)
        while cpr_queries_answered < query_count:
            os.write(master_fd, CPR_RESPONSE)
            cpr_queries_answered += 1
        if marker in captured:
            return bytes(captured), cpr_queries_answered
    preview = bytes(captured[-1500:]).decode("utf-8", errors="replace")
    raise MeasurementError(f"prompt marker {marker!r} was not reached; tail={preview!r}")


def process_rss_kib(pid: int) -> int:
    completed = subprocess.run(
        ["ps", "-o", "rss=", "-p", str(pid)],
        capture_output=True,
        text=True,
        errors="replace",
        timeout=5,
        check=False,
    )
    if completed.returncode != 0:
        raise MeasurementError(f"ps could not read RSS for pid {pid}: {completed.stderr.strip()}")
    try:
        return int(completed.stdout.strip())
    except ValueError as exc:
        raise MeasurementError(f"ps returned an invalid RSS value: {completed.stdout!r}") from exc


def stop_owned_process(process: subprocess.Popen[bytes], master_fd: int) -> None:
    try:
        os.close(master_fd)
    except OSError:
        pass
    try:
        os.killpg(process.pid, signal.SIGHUP)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired as exc:
            raise MeasurementError(
                f"owned process {process.pid} did not exit after PTY closure and SIGKILL"
            ) from exc


def measure_idle_process(
    command: list[str],
    *,
    marker: str,
    env: dict[str, str],
    sample_count: int,
    sample_interval: float,
    prompt_timeout: float,
) -> dict[str, Any]:
    master_fd, slave_fd = pty.openpty()
    window_size = struct.pack("HHHH", PTY_ROWS, PTY_COLUMNS, 0, 0)
    fcntl.ioctl(master_fd, termios.TIOCSWINSZ, window_size)
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, window_size)
    process: subprocess.Popen[bytes] | None = None
    startup_tail = ""
    try:
        process = subprocess.Popen(
            command,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            env=env,
            start_new_session=True,
        )
        os.close(slave_fd)
        slave_fd = -1
        startup, cpr_queries_answered = read_until_marker(
            master_fd, marker.encode("ascii"), prompt_timeout
        )
        startup_tail = startup[-1000:].decode("utf-8", errors="replace")
        rss_samples: list[int] = []
        for sample_index in range(sample_count):
            if sample_index:
                time.sleep(sample_interval)
            if process.poll() is not None:
                raise MeasurementError(f"process exited while idle with status {process.returncode}")
            rss_samples.append(process_rss_kib(process.pid))
        rss_mib = [value / 1024.0 for value in rss_samples]
        center = median(rss_mib)
        return {
            "status": "success" if center <= NFR07_RSS_LIMIT_MIB else "fail",
            "command": command,
            "ready_marker_seen": True,
            "pty_size_rows": PTY_ROWS,
            "pty_size_columns": PTY_COLUMNS,
            "cpr_queries_answered": cpr_queries_answered,
            "startup_output_tail": startup_tail,
            "rss_kib_samples": rss_samples,
            "rss_mib_median": round(center, 3),
            "rss_mib_max": round(max(rss_mib), 3),
            "target_mib": NFR07_RSS_LIMIT_MIB,
            "target_passed": center <= NFR07_RSS_LIMIT_MIB,
        }
    finally:
        if process is not None:
            stop_owned_process(process, master_fd)
        else:
            os.close(master_fd)
        if slave_fd >= 0:
            os.close(slave_fd)


def nfr07_operations(args: argparse.Namespace, log_path: Path) -> list[dict[str, Any]]:
    binary = args.binary.resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise MeasurementError(f"--binary is not an executable file: {binary}")
    marker = "NSHELL_NFR07_READY> "
    with tempfile.TemporaryDirectory(prefix="nshell-nfr07-", dir=temporary_parent()) as scratch:
        temp_root = Path(scratch)
        paths = {
            "HOME": temp_root / "home",
            "XDG_CONFIG_HOME": temp_root / "config",
            "XDG_DATA_HOME": temp_root / "data",
            "XDG_CACHE_HOME": temp_root / "cache",
            "XDG_STATE_HOME": temp_root / "state",
            "TMPDIR": temp_root / "tmp",
        }
        for path in paths.values():
            path.mkdir()
        base_env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "dumb",
            "LANG": "C",
            "LC_ALL": "C",
            **{name: str(path) for name, path in paths.items()},
            "NSHELL_GREETING": "",
            "NSHELL_AI_COMMAND": "/nonexistent",
        }
        target_env = {**base_env, "NSHELL_PROMPT": marker}
        shell_marker = "NSHELL_NFR07_CONTROL> "
        shell_env = {**base_env, "PS1": shell_marker}
        results = [
            operation(
                "nfr07_nshell_idle_rss",
                lambda: measure_idle_process(
                    [str(binary)],
                    marker=marker,
                    env=target_env,
                    sample_count=args.rss_samples,
                    sample_interval=args.rss_interval,
                    prompt_timeout=args.prompt_timeout,
                ),
                log_path,
            ),
            operation(
                "nfr07_bin_sh_control_idle_rss",
                lambda: measure_idle_process(
                    ["/bin/sh", "-i"],
                    marker=shell_marker,
                    env=shell_env,
                    sample_count=args.rss_samples,
                    sample_interval=args.rss_interval,
                    prompt_timeout=args.prompt_timeout,
                ),
                log_path,
            ),
        ]
        results[0]["same_host_control"] = "nfr07_bin_sh_control_idle_rss"
        results[1]["control_for"] = "nfr07_nshell_idle_rss"
        if results[0].get("rss_mib_median") is not None and results[1].get("rss_mib_median") is not None:
            results[0]["rss_mib_median_minus_control"] = round(
                results[0]["rss_mib_median"] - results[1]["rss_mib_median"], 3
            )
        return results


def seed_argument(raw: str) -> int:
    try:
        seed = int(raw, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("seed must be an integer, optionally prefixed with 0x") from exc
    if not 1 <= seed <= 0xFFFFFFFF:
        raise argparse.ArgumentTypeError("seed must be between 1 and 0xffffffff")
    return seed


def lisp_fuzz_source(seed: int, input_count: int, targets: set[str]) -> str:
    selected = "(" + " ".join(f":{target}" for target in sorted(targets)) + ")"
    return f'''(require :asdf)
(defparameter *nfr-root* (truename (uiop:getenv "NSHELL_ROOT")))
(load (merge-pathnames #P"scripts/asdf-runtime.lisp" *nfr-root*))
(nshell-configure-writable-asdf-output)
(asdf:initialize-source-registry
 (if (uiop:getenv "CL_SOURCE_REGISTRY")
     `(:source-registry (:directory ,*nfr-root*) :inherit-configuration)
     `(:source-registry (:directory ,*nfr-root*)
       (:tree ,(uiop:pathname-parent-directory-pathname *nfr-root*))
       :inherit-configuration)))
(asdf:load-system :nshell :force :all)

(defun nfr-next-byte (state)
  (setf (car state) (logand #xffffffff (logxor (car state) (ash (car state) 13))))
  (setf (car state) (logand #xffffffff (logxor (car state) (ash (car state) -17))))
  (setf (car state) (logand #xffffffff (logxor (car state) (ash (car state) 5))))
  (logand (car state) #xff))

(defun nfr-random-source (state)
  (let* ((length (mod (nfr-next-byte state) 17))
         (source (make-string length)))
    (dotimes (position length source)
      (setf (char source position) (code-char (nfr-next-byte state))))))

(defun nfr-fuzz-reader (count seed)
  (let ((state (list seed)))
    (dotimes (case-index count)
      (let ((source (nfr-random-source state)))
        (handler-case
            (let ((results (nshell.domain.parsing:read-submission source)))
              (unless (and (listp results)
                           (every #'nshell.domain.parsing:reader-result-p results))
                (error "Reader fuzz case ~D returned invalid results for ~S" case-index source)))
          (nshell.domain.parsing:sexp-reader-error () nil)))
      (when (and (plusp count) (zerop (mod (1+ case-index) (max 1 (min 10000 count)))))
        (format *error-output* "reader-fuzz-case=~D~%" (1+ case-index))
        (finish-output *error-output*))))
  count)

(defun nfr-fuzz-scanner (count seed)
  (let ((state (list seed)))
    (dotimes (case-index count)
      (let* ((source (nfr-random-source state))
             (result (nshell.domain.parsing:scan-input source :reader-context :bare-line))
             (status (and (nshell.domain.parsing:scan-result-p result)
                          (nshell.domain.parsing:scan-result-status result))))
        (unless (member status '(:complete :incomplete :invalid))
          (error "Scanner fuzz case ~D returned invalid status ~S for ~S" case-index status source)))
      (when (and (plusp count) (zerop (mod (1+ case-index) (max 1 (min 10000 count)))))
        (format *error-output* "scanner-fuzz-case=~D~%" (1+ case-index))
        (finish-output *error-output*))))
  count)

(defun nfr-fuzz-input-state (count seed)
  (let* ((state-seed (list seed))
         (current (nshell.presentation:make-input-state))
         (event-types #(:left :right :home :end :backspace :delete :ctrl-a :ctrl-b
                        :ctrl-e :ctrl-f :ctrl-k :ctrl-u :ctrl-w :ctrl-y :alt-y
                        :alt-t :alt-u :alt-l :alt-c :alt-s :alt-r :escape
                        :enter :tab :shift-tab :ctrl-underscore))
         (characters "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _./-[]|;&<>"))
    (dotimes (case-index count)
      (when (zerop (mod case-index 64))
        (let* ((length (mod (nfr-next-byte state-seed) 25))
               (buffer (make-string length)))
          (dotimes (position length)
            (setf (char buffer position)
                  (char characters (mod (nfr-next-byte state-seed) (length characters)))))
          (setf current
                (nshell.presentation:make-input-state
                 :buffer buffer
                 :cursor-pos (mod (nfr-next-byte state-seed) (1+ length))))))
      (let* ((old-buffer (copy-seq (nshell.presentation:input-state-buffer current)))
             (old-cursor (nshell.presentation:input-state-cursor-pos current))
             (type (if (zerop (mod (nfr-next-byte state-seed) 3))
                       :char
                       (aref event-types
                             (mod (nfr-next-byte state-seed) (length event-types)))))
             (event (if (eq type :char)
                        (nshell.domain.input:make-key-event
                         :char
                         (char characters (mod (nfr-next-byte state-seed) (length characters))))
                        (nshell.domain.input:make-key-event type)))
             (next (nshell.presentation:reduce-input-state current event))
             (buffer (nshell.presentation:input-state-buffer next))
             (cursor (nshell.presentation:input-state-cursor-pos next)))
        (unless (and (nshell.presentation:input-state-p next)
                     (stringp buffer)
                     (integerp cursor)
                     (<= 0 cursor (length buffer))
                     (string= old-buffer (nshell.presentation:input-state-buffer current))
                     (= old-cursor (nshell.presentation:input-state-cursor-pos current)))
          (error "Input-state fuzz case ~D broke a state invariant: event=~S state=~S"
                 case-index event next))
        (setf current next))
      (when (and (plusp count) (zerop (mod (1+ case-index) (max 1 (min 10000 count)))))
        (format *error-output* "input-state-fuzz-case=~D~%" (1+ case-index))
        (finish-output *error-output*)))
  count))

(let* ((selected '{selected})
       (reader-count (if (member :reader selected) (nfr-fuzz-reader {input_count} {seed}) 0))
       (scanner-count (if (member :scanner selected) (nfr-fuzz-scanner {input_count} {seed}) 0))
       (input-state-count (if (member :input-state selected)
                              (nfr-fuzz-input-state {input_count} {seed}) 0)))
  (format t "NFR08_COUNTS reader=~D scanner=~D input_state=~D seed=~D~%"
          reader-count scanner-count input-state-count {seed})
  (finish-output)
  (sb-ext:exit :code 0))
'''


def diagnostic_findings(
    stdout: str, stderr: str, scratch: Path, exit_status: int | None
) -> dict[str, Any]:
    text = f"{stdout}\n{stderr}"
    debugger = [pattern.pattern for pattern in DEBUGGER_PATTERNS if pattern.search(text)]
    dumps = [pattern.pattern for pattern in DUMP_PATTERNS if pattern.search(text)]
    core_files = sorted(path.name for path in scratch.glob("core*") if path.is_file())
    if core_files:
        dumps.append("core file created")
    if exit_status is not None and exit_status < 0:
        dumps.append(f"process terminated by signal {-exit_status}")
    return {
        "debugger_indicators": debugger,
        "dump_indicators": dumps,
        "core_files": core_files,
    }


def nfr08_operation(args: argparse.Namespace, log_path: Path) -> dict[str, Any]:
    selected = set(args.fuzz_target)
    with tempfile.TemporaryDirectory(
        prefix="nshell-nfr08-", dir=temporary_parent()
    ) as scratch_name:
        scratch = Path(scratch_name)
        runner = scratch / "fuzz-runner.lisp"
        runner.write_text(
            lisp_fuzz_source(args.seed, args.input_count, selected), encoding="utf-8"
        )
        asdf_output = scratch / "asdf-output"
        env = os.environ.copy()
        env["NSHELL_ASDF_OUTPUT_DIR"] = str(asdf_output)
        env["NSHELL_ROOT"] = str(ROOT)
        command = [
            "nix",
            "develop",
            str(ROOT),
            "-c",
            "env",
            f"NSHELL_ROOT={ROOT}",
            f"NSHELL_ASDF_OUTPUT_DIR={asdf_output}",
            "sbcl",
            "--script",
            str(runner),
        ]
        result = run_process(
            command,
            cwd=scratch,
            env=env,
            timeout_seconds=args.timeout_seconds,
        )
        combined = f"$ {' '.join(command)}\n\n{result['stdout']}\n{result['stderr']}"
        append_log(log_path, "nfr08 fixed-seed fuzz", combined)
        findings = diagnostic_findings(
            result["stdout"], result["stderr"], scratch, result["exit_status"]
        )
        counts_match = re.search(
            r"NFR08_COUNTS reader=(\d+) scanner=(\d+) input_state=(\d+) seed=(\d+)",
            result["stdout"],
        )
        counts = (
            {
                "reader": int(counts_match.group(1)),
                "scanner": int(counts_match.group(2)),
                "input_state": int(counts_match.group(3)),
                "seed": int(counts_match.group(4)),
            }
            if counts_match
            else None
        )
        expected = {
            "reader": args.input_count if "reader" in selected else 0,
            "scanner": args.input_count if "scanner" in selected else 0,
            "input_state": args.input_count if "input-state" in selected else 0,
            "seed": args.seed,
        }
        timed_out = result["timed_out"]
        required_targets = {"reader", "input-state"}
        required_targets_selected = required_targets <= selected
        required_input_count_reached = args.input_count == 100_000
        passed = (
            result["exit_status"] == 0
            and not timed_out
            and counts == expected
            and required_targets_selected
            and required_input_count_reached
            and not findings["debugger_indicators"]
            and not findings["dump_indicators"]
        )
        status = "success" if passed else "fail"
        return {
            "status": status,
            "command": command,
            "repository_test_selection": [],
            "repository_tests_selected": 0,
            "selection_kind": "direct fixed-seed fuzz loops; no nshell/test suite selection",
            "fuzz_targets": sorted(selected),
            "fuzz_target_count": len(selected),
            "required_targets": sorted(required_targets),
            "required_targets_selected": required_targets_selected,
            "input_count_per_target": args.input_count,
            "required_input_count_per_target": 100_000,
            "required_input_count_reached": required_input_count_reached,
            "seed": args.seed,
            "counts": counts,
            "expected_counts": expected,
            "exit_status": result["exit_status"],
            "timed_out": timed_out,
            "cleanup_timed_out": result["cleanup_timed_out"],
            **findings,
        }


def parse_added_source_lines(diff_text: str) -> dict[str, dict[int, str]]:
    added: dict[str, dict[int, str]] = {}
    current_path: str | None = None
    new_line = 0
    in_hunk = False
    file_header = re.compile(r"^diff --git a/(.+) b/(.+)$")
    hunk_header = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
    for line in diff_text.splitlines():
        match = file_header.match(line)
        if match:
            current_path = match.group(2)
            in_hunk = False
            continue
        match = hunk_header.match(line)
        if match:
            new_line = int(match.group(1))
            in_hunk = True
            continue
        if not in_hunk or current_path is None:
            continue
        if line.startswith("+") and not line.startswith("+++"):
            source_line = line[1:]
            if current_path.startswith("src/") and current_path.endswith(".lisp"):
                if source_line.strip() and not source_line.lstrip().startswith(";"):
                    added.setdefault(current_path, {})[new_line] = source_line
            new_line += 1
        elif line.startswith("-") and not line.startswith("---"):
            continue
        elif line.startswith("\\"):
            continue
        else:
            new_line += 1
    return added


def source_diff(base_revision: str, revision: str) -> dict[str, dict[int, str]]:
    command = [
        "jj",
        "--ignore-working-copy",
        "--color",
        "never",
        "diff",
        "--from",
        base_revision,
        "--to",
        revision,
        "--git",
        "--context",
        "0",
        "src",
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        errors="replace",
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        raise MeasurementError(f"jj source diff failed: {completed.stderr.strip()}")
    return parse_added_source_lines(completed.stdout)


def coverage_runner_source() -> str:
    return '''(require :asdf)
(require :sb-cover)
(let* ((report-symbol (find-symbol "REPORT" :sb-cover))
       (lcov-symbol (find-symbol "LCOV-REPORT" :sb-cover))
       (standard-report (and report-symbol (fboundp report-symbol)
                             (symbol-function report-symbol)))
       (lcov-report (and lcov-symbol (fboundp lcov-symbol)
                         (symbol-function lcov-symbol)))
       (lcov-path (uiop:getenv "NSHELL_NFR_COVERAGE_LCOV_PATH")))
  (when lcov-report
    (format *error-output* "NFR09_LCOV_API_AVAILABLE sb-cover:lcov-report~%"))
  (when (and standard-report lcov-report lcov-path)
    (sb-ext:without-package-locks
      (setf (symbol-function report-symbol)
            (lambda (directory &rest arguments)
              (prog1 (apply standard-report directory arguments)
                (funcall lcov-report (pathname lcov-path)))))))
  (unless lcov-report
    (format *error-output* "NFR09_LCOV_UNAVAILABLE sb-cover:lcov-report is not present~%"))
  (load #P"scripts/coverage.lisp"))
'''


def parse_coverage_summary(coverage_dir: Path) -> dict[str, Any] | None:
    summary = coverage_dir / "coverage-summary.json"
    if not summary.is_file():
        return None
    try:
        return json.loads(summary.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MeasurementError(f"invalid coverage summary {summary}: {exc}") from exc


def parse_lcov_new_code(
    lcov_path: Path,
    added_lines: dict[str, dict[int, str]],
    minimum_percent: float,
) -> dict[str, Any]:
    if not lcov_path.is_file():
        return {"status": "unavailable", "reason": "coverage runner did not produce LCOV data"}
    executable: dict[str, dict[int, int]] = {}
    current_file: str | None = None
    for line in lcov_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("SF:"):
            current_file = line[3:]
            executable.setdefault(current_file, {})
        elif line.startswith("DA:") and current_file is not None:
            fields = line[3:].split(",")
            if len(fields) >= 2:
                try:
                    executable[current_file][int(fields[0])] = int(fields[1])
                except ValueError:
                    continue

    covered = 0
    total = 0
    per_file: dict[str, dict[str, int]] = {}
    missing_lcov_files: list[str] = []
    for relative_path, changed in added_lines.items():
        candidates = {
            str((ROOT / relative_path).resolve()),
            str((ROOT / relative_path).resolve()).replace("\\", "/"),
            relative_path,
        }
        file_rows: dict[int, int] = {}
        for candidate in candidates:
            if candidate in executable:
                file_rows = executable[candidate]
                break
        else:
            missing_lcov_files.append(relative_path)
        line_hits = {number: file_rows[number] for number in changed if number in file_rows}
        file_total = len(line_hits)
        file_covered = sum(1 for hits in line_hits.values() if hits > 0)
        per_file[relative_path] = {"covered_lines": file_covered, "executable_added_lines": file_total}
        covered += file_covered
        total += file_total
    if missing_lcov_files:
        return {
            "status": "unavailable",
            "reason": "changed source files are absent from LCOV data",
            "missing_lcov_files": missing_lcov_files,
            "per_file": per_file,
        }
    if total == 0:
        return {
            "status": "unavailable",
            "reason": "no added executable src lines were found in LCOV data",
            "added_source_files": sorted(added_lines),
            "per_file": per_file,
        }
    percentage = 100.0 * covered / total
    return {
        "status": "success" if percentage >= minimum_percent else "fail",
        "metric": "LCOV executable added lines",
        "covered_lines": covered,
        "executable_added_lines": total,
        "line_percent": round(percentage, 2),
        "minimum_percent": minimum_percent,
        "target_passed": percentage >= minimum_percent,
        "per_file": per_file,
    }


def nfr09_operation(
    args: argparse.Namespace,
    log_path: Path,
    coverage_dir: Path,
) -> dict[str, Any]:
    if coverage_dir.exists():
        raise MeasurementError(f"coverage output directory already exists: {coverage_dir}")
    coverage_dir.mkdir(parents=True)
    lcov_path = coverage_dir / "coverage.lcov"
    scratch_context = tempfile.TemporaryDirectory(
        prefix="nshell-nfr09-", dir=temporary_parent()
    )
    scratch = Path(scratch_context.name)
    runner = scratch / "coverage-runner.lisp"
    runner.write_text(coverage_runner_source(), encoding="utf-8")
    asdf_output = scratch / "asdf-output"
    env = os.environ.copy()
    env.update(
        {
            "NSHELL_ASDF_OUTPUT_DIR": str(asdf_output),
            "NSHELL_COVERAGE_DIR": str(coverage_dir),
            "NSHELL_NFR_COVERAGE_LCOV_PATH": str(lcov_path),
            "NSHELL_COVERAGE_MIN": str(args.coverage_min),
        }
    )
    command = ["nix", "develop", "-c", "sbcl", "--script", str(runner)]
    try:
        result = run_process(
            command,
            cwd=ROOT,
            env=env,
            timeout_seconds=args.timeout_seconds,
        )
    finally:
        scratch_context.cleanup()
    append_log(
        log_path,
        "nfr09 overall and new-code coverage",
        f"$ {' '.join(command)}\n\n{result['stdout']}\n{result['stderr']}",
    )
    summary = parse_coverage_summary(coverage_dir)
    added_lines = source_diff(args.base_revision, args.revision or "@")
    new_code = parse_lcov_new_code(lcov_path, added_lines, args.new_code_min)
    overall_percent = None
    if summary is not None:
        overall_percent = summary.get("expression-percent")
    lcov_unavailable = "NFR09_LCOV_UNAVAILABLE" in result["stderr"]
    lcov_available = "NFR09_LCOV_API_AVAILABLE" in result["stderr"]
    overall_passed = (
        isinstance(overall_percent, (int, float))
        and overall_percent >= args.coverage_min
        and summary.get("minimum-passed") is True
        and summary.get("tests-passed") is True
    )
    lcov_ok = new_code.get("status") in ("success", "fail") and not lcov_unavailable
    status = "success"
    if result["timed_out"] or result["exit_status"] != 0 or not overall_passed:
        status = "fail"
    elif not lcov_ok or new_code.get("status") == "fail":
        status = "warning" if not lcov_ok else "fail"
    return {
        "status": status,
        "command": command,
        "revision": args.revision or "@",
        "base_revision": args.base_revision,
        "coverage_directory": str(coverage_dir),
        "exit_status": result["exit_status"],
        "timed_out": result["timed_out"],
        "cleanup_timed_out": result["cleanup_timed_out"],
        "coverage_summary": summary,
        "overall_expression_percent": overall_percent,
        "overall_metric_unit": "covered executable source expressions / executable source expressions",
        "overall_minimum_percent": args.coverage_min,
        "overall_target_passed": bool(overall_passed),
        "new_code": new_code,
        "new_code_metric_unit": "covered executable added source lines / executable added source lines",
        "lcov_api_available": lcov_available,
        "lcov_api_unavailable": lcov_unavailable,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure idle RSS, fixed-seed reader/input-state fuzz, and source coverage."
    )
    parser.add_argument(
        "--mode",
        choices=("all", "nfr07", "nfr08", "nfr09"),
        default="all",
        help="operation group; all groups run serially (default: all)",
    )
    parser.add_argument("--binary", type=Path, help="explicit nshell executable for NFR-07")
    parser.add_argument(
        "--revision",
        help="measured JJ revision selector and report label; defaults to @ for source operations",
    )
    parser.add_argument(
        "--base-revision",
        help="JJ base revision used to identify newly added src lines for NFR-09",
    )
    parser.add_argument("--output", required=True, type=Path, help="JSON report path outside the repository")
    parser.add_argument("--log", type=Path, help="operation log path; defaults to <output>.log")
    parser.add_argument(
        "--fuzz-target",
        action="append",
        choices=("reader", "scanner", "input-state"),
        help="NFR-08 target to fuzz; repeat to select several (default: all three)",
    )
    parser.add_argument("--seed", type=seed_argument, default=DEFAULT_SEED, help="fixed 32-bit fuzz seed")
    parser.add_argument(
        "--input-count", type=int, default=100_000, help="cases per selected NFR-08 target"
    )
    parser.add_argument("--rss-samples", type=int, default=5, help="RSS samples after the prompt")
    parser.add_argument("--rss-interval", type=float, default=1.0, help="seconds between RSS samples")
    parser.add_argument("--prompt-timeout", type=float, default=30.0, help="seconds to wait for each prompt")
    parser.add_argument(
        "--timeout-seconds", type=float, default=1800.0, help="timeout for each fuzz or coverage operation"
    )
    parser.add_argument(
        "--coverage-min", type=float, default=NFR09_COVERAGE_LIMIT, help="overall expression coverage minimum"
    )
    parser.add_argument(
        "--new-code-min", type=float, default=NFR09_NEW_CODE_LIMIT, help="new-code line coverage minimum"
    )
    args = parser.parse_args()
    if args.input_count <= 0:
        parser.error("--input-count must be positive")
    if args.rss_samples <= 0 or args.rss_interval < 0 or args.prompt_timeout <= 0:
        parser.error("RSS sample count and prompt timeout must be positive; interval cannot be negative")
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")
    if not 0 <= args.coverage_min <= 100 or not 0 <= args.new_code_min <= 100:
        parser.error("coverage thresholds must be between 0 and 100")
    if args.coverage_min < NFR09_COVERAGE_LIMIT or args.new_code_min < NFR09_NEW_CODE_LIMIT:
        parser.error("coverage thresholds cannot be lower than the NFR-09 requirements (85% and 90%)")
    if args.mode in ("all", "nfr07") and args.binary is None:
        parser.error("--binary is required for --mode nfr07 or all")
    if args.mode in ("all", "nfr09") and not args.base_revision:
        parser.error("--base-revision is required for --mode nfr09 or all")
    if args.fuzz_target is None:
        args.fuzz_target = ["reader", "scanner", "input-state"]
    if args.binary is not None:
        args.binary = args.binary.expanduser().resolve()
        if args.mode in ("all", "nfr07") and (
            not args.binary.is_file() or not os.access(args.binary, os.X_OK)
        ):
            parser.error(f"--binary is not an executable file: {args.binary}")
    args.output = args.output.expanduser().resolve()
    args.log = (args.log or Path(str(args.output) + ".log")).expanduser().resolve()
    for path in (args.output, args.log):
        if path == ROOT or ROOT in path.parents:
            parser.error(f"output files must be outside the repository: {path}")
    return args


def main() -> int:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.log.write_text("", encoding="utf-8")
    report: dict[str, Any] = {
        "revision": args.revision,
        "host": {"platform": platform.platform(), "machine": platform.machine()},
        "load_average_source": "uptime before and after each operation",
        "operations": [],
        "gaps": [],
    }
    if args.mode in ("all", "nfr07"):
        report["operations"].extend(nfr07_operations(args, args.log))
    if args.mode in ("all", "nfr08"):
        report["operations"].append(operation("nfr08_fuzz", lambda: nfr08_operation(args, args.log), args.log))
    if args.mode in ("all", "nfr09"):
        coverage_dir = args.output.parent / f"{args.output.stem}-coverage"
        report["operations"].append(
            operation(
                "nfr09_coverage",
                lambda: nfr09_operation(args, args.log, coverage_dir),
                args.log,
            )
        )
    statuses = [item["status"] for item in report["operations"]]
    report["status"] = (
        "success"
        if statuses and all(status == "success" for status in statuses)
        else "warning"
        if statuses and all(status in ("success", "warning") for status in statuses)
        else "error"
    )
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"report: {args.output}")
    print(f"log: {args.log}")
    print(f"status: {report['status']}")
    return 0 if report["status"] == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
