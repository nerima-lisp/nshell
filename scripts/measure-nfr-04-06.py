#!/usr/bin/env python3
"""Measure NFR-04, NFR-05, and NFR-06 with paired same-host controls."""

from __future__ import annotations

import argparse
import errno
import fcntl
import hashlib
import json
import os
import platform
import pty
import random
import re
import select
import shlex
import shutil
import signal
import statistics
import struct
import subprocess
import sys
import tempfile
import termios
import time
import uuid
from pathlib import Path
from typing import Callable

from nfr_thresholds import NFR_THRESHOLDS


NFR06_SAME_PROCESS_REPEAT_COUNT = 3
NFR06_COMPUTE_SIDECAR_ENV = "NSHELL_NFR06_CANDIDATE_COMPUTE_SIDECAR"
NFR05_DIAGNOSTIC_SIDECAR_ENV = "NSHELL_NFR05_DIAGNOSTIC_SIDECAR"
DEFAULT_BUFFER_SIZES = (1000,)
PROMPT_TIMEOUT_SECONDS = 15
OUTPUT_TIMEOUT_SECONDS = 5
CPR_QUERY = b"\x1b[6n"
CPR_RESPONSE = b"\x1b[1;1R"
CURSOR_RESTORE = b"\x1b8"
PROMPT_CURSOR_SHAPE = b"\x1b[0 q"
BRACKETED_PASTE_START = b"\x1b[200~"
BRACKETED_PASTE_END = b"\x1b[201~"
ANSI_SEQUENCE_RE = re.compile(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[@-_])")
FIXTURE_FILE_COUNT = 20_000
SUGGESTION_KEY_SEQUENCE = "source item-"
CHILD_REAP_TIMEOUT_SECONDS = 0.5
NFR06_TERMINAL_SIZE = (10, 80)
NFR06_VISIBLE_CANDIDATE_COUNT = 28
COMPLETION_PAGER_FOOTER = b"arrows move, Enter accepts, Esc/Ctrl-C cancels"


def uptime_record() -> dict[str, object]:
    raw = subprocess.run(
        ["uptime"], check=True, capture_output=True, text=True
    ).stdout.strip()
    match = re.search(r"load averages?:\s*([0-9.]+)", raw)
    if match is None:
        raise RuntimeError(f"cannot parse one-minute load from uptime: {raw}")
    return {"raw": raw, "load_average_1m": float(match.group(1))}


def percentile_nearest_rank(values: list[float], percentile: float) -> float:
    if not values:
        raise ValueError("percentile requires at least one value")
    ordered = sorted(values)
    rank = max(1, (len(ordered) * int(percentile * 100) + 99) // 100)
    return ordered[rank - 1]


def visible_terminal_text(data: bytes) -> bytes:
    return ANSI_SEQUENCE_RE.sub(b"", data)


def prompt_render_complete(
    output: bytes,
    marker: bytes,
    *,
    require_cursor_restore: bool = True,
) -> bool:
    marker_start = output.rfind(marker)
    if marker_start < 0:
        return False
    if not require_cursor_restore:
        return True
    marker_end = marker_start + len(marker)
    cursor_restore = output.find(CURSOR_RESTORE, marker_end)
    if cursor_restore < 0:
        return False
    return output.find(
        PROMPT_CURSOR_SHAPE,
        cursor_restore + len(CURSOR_RESTORE),
    ) >= 0


def rendered_x_count(data: bytes, start: int, marker: bytes) -> int:
    output = data[start:]
    marker_index = output.rfind(marker)
    if marker_index < 0:
        return -1
    output = output[marker_index + len(marker):]
    return visible_terminal_text(output).count(b"x")


def strip_terminal_sequences(data: bytes) -> bytes:
    return ANSI_SEQUENCE_RE.sub(b"", data)


def validate_executable(path_text: str, label: str) -> Path:
    path = Path(path_text).expanduser().resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f"{label} must be an executable file: {path}")
    return path


def ensure_outside_repository(path: Path, label: str) -> None:
    repository_root = Path(__file__).resolve().parent.parent
    if path == repository_root or repository_root in path.parents:
        raise ValueError(f"{label} must be outside the repository: {path}")


def find_git_root(path: Path) -> Path | None:
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("git is required to validate --git-fixture")
    result = subprocess.run(
        [git, "-C", str(path), "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip()).resolve()


def validate_fixtures(args: argparse.Namespace) -> dict[str, object]:
    plain_fixture = Path(args.plain_fixture).expanduser().resolve()
    completion_fixture = Path(args.completion_fixture).expanduser().resolve()
    for fixture, label in (
        (plain_fixture, "--plain-fixture"),
        (completion_fixture, "--completion-fixture"),
    ):
        if not fixture.is_dir():
            raise ValueError(f"{label} must be an existing directory: {fixture}")
        ensure_outside_repository(fixture, label)

    if find_git_root(plain_fixture) is not None:
        raise ValueError("--plain-fixture must not be inside a Git working tree")

    git_fixture = None
    git_root = None
    git_branch = None
    if args.start_from == "nfr04":
        if not args.git_fixture:
            raise ValueError("--git-fixture is required when --from is nfr04")
        git_fixture = Path(args.git_fixture).expanduser().resolve()
        if not git_fixture.is_dir():
            raise ValueError(f"--git-fixture must be an existing directory: {git_fixture}")
        ensure_outside_repository(git_fixture, "--git-fixture")
        git_root = find_git_root(git_fixture)
        if git_root is None:
            raise ValueError("--git-fixture must be inside a Git working tree")
        branch_result = subprocess.run(
            [shutil.which("git") or "git", "-C", str(git_fixture), "branch", "--show-current"],
            check=True,
            capture_output=True,
            text=True,
        )
        git_branch = branch_result.stdout.strip()

    entries = list(completion_fixture.iterdir())
    if len(entries) != FIXTURE_FILE_COUNT:
        raise ValueError(
            f"--completion-fixture must contain exactly {FIXTURE_FILE_COUNT} entries; "
            f"found {len(entries)}"
        )
    if any(not entry.is_file() or not entry.name.startswith(args.completion_prefix) for entry in entries):
        raise ValueError(
            "all --completion-fixture entries must be files whose names start with "
            f"{args.completion_prefix!r}"
        )

    return {
        "plain_fixture": str(plain_fixture),
        "git_fixture": str(git_fixture) if git_fixture is not None else None,
        "git_root": str(git_root) if git_root is not None else None,
        "git_branch": git_branch,
        "completion_fixture": str(completion_fixture),
        "completion_entries": len(entries),
        "completion_prefix": args.completion_prefix,
    }


def child_environment(
    home: Path,
    prompt: str | None = None,
    git_prompt: bool = False,
    candidate_compute_sidecar: Path | None = None,
    nfr05_diagnostic_sidecar: Path | None = None,
) -> dict[str, str]:
    for name in ("config", "data", "state", "cache", "tmp"):
        (home / name).mkdir(parents=True, exist_ok=True)
    env = {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / "config"),
        "XDG_DATA_HOME": str(home / "data"),
        "XDG_STATE_HOME": str(home / "state"),
        "XDG_CACHE_HOME": str(home / "cache"),
        "TMPDIR": str(home / "tmp"),
        "TERM": "xterm-256color",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "NSHELL_GREETING": "",
        "NSHELL_AI_COMMAND": "/nonexistent",
    }
    if prompt is not None:
        env["NSHELL_PROMPT"] = ("{git} " if git_prompt else "") + prompt
    if candidate_compute_sidecar is not None:
        env[NFR06_COMPUTE_SIDECAR_ENV] = str(candidate_compute_sidecar)
    if nfr05_diagnostic_sidecar is not None:
        env[NFR05_DIAGNOSTIC_SIDECAR_ENV] = str(nfr05_diagnostic_sidecar)
    return env


class PtySession:
    def __init__(
        self,
        argv: list[str],
        cwd: Path,
        env: dict[str, str],
        terminal_size: tuple[int, int] = (24, 100),
    ):
        self.data = bytearray()
        self.responses_sent = 0
        self.argv = argv
        self.cwd = cwd
        self.env = env
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            try:
                os.chdir(cwd)
                os.execve(argv[0], argv, env)
            except OSError as error:
                os.write(2, f"cannot exec {argv[0]}: {error}\n".encode())
                os._exit(127)
        rows, columns = terminal_size
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))

    def _read_once(self, timeout_seconds: float) -> bool:
        ready, _, _ = select.select([self.master], [], [], max(0.0, timeout_seconds))
        if not ready:
            return False
        try:
            chunk = os.read(self.master, 8192)
        except OSError as error:
            if error.errno == errno.EIO:
                raise RuntimeError(f"PTY child exited; tail={bytes(self.data[-800:])!r}") from error
            raise
        if not chunk:
            raise RuntimeError(f"PTY child closed its output; tail={bytes(self.data[-800:])!r}")
        self.data.extend(chunk)
        self._respond_to_cursor_queries()
        return True

    def _respond_to_cursor_queries(self) -> None:
        query_count = self.data.count(CPR_QUERY)
        while self.responses_sent < query_count:
            os.write(self.master, CPR_RESPONSE)
            self.responses_sent += 1

    def reset_transcript(self) -> None:
        self.data.clear()
        self.responses_sent = 0

    def wait_for_marker(self, marker: bytes, occurrence: int = 1, timeout_seconds: float = PROMPT_TIMEOUT_SECONDS) -> int:
        deadline = time.monotonic() + timeout_seconds
        while self.data.count(marker) < occurrence:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"prompt marker timed out; tail={bytes(self.data[-800:])!r}")
            self._read_once(remaining)
        if self.data.count(marker) < occurrence:
            raise RuntimeError(f"PTY exited before prompt marker; tail={bytes(self.data[-800:])!r}")
        return time.monotonic_ns()

    def wait_for_output(self, predicate: Callable[[bytes], bool], timeout_seconds: float = OUTPUT_TIMEOUT_SECONDS) -> int:
        deadline = time.monotonic() + timeout_seconds
        while not predicate(bytes(self.data)):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"PTY output timed out; tail={bytes(self.data[-800:])!r}")
            self._read_once(remaining)
        if not predicate(bytes(self.data)):
            raise RuntimeError(f"PTY exited before expected output; tail={bytes(self.data[-800:])!r}")
        return time.monotonic_ns()

    def wait_for_completion_render(
        self,
        start: int,
        marker: bytes,
        expected_candidates: set[bytes] | None = None,
        timeout_seconds: float = OUTPUT_TIMEOUT_SECONDS,
    ) -> dict[str, int | None]:
        deadline = time.monotonic() + timeout_seconds
        marker_search_offset = start
        marker_end: int | None = None
        cursor_restore_search_offset: int | None = None
        prompt_shape_search_offset: int | None = None
        candidate_scan_offset = start
        candidate_pending = b""
        candidate_output_first_visible_ns: int | None = None
        while True:
            if expected_candidates and candidate_output_first_visible_ns is None:
                chunk = candidate_pending + bytes(self.data[candidate_scan_offset:])
                candidate_scan_offset = len(self.data)
                if chunk:
                    lines = chunk.split(b"\n")
                    if chunk.endswith(b"\n"):
                        candidate_pending = b""
                    else:
                        candidate_pending = lines.pop()
                    for line in lines:
                        candidate = visible_terminal_text(line).rstrip(b"\r")
                        if candidate in expected_candidates:
                            candidate_output_first_visible_ns = time.monotonic_ns()
                            break
            if marker_end is None:
                marker_start = self.data.find(marker, marker_search_offset)
                if marker_start < 0:
                    marker_search_offset = max(start, len(self.data) - len(marker) + 1)
                else:
                    marker_end = marker_start + len(marker)
                    cursor_restore_search_offset = marker_end
            if marker_end is not None and cursor_restore_search_offset is not None:
                cursor_restore = self.data.find(CURSOR_RESTORE, cursor_restore_search_offset)
                if cursor_restore < 0:
                    cursor_restore_search_offset = max(
                        marker_end, len(self.data) - len(CURSOR_RESTORE) + 1
                    )
                else:
                    prompt_shape_search_offset = cursor_restore + len(CURSOR_RESTORE)
                    cursor_restore_search_offset = None
            if prompt_shape_search_offset is not None:
                if self.data.find(PROMPT_CURSOR_SHAPE, prompt_shape_search_offset) >= 0:
                    return {
                        "prompt_render_complete_ns": time.monotonic_ns(),
                        "candidate_output_first_visible_ns": candidate_output_first_visible_ns,
                    }
                prompt_shape_search_offset = max(
                    prompt_shape_search_offset,
                    len(self.data) - len(PROMPT_CURSOR_SHAPE) + 1,
                )
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(
                    f"NFR-06 completion prompt timed out; tail={bytes(self.data[-800:])!r}"
                )
            self._read_once(remaining)

    def pump_for(self, duration_seconds: float) -> None:
        deadline = time.monotonic() + duration_seconds
        while time.monotonic() < deadline:
            if not self._read_once(deadline - time.monotonic()):
                break

    def close(self) -> None:
        reaped = False
        cleanup_errors: list[str] = []
        signal_errors: list[str] = []

        def wait_for_child() -> bool:
            try:
                return self._wait_for_child(CHILD_REAP_TIMEOUT_SECONDS)
            except OSError as error:
                cleanup_errors.append(f"waitpid failed: {error}")
                return False

        def wait_for_child_immediately() -> bool:
            try:
                return self._wait_for_child(0)
            except OSError as error:
                cleanup_errors.append(f"waitpid failed: {error}")
                return False

        def signal_child(signal_number: int) -> None:
            try:
                self._signal_child(signal_number)
            except OSError as error:
                signal_errors.append(f"signal {signal_number} failed: {error}")

        def close_master() -> None:
            try:
                self._close_master()
            except OSError as error:
                cleanup_errors.append(f"PTY master close failed: {error}")

        try:
            signal_child(signal.SIGTERM)
            reaped = wait_for_child()
            close_master()
            if not reaped:
                reaped = wait_for_child()
            if not reaped:
                reaped = wait_for_child_immediately()
                if not reaped:
                    signal_child(signal.SIGKILL)
                    reaped = wait_for_child()
        finally:
            close_master()
        if not reaped:
            errors_found = cleanup_errors + signal_errors
            errors = f"; cleanup errors: {'; '.join(errors_found)}" if errors_found else ""
            raise RuntimeError(
                f"PTY child {self.pid} was not reaped after SIGTERM, PTY master closure, "
                f"and SIGKILL; it may still be running{errors}"
            )
        if cleanup_errors:
            raise RuntimeError(
                f"PTY child {self.pid} was reaped but cleanup reported: {'; '.join(cleanup_errors)}"
            )

    def _wait_for_child(self, timeout_seconds: float) -> bool:
        deadline = time.monotonic() + timeout_seconds
        while True:
            try:
                child, _ = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                return True
            except InterruptedError:
                continue
            if child == self.pid:
                return True
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            time.sleep(min(0.01, remaining))

    def _close_master(self) -> None:
        if self.master < 0:
            return
        master = self.master
        self.master = -1
        os.close(master)

    def _signal_child(self, signal_number: int) -> None:
        try:
            os.killpg(self.pid, signal_number)
        except ProcessLookupError:
            try:
                os.kill(self.pid, signal_number)
            except ProcessLookupError:
                pass


def run_prompt_sample(
    executable: Path,
    cwd: Path,
    home_root: Path,
    marker_text: str,
    git_prompt: bool,
    control_shell: bool,
    settle_seconds: float,
) -> dict[str, object]:
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    env = child_environment(home, marker_text, git_prompt=git_prompt) if not control_shell else child_environment(home)
    if control_shell:
        env["PS1"] = marker_text + " "
        argv = [str(executable), "-i"]
    else:
        argv = [str(executable)]
    session = PtySession(argv, cwd, env)
    try:
        session.wait_for_marker(marker)
        session.pump_for(settle_seconds)
        response_start = len(session.data)
        markers_before = session.data.count(marker)
        start_ns = time.monotonic_ns()
        if os.write(session.master, b"\r") != 1:
            raise RuntimeError("NFR-04 Enter key was not fully written to the PTY")
        end_ns = session.wait_for_output(
            lambda data: prompt_render_complete(
                data[response_start:],
                marker,
                require_cursor_restore=not control_shell,
            )
        )
        return {
            "latency_ms": (end_ns - start_ns) / 1_000_000,
            "cursor_queries": session.responses_sent,
            "prompt_markers_before": markers_before,
            "prompt_markers_seen": session.data.count(marker),
            "fresh_prompt_seen": marker in session.data[response_start:],
            "prompt_cursor_restored": CURSOR_RESTORE in session.data[response_start:],
            "prompt_render_complete_detected": PROMPT_CURSOR_SHAPE in session.data[response_start:],
        }
    finally:
        session.close()


def run_redraw_sample(
    executable: Path,
    cwd: Path,
    home_root: Path,
    marker_text: str,
    buffer_length: int,
    settle_seconds: float,
    diagnostic_sidecar: Path | None = None,
    native_capture: Callable[[int], Callable[[], dict[str, object]]] | None = None,
) -> dict[str, object]:
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    if diagnostic_sidecar is not None:
        diagnostic_sidecar.parent.mkdir(parents=True, exist_ok=True)
        diagnostic_sidecar.unlink(missing_ok=True)
    env = child_environment(
        home,
        marker_text,
        nfr05_diagnostic_sidecar=diagnostic_sidecar,
    )
    argv = [str(executable)]
    session = PtySession(argv, cwd, env)
    finish_native_capture = None
    native_capture_result = None
    preloaded_length = buffer_length - 1
    preloaded_buffer = b"x" * preloaded_length
    try:
        session.wait_for_marker(marker)
        session.pump_for(settle_seconds)
        input_start = len(session.data)
        if preloaded_buffer:
            os.write(
                session.master,
                BRACKETED_PASTE_START + preloaded_buffer + BRACKETED_PASTE_END,
            )
            session.wait_for_output(
                lambda data: rendered_x_count(data, input_start, marker) == preloaded_length,
                timeout_seconds=OUTPUT_TIMEOUT_SECONDS,
            )
        session.pump_for(0.05)
        response_start = len(session.data)
        responses_before = session.responses_sent
        if native_capture is not None:
            finish_native_capture = native_capture(session.pid)
        start_ns = time.monotonic_ns()
        keypress_realtime_ns = (
            time.time_ns()
            if diagnostic_sidecar is not None or native_capture is not None
            else None
        )
        if os.write(session.master, b"x") != 1:
            raise RuntimeError("NFR-05 keypress was not fully written to the PTY")
        end_ns = session.wait_for_output(
            lambda data: (
                prompt_render_complete(data[response_start:], marker)
                and rendered_x_count(data, response_start, marker) == buffer_length
            ),
            timeout_seconds=OUTPUT_TIMEOUT_SECONDS,
        )
        redraw_complete_realtime_ns = (
            time.time_ns()
            if diagnostic_sidecar is not None or native_capture is not None
            else None
        )
        response = bytes(session.data[response_start:])
        visible_response = visible_terminal_text(response)
        response_buffer_characters = rendered_x_count(session.data, response_start, marker)
        if (
            not prompt_render_complete(response, marker)
            or marker not in visible_response
            or response_buffer_characters != buffer_length
        ):
            raise RuntimeError("NFR-05 keypress did not redraw the prompt and full input buffer")
        result = {
            "latency_ms": (end_ns - start_ns) / 1_000_000,
            "keypress": "x",
            "preloaded_buffer_characters": preloaded_length,
            "redrawn_prompt_seen": marker in visible_response,
            "prompt_cursor_restored": CURSOR_RESTORE in response,
            "prompt_render_complete_detected": PROMPT_CURSOR_SHAPE in response,
            "redrawn_buffer_characters": response_buffer_characters,
            "response_bytes": len(response),
            "cursor_queries": session.responses_sent,
        }
        if diagnostic_sidecar is not None:
            result["cursor_query_count"] = response.count(CPR_QUERY)
            result["cursor_response_count"] = session.responses_sent - responses_before
            deadline = time.monotonic() + 5.0
            while time.monotonic() < deadline:
                try:
                    diagnostic = json.loads(diagnostic_sidecar.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    time.sleep(0.001)
                    continue
                if (
                    diagnostic.get("schema_version") != 2
                    or diagnostic.get("record") != "nfr05-render-diagnostic"
                ):
                    raise RuntimeError("NFR-05 diagnostic sidecar has an unexpected schema")
                result["diagnostics"] = diagnostic
                break
            else:
                raise TimeoutError("NFR-05 diagnostic sidecar was not written after redraw")
            result["keypress_realtime_ns"] = keypress_realtime_ns
            result["redraw_complete_realtime_ns"] = redraw_complete_realtime_ns
        if finish_native_capture is not None:
            native_capture_result = finish_native_capture()
            capture_started_ns = native_capture_result.get("capture_started_monotonic_ns")
            capture_finished_ns = native_capture_result.get("capture_finished_monotonic_ns")
            if (
                isinstance(keypress_realtime_ns, int)
                and isinstance(redraw_complete_realtime_ns, int)
            ):
                event_window = {
                    "keypress_monotonic_ns": start_ns,
                    "redraw_complete_monotonic_ns": end_ns,
                    "redraw_duration_ns": end_ns - start_ns,
                    "keypress_realtime_ns": keypress_realtime_ns,
                    "redraw_complete_realtime_ns": redraw_complete_realtime_ns,
                    "redraw_realtime_duration_ns": (
                        redraw_complete_realtime_ns - keypress_realtime_ns
                    ),
                    "wall_clock_source": "Python time.time_ns sampled adjacent to the keypress and redraw completion",
                }
            else:
                event_window = {
                    "keypress_monotonic_ns": start_ns,
                    "redraw_complete_monotonic_ns": end_ns,
                    "redraw_duration_ns": end_ns - start_ns,
                    "keypress_realtime_ns": None,
                    "redraw_complete_realtime_ns": None,
                    "wall_clock_source": "not recorded",
                }
            if isinstance(capture_started_ns, int) and isinstance(capture_finished_ns, int):
                overlap_start_ns = max(capture_started_ns, start_ns)
                overlap_end_ns = min(capture_finished_ns, end_ns)
                event_window.update(
                    {
                        "capture_started_before_keypress": capture_started_ns <= start_ns,
                        "capture_finished_after_redraw": capture_finished_ns >= end_ns,
                        "capture_process_overlap_ns": max(0, overlap_end_ns - overlap_start_ns),
                        "overlap_evidence": (
                            "monotonic process start/finish bounds; platform sample stack timestamps "
                            "are not exposed"
                        ),
                    }
                )
            native_capture_result["event_window"] = event_window
            result["native_capture"] = native_capture_result
            diagnostic = result.get("diagnostics")
            if isinstance(diagnostic, dict):
                if native_capture_result.get("lock_wait_ns") is not None:
                    diagnostic["lock_wait_ns"] = native_capture_result["lock_wait_ns"]
                diagnostic["lock_wait_scope"] = native_capture_result.get(
                    "lock_wait_scope", "unavailable"
                )
                diagnostic["lock_wait_source"] = native_capture_result.get(
                    "lock_wait_source", "native capture"
                )
        return result
    finally:
        if finish_native_capture is not None and native_capture_result is None:
            finish_native_capture()
        session.close()


def verify_redraw_support(
    executable: Path,
    cwd: Path,
    home_root: Path,
    marker_text: str,
) -> dict[str, object]:
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    env = child_environment(home, marker_text)
    argv = [str(executable)]
    probe_length = 32
    preloaded_length = probe_length - 1
    probe_buffer = b"x" * preloaded_length
    session = PtySession(argv, cwd, env)
    try:
        session.wait_for_marker(marker)
        session.pump_for(0.05)
        input_start = len(session.data)
        if probe_buffer:
            os.write(
                session.master,
                BRACKETED_PASTE_START + probe_buffer + BRACKETED_PASTE_END,
            )
            session.wait_for_output(
                lambda data: rendered_x_count(data, input_start, marker) == preloaded_length
            )
        session.pump_for(0.05)
        response_start = len(session.data)
        os.write(session.master, b"x")
        session.wait_for_output(
            lambda data: (
                prompt_render_complete(data[response_start:], marker)
                and rendered_x_count(data, response_start, marker) == probe_length
            )
        )
        response = bytes(session.data[response_start:])
        visible_response = visible_terminal_text(response)
        response_buffer_characters = rendered_x_count(session.data, response_start, marker)
        if (
            not prompt_render_complete(response, marker)
            or marker not in visible_response
            or response_buffer_characters != probe_length
        ):
            raise RuntimeError("NFR-05 preflight keypress did not redraw the prompt and full input buffer")
        return {
            "supported": True,
            "trigger": "one-character insertion",
            "probe_buffer_length": probe_length,
            "redrawn_prompt_seen": marker in visible_response,
            "prompt_cursor_restored": CURSOR_RESTORE in response,
            "redrawn_buffer_characters": response_buffer_characters,
            "response_bytes": len(response),
            "cursor_queries": session.responses_sent,
        }
    finally:
        session.close()


def completion_command(binary: Path, fixture: Path, prefix: str) -> list[str]:
    query = f"source {fixture / prefix}"
    command_line = f"complete -C {shlex.quote(query)}"
    return [str(binary), "--no-config", "--command", command_line]


def completion_reference_output(
    binary: Path,
    fixture: Path,
    prefix: str,
    home_root: Path,
) -> bytes:
    home = home_root / f"home-{uuid.uuid4().hex}"
    env = child_environment(home)
    result = subprocess.run(
        completion_command(binary, fixture, prefix),
        cwd=fixture,
        env=env,
        check=False,
        capture_output=True,
    )
    if result.returncode != 0 or result.stderr:
        raise RuntimeError(
            f"completion command failed: status={result.returncode}, stderr={result.stderr[-500:]!r}"
        )
    rows = result.stdout.splitlines()
    if len(rows) != FIXTURE_FILE_COUNT or len(set(rows)) != FIXTURE_FILE_COUNT:
        raise RuntimeError(
            f"completion returned {len(rows)} rows and {len(set(rows))} unique rows; "
            f"expected {FIXTURE_FILE_COUNT} of each"
        )
    return result.stdout


def read_candidate_compute_measurement(sidecar_path: Path) -> dict[str, float]:
    fields = sidecar_path.read_text(encoding="ascii").split()
    if len(fields) != 3:
        raise RuntimeError(
            "NFR-06 candidate-compute sidecar must contain compute ticks, "
            "output-preparation ticks, and time units"
        )
    try:
        compute_ticks, output_preparation_ticks, time_units = (int(field) for field in fields)
    except ValueError as error:
        raise RuntimeError("NFR-06 candidate-compute sidecar contains a non-integer value") from error
    if min(compute_ticks, output_preparation_ticks) < 0 or time_units <= 0:
        raise RuntimeError("NFR-06 candidate-compute sidecar contains an invalid duration")
    return {
        "candidate_compute_duration_ms": compute_ticks * 1000 / time_units,
        "candidate_output_preparation_duration_ms": output_preparation_ticks * 1000 / time_units,
    }


def run_interactive_completion_round(
    session: PtySession,
    command_bytes: bytes,
    marker: bytes,
    expected_output: bytes,
    candidate_compute_sidecar: Path | None = None,
) -> dict[str, object]:
    paste = BRACKETED_PASTE_START + command_bytes + BRACKETED_PASTE_END
    input_start = len(session.data)
    if os.write(session.master, paste) != len(paste):
        raise RuntimeError("NFR-06 completion command was not fully written to the PTY")
    session.wait_for_output(
        lambda data: command_bytes in strip_terminal_sequences(data[input_start:])
    )
    session.pump_for(0.05)
    response_start = len(session.data)
    started_ns = time.monotonic_ns()
    if os.write(session.master, b"\r") != 1:
        raise RuntimeError("NFR-06 completion trigger was not fully written to the PTY")

    expected_rows = expected_output.splitlines()
    expected_candidates = set(expected_rows)
    render_timing = session.wait_for_completion_render(
        response_start,
        marker,
        expected_candidates if candidate_compute_sidecar is not None else None,
    )
    end_ns = int(render_timing["prompt_render_complete_ns"])
    response = bytes(session.data[response_start:])
    visible_lines = [
        visible_terminal_text(line).rstrip(b"\r")
        for line in response.splitlines()
    ]
    candidate_rows = [line for line in visible_lines if line in expected_candidates]
    if candidate_rows != expected_rows:
        first_mismatch = next(
            (
                index
                for index, (actual, expected) in enumerate(zip(candidate_rows, expected_rows))
                if actual != expected
            ),
            min(len(candidate_rows), len(expected_rows)),
        )
        raise RuntimeError(
            "NFR-06 interactive completion output did not match the ordered reference candidates: "
            f"observed {len(candidate_rows)} rows, expected {len(expected_rows)}, "
            f"first mismatch at row {first_mismatch}"
        )
    if not prompt_render_complete(response, marker):
        raise RuntimeError("NFR-06 completion did not return to a fully rendered prompt")
    observed_candidate_output = b"\n".join(candidate_rows)
    result: dict[str, object] = {
        "latency_ms": (end_ns - started_ns) / 1_000_000,
        "candidate_count": FIXTURE_FILE_COUNT,
        "output_bytes": len(expected_output),
        "output_sha256": hashlib.sha256(observed_candidate_output).hexdigest(),
        "response_bytes": len(response),
        "prompt_cursor_restored": CURSOR_RESTORE in response,
        "prompt_render_complete_detected": PROMPT_CURSOR_SHAPE in response,
        "observed_candidate_count": len(candidate_rows),
        "cursor_queries": session.responses_sent,
    }
    if candidate_compute_sidecar is not None:
        candidate_output_start_ns = render_timing["candidate_output_first_visible_ns"]
        if candidate_output_start_ns is None:
            raise RuntimeError("NFR-06 diagnostic did not observe a visible expected candidate row")
        result["candidate_output_to_prompt_ms"] = (
            end_ns - candidate_output_start_ns
        ) / 1_000_000
        result.update(read_candidate_compute_measurement(candidate_compute_sidecar))
    return result


def run_interactive_completion_sample(
    binary: Path,
    fixture: Path,
    prefix: str,
    home_root: Path,
    expected_output: bytes,
    settle_seconds: float,
    candidate_compute_diagnostics: bool = False,
) -> dict[str, object]:
    marker_text = f"NSHELL_NFR06_{uuid.uuid4().hex}_PROMPT"
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    candidate_compute_sidecar = home / "tmp" / "nfr06-candidate-compute"
    environment = child_environment(
        home,
        marker_text,
        candidate_compute_sidecar=(
            candidate_compute_sidecar if candidate_compute_diagnostics else None
        ),
    )
    session: PtySession | None = None
    command_bytes = completion_command(binary, fixture, prefix)[-1].encode()
    try:
        session = PtySession([str(binary), "--no-config"], fixture, environment)
        session.wait_for_marker(marker)
        session.pump_for(settle_seconds)
        if candidate_compute_diagnostics:
            candidate_compute_sidecar.unlink(missing_ok=True)


        first = run_interactive_completion_round(
            session,
            command_bytes,
            marker,
            expected_output,
            candidate_compute_sidecar=(
                candidate_compute_sidecar if candidate_compute_diagnostics else None
            ),
        )
        repeated_latencies = []
        repeated_candidate_compute_durations = []
        repeated_candidate_output_preparation_durations = []
        repeated_candidate_output_to_prompt_durations = []
        for _ in range(NFR06_SAME_PROCESS_REPEAT_COUNT):
            session.reset_transcript()
            if candidate_compute_diagnostics:
                candidate_compute_sidecar.unlink(missing_ok=True)
            repeated = run_interactive_completion_round(
                session,
                command_bytes,
                marker,
                expected_output,
                candidate_compute_sidecar=(
                    candidate_compute_sidecar if candidate_compute_diagnostics else None
                ),
            )
            repeated_latencies.append(float(repeated["latency_ms"]))
            if candidate_compute_diagnostics:
                repeated_candidate_compute_durations.append(
                    float(repeated["candidate_compute_duration_ms"])
                )
                repeated_candidate_output_preparation_durations.append(
                    float(repeated["candidate_output_preparation_duration_ms"])
                )
                repeated_candidate_output_to_prompt_durations.append(
                    float(repeated["candidate_output_to_prompt_ms"])
                )
        result: dict[str, object] = {
            "latency_ms": first["latency_ms"],
            "trigger": "Enter on an already-visible complete -C command",
            "candidate_count": first["candidate_count"],
            "output_bytes": first["output_bytes"],
            "output_sha256": first["output_sha256"],
            "response_bytes": first["response_bytes"],
            "prompt_cursor_restored": first["prompt_cursor_restored"],
            "prompt_render_complete_detected": first["prompt_render_complete_detected"],
            "observed_candidate_count": first["observed_candidate_count"],
            "cursor_queries": first["cursor_queries"],
            "same_process_repeat_latencies_ms": repeated_latencies,
        }
        if candidate_compute_diagnostics:
            result.update({
                "candidate_compute_duration_ms": first["candidate_compute_duration_ms"],
                "candidate_output_preparation_duration_ms": first["candidate_output_preparation_duration_ms"],
                "candidate_output_to_prompt_ms": first["candidate_output_to_prompt_ms"],
                "same_process_repeat_candidate_compute_durations_ms": repeated_candidate_compute_durations,
                "same_process_repeat_candidate_output_preparation_durations_ms": repeated_candidate_output_preparation_durations,
                "same_process_repeat_candidate_output_to_prompt_durations_ms": repeated_candidate_output_to_prompt_durations,
            })
        return result
    finally:
        if session is not None:
            session.close()
        if candidate_compute_diagnostics:
            candidate_compute_sidecar.unlink(missing_ok=True)


def run_interactive_completion_tab_sample(
    binary: Path,
    fixture: Path,
    prefix: str,
    home_root: Path,
    expected_candidates: list[bytes],
    settle_seconds: float,
) -> dict[str, object]:
    if len(expected_candidates) != FIXTURE_FILE_COUNT:
        raise RuntimeError("NFR-06 Tab sample reference output has an invalid row count")
    expected_first = expected_candidates[0]
    expected_last = expected_candidates[-1]
    expected_initial_page = expected_candidates[:NFR06_VISIBLE_CANDIDATE_COUNT]
    marker_text = f"NSHELL_NFR06_{uuid.uuid4().hex}_PROMPT"
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    session = PtySession(
        [str(binary), "--no-config"],
        fixture,
        child_environment(home, marker_text),
        terminal_size=NFR06_TERMINAL_SIZE,
    )
    command_bytes = f"cat {shlex.quote(prefix)}".encode()
    try:
        session.wait_for_marker(marker)
        session.pump_for(settle_seconds)
        paste = BRACKETED_PASTE_START + command_bytes + BRACKETED_PASTE_END
        input_start = len(session.data)
        if os.write(session.master, paste) != len(paste):
            raise RuntimeError("NFR-06 Tab command was not fully written to the PTY")
        session.wait_for_output(
            lambda data: command_bytes in strip_terminal_sequences(data[input_start:])
        )
        session.pump_for(0.05)

        response_start = len(session.data)
        started_ns = time.monotonic_ns()
        if os.write(session.master, b"\t") != 1:
            raise RuntimeError("NFR-06 Tab trigger was not fully written to the PTY")

        def initial_page_visible(data: bytes) -> bool:
            visible = visible_terminal_text(data[response_start:])
            return (
                COMPLETION_PAGER_FOOTER in visible
                and b"1/20000" in visible
                and re.findall(rb"item-\d{5}", visible) == expected_initial_page
            )

        end_ns = session.wait_for_output(initial_page_visible)
        response = bytes(session.data[response_start:])
        visible_response = visible_terminal_text(response)
        visible_candidates = re.findall(rb"item-\d{5}", visible_response)
        if visible_candidates != expected_initial_page:
            raise RuntimeError("NFR-06 Tab sample did not render the expected initial candidate page")

        followup_start = len(session.data)
        if os.write(session.master, b"x") != 1:
            raise RuntimeError("NFR-06 follow-up filter key was not fully written to the PTY")
        session.wait_for_output(
            lambda data: (
                b"Filter: x" in visible_terminal_text(data[followup_start:])
                and b"No matches" in visible_terminal_text(data[followup_start:])
            )
        )
        return {
            "latency_ms": (end_ns - started_ns) / 1_000_000,
            "trigger": "Tab on an already-visible file-completion command",
            "candidate_count": FIXTURE_FILE_COUNT,
            "terminal_rows": NFR06_TERMINAL_SIZE[0],
            "terminal_columns": NFR06_TERMINAL_SIZE[1],
            "visible_candidate_count": len(visible_candidates),
            "first_candidate_visible": expected_first.decode("utf-8"),
            "last_candidate_hidden": expected_last not in visible_candidates,
            "pager_total_visible": b"1/20000" in visible_response,
            "followup_filter_key_accepted": True,
            "response_bytes": len(response),
            "cursor_queries": session.responses_sent,
        }
    finally:
        session.close()


def run_suggestion_key_sample(
    binary: Path,
    cwd: Path,
    home_root: Path,
    settle_seconds: float,
) -> dict[str, object]:
    marker_text = f"NSHELL_NFR06_{uuid.uuid4().hex}_PROMPT"
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    session = PtySession([str(binary)], cwd, child_environment(home, marker_text))
    typed = ""
    keypresses: list[dict[str, object]] = []
    try:
        session.wait_for_marker(marker)
        session.pump_for(settle_seconds)
        for index, character in enumerate(SUGGESTION_KEY_SEQUENCE, start=1):
            response_start = len(session.data)
            started_ns = time.monotonic_ns()
            os.write(session.master, character.encode("ascii"))
            typed += character
            typed_bytes = typed.encode("ascii")
            visible_ns = session.wait_for_output(
                lambda data: typed_bytes in strip_terminal_sequences(data[response_start:])
            )
            keypresses.append({
                "key_index": index,
                "key": character,
                "typed_prefix": typed,
                "keypress_started_ns": started_ns,
                "visible_buffer_ns": visible_ns,
                "raw_keypress_to_visible_buffer_ms": (visible_ns - started_ns) / 1_000_000,
                "response_bytes": len(session.data) - response_start,
            })
    finally:
        session.close()

    latencies = [float(event["raw_keypress_to_visible_buffer_ms"]) for event in keypresses]
    return {
        "fixture": str(cwd),
        "typed_sequence": SUGGESTION_KEY_SEQUENCE,
        "keypresses": keypresses,
        "sequence_stats": stats(latencies),
    }


def run_pair(
    target: Callable[[], dict[str, object]],
    control: Callable[[], dict[str, object]],
    order_rng: random.Random,
) -> tuple[dict[str, object], list[str]]:
    order = ["target", "control"]
    order_rng.shuffle(order)
    values: dict[str, dict[str, object]] = {}
    for arm in order:
        values[arm] = target() if arm == "target" else control()
    return values, order


def stats(values: list[float]) -> dict[str, float]:
    return {
        "median_ms": statistics.median(values),
        "p99_ms": percentile_nearest_rank(values, 0.99),
        "max_ms": max(values),
    }


def run_target_group(
    stream,
    metric: str,
    context: dict[str, object],
    samples: int,
    warmups: int,
    threshold_ms: float,
    acceptance_statistic: str,
    target_runner: Callable[[], dict[str, object]],
) -> dict[str, object]:
    load_before = uptime_record()
    stream.write(json.dumps({
        "record": "group-start",
        "metric": metric,
        **context,
        "uptime": load_before,
    }, sort_keys=True) + "\n")
    stream.flush()

    rows: list[dict[str, object]] = []
    for index in range(warmups + samples):
        target = target_runner()
        row = {
            "record": "sample",
            "metric": metric,
            **context,
            "sample": index + 1,
            "warmup": index < warmups,
            "target": target,
        }
        stream.write(json.dumps(row, sort_keys=True) + "\n")
        stream.flush()
        if index >= warmups:
            rows.append(row)

    load_after = uptime_record()
    target_values = [float(row["target"]["latency_ms"]) for row in rows]
    target_stats = stats(target_values)
    acceptance_value = (
        target_stats["median_ms"] if acceptance_statistic == "median" else target_stats["p99_ms"]
    )
    summary = {
        "record": "group-summary",
        "metric": metric,
        **context,
        "measured_samples": samples,
        "warmups": warmups,
        "acceptance_statistic": acceptance_statistic,
        "threshold_ms": threshold_ms,
        "target_threshold_met": acceptance_value <= threshold_ms,
        "target": target_stats,
        "uptime_before": load_before,
        "uptime_after": load_after,
    }
    if metric == "NFR-06":
        repeat_rows = [
            row for row in rows if "same_process_repeat_latencies_ms" in row["target"]
        ]
        if repeat_rows:
            repeat_values = [
                float(latency)
                for row in repeat_rows
                for latency in row["target"]["same_process_repeat_latencies_ms"]
            ]
            expected_repeat_count = samples * NFR06_SAME_PROCESS_REPEAT_COUNT
            if len(repeat_rows) != samples or len(repeat_values) != expected_repeat_count:
                raise ValueError(
                    "NFR-06 did not produce the configured same-process repeat count: "
                    f"expected {expected_repeat_count}, got {len(repeat_values)}"
                )
            summary["same_process_repeat"] = {
                "first_completion_per_process": True,
                "repeats_per_process": NFR06_SAME_PROCESS_REPEAT_COUNT,
                "measured_samples": len(repeat_values),
                **stats(repeat_values),
            }
        if rows and "candidate_compute_duration_ms" in rows[0]["target"]:
            first_compute_values = [
                float(row["target"]["candidate_compute_duration_ms"]) for row in rows
            ]
            first_output_preparation_values = [
                float(row["target"]["candidate_output_preparation_duration_ms"]) for row in rows
            ]
            first_output_to_prompt_values = [
                float(row["target"]["candidate_output_to_prompt_ms"]) for row in rows
            ]
            repeat_compute_values = [
                float(value)
                for row in rows
                for value in row["target"]["same_process_repeat_candidate_compute_durations_ms"]
            ]
            repeat_output_preparation_values = [
                float(value)
                for row in rows
                for value in row["target"]["same_process_repeat_candidate_output_preparation_durations_ms"]
            ]
            repeat_output_to_prompt_values = [
                float(value)
                for row in rows
                for value in row["target"]["same_process_repeat_candidate_output_to_prompt_durations_ms"]
            ]
            if (
                len(first_compute_values) != samples
                or len(first_output_preparation_values) != samples
                or len(first_output_to_prompt_values) != samples
                or len(repeat_compute_values) != expected_repeat_count
                or len(repeat_output_preparation_values) != expected_repeat_count
                or len(repeat_output_to_prompt_values) != expected_repeat_count
            ):
                raise ValueError("NFR-06 candidate-compute phase data is incomplete")
            summary["candidate_compute_phase_timing"] = {
                "first_completion": {
                    "measured_samples": len(first_compute_values),
                    "candidate_compute": stats(first_compute_values),
                    "candidate_output_preparation": stats(first_output_preparation_values),
                    "candidate_output_to_prompt": stats(first_output_to_prompt_values),
                },
                "same_process_repeats": {
                    "measured_samples": len(repeat_compute_values),
                    "candidate_compute": stats(repeat_compute_values),
                    "candidate_output_preparation": stats(repeat_output_preparation_values),
                    "candidate_output_to_prompt": stats(repeat_output_to_prompt_values),
                },
            }
    stream.write(json.dumps(summary, sort_keys=True) + "\n")
    stream.flush()
    return summary


def run_group(
    stream,
    metric: str,
    context: dict[str, object],
    samples: int,
    warmups: int,
    threshold_ms: float,
    acceptance_statistic: str,
    target_runner: Callable[[], dict[str, object]],
    control_runner: Callable[[], dict[str, object]],
    order_rng: random.Random,
) -> dict[str, object]:
    load_before = uptime_record()
    stream.write(json.dumps({
        "record": "group-start",
        "metric": metric,
        **context,
        "uptime": load_before,
    }, sort_keys=True) + "\n")
    stream.flush()

    rows: list[dict[str, object]] = []
    for index in range(warmups + samples):
        pair, order = run_pair(target_runner, control_runner, order_rng)
        target_ms = float(pair["target"]["latency_ms"])
        control_ms = float(pair["control"]["latency_ms"])
        row = {
            "record": "sample",
            "metric": metric,
            **context,
            "sample": index + 1,
            "warmup": index < warmups,
            "execution_order": order,
            "target": pair["target"],
            "control": pair["control"],
            "paired_delta_ms": target_ms - control_ms,
            "paired_abs_delta_ms": abs(target_ms - control_ms),
        }
        stream.write(json.dumps(row, sort_keys=True) + "\n")
        stream.flush()
        if index >= warmups:
            rows.append(row)

    load_after = uptime_record()
    target_values = [float(row["target"]["latency_ms"]) for row in rows]
    control_values = [float(row["control"]["latency_ms"]) for row in rows]
    deltas = [float(row["paired_delta_ms"]) for row in rows]
    abs_deltas = [float(row["paired_abs_delta_ms"]) for row in rows]
    target_stats = stats(target_values)
    control_stats = stats(control_values)
    acceptance_value = target_stats["median_ms"] if acceptance_statistic == "median" else target_stats["p99_ms"]
    summary = {
        "record": "group-summary",
        "metric": metric,
        **context,
        "measured_samples": samples,
        "warmups": warmups,
        "acceptance_statistic": acceptance_statistic,
        "threshold_ms": threshold_ms,
        "target_threshold_met": acceptance_value <= threshold_ms,
        "target": target_stats,
        "control": control_stats,
        "paired_delta_median_ms": statistics.median(deltas),
        "paired_abs_delta_median_ms": statistics.median(abs_deltas),
        "paired_abs_delta_p99_ms": percentile_nearest_rank(abs_deltas, 0.99),
        "uptime_before": load_before,
        "uptime_after": load_after,
    }
    stream.write(json.dumps(summary, sort_keys=True) + "\n")
    stream.flush()
    return summary


def run_suggestion_key_group(
    stream,
    context: dict[str, object],
    samples: int,
    warmups: int,
    target_runner: Callable[[], dict[str, object]],
    control_runner: Callable[[], dict[str, object]],
    order_rng: random.Random,
) -> dict[str, object]:
    if samples < 100:
        raise ValueError("NFR-06 suggestion key response requires at least 100 measured sequences")

    metric = "NFR-06-suggestion-key-responsiveness"
    load_before = uptime_record()
    stream.write(json.dumps({
        "record": "group-start",
        "metric": metric,
        **context,
        "uptime": load_before,
    }, sort_keys=True) + "\n")
    stream.flush()

    rows: list[dict[str, object]] = []
    for index in range(warmups + samples):
        pair, order = run_pair(target_runner, control_runner, order_rng)
        target_p99 = float(pair["target"]["sequence_stats"]["p99_ms"])
        plain_fixture_p99 = float(pair["control"]["sequence_stats"]["p99_ms"])
        row = {
            "record": "sample",
            "metric": metric,
            **context,
            "sample": index + 1,
            "warmup": index < warmups,
            "execution_order": order,
            "target": pair["target"],
            "plain_fixture": pair["control"],
            "paired_sequence_p99_delta_ms": target_p99 - plain_fixture_p99,
        }
        stream.write(json.dumps(row, sort_keys=True) + "\n")
        stream.flush()
        if index >= warmups:
            rows.append(row)

    load_after = uptime_record()
    target_latencies = [
        float(event["raw_keypress_to_visible_buffer_ms"])
        for row in rows
        for event in row["target"]["keypresses"]
    ]
    plain_fixture_latencies = [
        float(event["raw_keypress_to_visible_buffer_ms"])
        for row in rows
        for event in row["plain_fixture"]["keypresses"]
    ]
    sequence_p99_deltas = [float(row["paired_sequence_p99_delta_ms"]) for row in rows]
    target_stats = stats(target_latencies)
    plain_fixture_stats = stats(plain_fixture_latencies)
    summary = {
        "record": "group-summary",
        "metric": metric,
        **context,
        "measured_sequences": samples,
        "keypress_samples_per_fixture": len(target_latencies),
        "warmups": warmups,
            "criterion": "diagnostic p99 per-key latency to visible buffer in the 20,000-entry and plain fixtures",
        "target": target_stats,
        "plain_fixture": plain_fixture_stats,
        "plain_fixture_delta_p99_ms": target_stats["p99_ms"] - plain_fixture_stats["p99_ms"],
        "paired_sequence_p99_delta_median_ms": statistics.median(sequence_p99_deltas),
        "paired_sequence_p99_delta_p99_ms": percentile_nearest_rank(sequence_p99_deltas, 0.99),
        "specified_nfr06_keypress_p99_threshold_ms": None,
        "inferred_nfr05_p99_threshold_ms": NFR_THRESHOLDS["05"]["limit"],
        "inferred_nfr05_threshold_met_by_target": target_stats["p99_ms"] <= NFR_THRESHOLDS["05"]["limit"],
        "inference_note": "p99 <= 16 ms is an inference borrowed from NFR-05, not a specified NFR-06 threshold",
        "uptime_before": load_before,
        "uptime_after": load_after,
    }
    stream.write(json.dumps(summary, sort_keys=True) + "\n")
    stream.flush()
    return summary


def run_completion_group(
    stream,
    binary: Path,
    completion_fixture: Path,
    prefix: str,
    home_root: Path,
    samples: int,
    warmups: int,
    settle_seconds: float,
) -> dict[str, object]:
    expected_output = completion_reference_output(binary, completion_fixture, prefix, home_root)
    expected_candidates = sorted(
        path.name.encode("utf-8")
        for path in completion_fixture.iterdir()
        if path.is_file() and path.name.startswith(prefix)
    )
    if len(expected_candidates) != FIXTURE_FILE_COUNT:
        raise RuntimeError(
            f"NFR-06 Tab fixture returned {len(expected_candidates)} matching files, "
            f"expected {FIXTURE_FILE_COUNT}"
        )
    target = lambda: run_interactive_completion_tab_sample(
        binary,
        completion_fixture,
        prefix,
        home_root,
        expected_candidates,
        settle_seconds,
    )
    return run_target_group(
        stream,
        "NFR-06",
        {
            "completion_entries": FIXTURE_FILE_COUNT,
            "completion_prefix": prefix,
            "completion_command": f"cat {prefix}",
            "measurement_boundary": "PTY Tab write to the initial candidate page and its 20,000-entry pager footer",
            "terminal_size": {"rows": NFR06_TERMINAL_SIZE[0], "columns": NFR06_TERMINAL_SIZE[1]},
            "reference_output_bytes": len(expected_output),
        },
        samples,
        warmups,
        NFR_THRESHOLDS["06"]["limit"],
        "median",
        target,
    )


def run_complete_c_output_diagnostic_group(
    stream,
    binary: Path,
    completion_fixture: Path,
    prefix: str,
    home_root: Path,
    samples: int,
    warmups: int,
    settle_seconds: float,
    candidate_compute_diagnostics: bool = False,
) -> dict[str, object]:
    expected_output = completion_reference_output(binary, completion_fixture, prefix, home_root)
    target_runner = lambda: run_interactive_completion_sample(
        binary,
        completion_fixture,
        prefix,
        home_root,
        expected_output,
        settle_seconds,
        candidate_compute_diagnostics,
    )
    context = {
        "completion_entries": FIXTURE_FILE_COUNT,
        "completion_prefix": prefix,
        "completion_command": completion_command(binary, completion_fixture, prefix)[-1],
        "measurement_boundary": "PTY Enter write to all expected candidates and the next fully rendered prompt",
        "reference_output_bytes": len(expected_output),
        "diagnostic_only": True,
        "threshold_ms": None,
    }
    load_before = uptime_record()
    stream.write(json.dumps({
        "record": "group-start",
        "metric": "complete-C output diagnostic",
        **context,
        "uptime": load_before,
    }, sort_keys=True) + "\n")
    stream.flush()

    rows: list[dict[str, object]] = []
    for index in range(warmups + samples):
        target = target_runner()
        row = {
            "record": "sample",
            "metric": "complete-C output diagnostic",
            **context,
            "sample": index + 1,
            "warmup": index < warmups,
            "target": target,
        }
        stream.write(json.dumps(row, sort_keys=True) + "\n")
        stream.flush()
        if index >= warmups:
            rows.append(row)

    repeat_values = [
        float(value)
        for row in rows
        for value in row["target"].get("same_process_repeat_latencies_ms", [])
    ]
    expected_repeat_count = samples * NFR06_SAME_PROCESS_REPEAT_COUNT
    if len(repeat_values) != expected_repeat_count:
        raise ValueError(
            "complete-C diagnostic did not produce the configured same-process repeat count: "
            f"expected {expected_repeat_count}, got {len(repeat_values)}"
        )
    first_values = [float(row["target"]["latency_ms"]) for row in rows]
    summary: dict[str, object] = {
        "record": "group-summary",
        "metric": "complete-C output diagnostic",
        **context,
        "measured_samples": samples,
        "warmups": warmups,
        "first_completion_per_process": stats(first_values),
        "same_process_repeat": {
            "repeats_per_process": NFR06_SAME_PROCESS_REPEAT_COUNT,
            "measured_samples": len(repeat_values),
            **stats(repeat_values),
        },
        "uptime_before": load_before,
        "uptime_after": uptime_record(),
    }
    if candidate_compute_diagnostics:
        first = [row["target"] for row in rows]
        phase_names = (
            "candidate_compute_duration_ms",
            "candidate_output_preparation_duration_ms",
            "candidate_output_to_prompt_ms",
        )
        first_phase_values = {
            name: [float(row[name]) for row in first]
            for name in phase_names
        }
        repeat_phase_values = {
            name: [
                float(value)
                for row in rows
                for value in row["target"].get(repeat_key, [])
            ]
            for name, repeat_key in (
                (phase_names[0], "same_process_repeat_candidate_compute_durations_ms"),
                (phase_names[1], "same_process_repeat_candidate_output_preparation_durations_ms"),
                (phase_names[2], "same_process_repeat_candidate_output_to_prompt_durations_ms"),
            )
        }
        if any(len(values) != samples for values in first_phase_values.values()) or any(
            len(values) != expected_repeat_count for values in repeat_phase_values.values()
        ):
            raise ValueError("complete-C diagnostic phase timing data is incomplete")

        def phase_stats(values: dict[str, list[float]], count: int) -> dict[str, object]:
            return {
                "measured_samples": count,
                "candidate_compute": stats(values[phase_names[0]]),
                "candidate_output_preparation": stats(values[phase_names[1]]),
                "candidate_output_to_prompt": stats(values[phase_names[2]]),
            }

        summary["candidate_compute_phase_timing"] = {
            "first_completion": phase_stats(first_phase_values, samples),
            "same_process_repeats": phase_stats(repeat_phase_values, expected_repeat_count),
        }
    stream.write(json.dumps(summary, sort_keys=True) + "\n")
    stream.flush()
    return summary


def run_measurements(args: argparse.Namespace, output_path: Path) -> list[dict[str, object]]:
    binary = validate_executable(args.binary, "--binary")
    control_shell = (
        validate_executable(args.control_binary, "--control-binary")
        if args.start_from == "nfr04"
        else None
    )
    fixtures = validate_fixtures(args)
    plain_fixture = Path(str(fixtures["plain_fixture"]))
    git_fixture = Path(str(fixtures["git_fixture"])) if fixtures["git_fixture"] is not None else None
    completion_fixture = Path(str(fixtures["completion_fixture"]))
    buffer_sizes = tuple(args.buffer_sizes)
    if args.start_from in ("nfr04", "nfr05") and (
        not buffer_sizes or any(size < 1 or size > 1000 for size in buffer_sizes)
    ):
        raise ValueError("--buffer-sizes values must be between 1 and 1000")
    if args.start_from in ("nfr04", "nfr05") and len(set(buffer_sizes)) != len(buffer_sizes):
        raise ValueError("--buffer-sizes values must be unique")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    summaries: list[dict[str, object]] = []
    order_rng = random.Random(args.seed)
    with tempfile.TemporaryDirectory(prefix="nshell-nfr-04-06-") as temp:
        home_root = Path(temp)
        metadata = {
            "record": "metadata",
            "platform": platform.platform(),
            "machine": platform.machine(),
            "binary": str(binary),
            "output": str(output_path),
            "start_from": args.start_from,
            "control_binary": str(control_shell) if control_shell is not None else None,
            "samples": args.samples,
            "warmups": args.warmups,
            "seed": args.seed,
            "fixture_validation": fixtures,
            "nfr04_control": (
                f"interactive {control_shell} blank-Enter-to-prompt in the same fixture directory"
                if control_shell is not None
                else None
            ),
            "nfr05_action": "write one character to a buffer preloaded to one character below the selected length",
            "nfr05_measurement_boundary": "keypress PTY write to the fresh prompt, cursor restore, and full buffer in PTY output",
            "nfr06_action": "press Tab on a file-completion prefix in a live nshell PTY",
            "nfr06_measurement_boundary": "Tab PTY write to the initial candidate page and its 20,000-entry pager footer",
            "nfr06_suggestion_key_metric": "raw per-key latency from writing one character to observing the full typed prefix in subsequent PTY output",
            "nfr06_suggestion_key_plain_fixture": "same binary and typed sequence in the plain fixture directory",
            "nfr06_suggestion_key_sequence": SUGGESTION_KEY_SEQUENCE,
            "terminal_size": {"rows": 24, "columns": 100},
            "nfr06_completion_terminal_size": {
                "rows": NFR06_TERMINAL_SIZE[0],
                "columns": NFR06_TERMINAL_SIZE[1],
            },
            "percentile": "nearest-rank p99",
        }
        if args.nfr06_candidate_compute_diagnostics:
            metadata["nfr06_candidate_compute_diagnostics"] = {
                "candidate_compute_boundary": "get-internal-real-time immediately before the domain completion:complete call through its return; excludes candidate-text assembly and PTY rendering",
                "candidate_output_preparation_boundary": "get-internal-real-time around formatting all candidate texts into the command output string; excludes completion:complete and PTY rendering",
                "candidate_output_to_prompt_boundary": "Python time.monotonic_ns from observing the first expected candidate row in PTY output through the fully restored prompt cursor; excludes Enter dispatch and candidate computation, and includes candidate output through the PTY and prompt restoration",
                "observer_delivery": "The diagnostic-only sidecar writes three integer timing values to a per-sample file after candidate text preparation and before returning command output. The regular NFR-06 gate runs without this instrumentation.",
            }

        with output_path.open("w", encoding="utf-8") as stream:
            stream.write(json.dumps(metadata, sort_keys=True) + "\n")
            stream.flush()

            if args.start_from in ("nfr04", "nfr05"):
                redraw_preflight = {
                    "record": "preflight",
                    "metric": "NFR-05",
                    "trigger": "one-character insertion into a preloaded buffer",
                    "target": verify_redraw_support(
                        binary,
                        plain_fixture,
                        home_root,
                        f"NSHELL_NFR05_PREFLIGHT_{uuid.uuid4().hex}",
                    ),
                }
                stream.write(json.dumps(redraw_preflight, sort_keys=True) + "\n")
                stream.flush()

            for git_enabled, cwd, label in (
                ((False, plain_fixture, "git-disabled"), (True, git_fixture, "git-enabled"))
                if args.start_from == "nfr04"
                else ()
            ):
                prompt = f"NSHELL_NFR04_{uuid.uuid4().hex}_PROMPT"
                target = lambda cwd=cwd, prompt=prompt, git_enabled=git_enabled: run_prompt_sample(
                    binary,
                    cwd,
                    home_root,
                    prompt,
                    git_prompt=git_enabled,
                    control_shell=False,
                    settle_seconds=args.settle_ms / 1000,
                )
                control = lambda cwd=cwd, prompt=prompt: run_prompt_sample(
                    control_shell,
                    cwd,
                    home_root,
                    prompt,
                    git_prompt=False,
                    control_shell=True,
                    settle_seconds=args.settle_ms / 1000,
                )
                summaries.append(run_group(
                    stream,
                    "NFR-04",
                    {"context": label, "git_prompt_enabled": git_enabled},
                    args.samples,
                    args.warmups,
                    NFR_THRESHOLDS["04"]["limit"],
                    "median",
                    target,
                    control,
                    order_rng,
                ))

            for buffer_length in (buffer_sizes if args.start_from in ("nfr04", "nfr05") else ()):
                prompt = f"NSHELL_NFR05_{uuid.uuid4().hex}_PROMPT"
                target = lambda buffer_length=buffer_length, prompt=prompt: run_redraw_sample(
                    binary,
                    plain_fixture,
                    home_root,
                    prompt,
                    buffer_length,
                    settle_seconds=args.settle_ms / 1000,
                )
                summaries.append(run_target_group(
                    stream,
                    "NFR-05",
                    {
                        "buffer_length": buffer_length,
                        "trigger": "one-character insertion after preloading buffer_length minus one characters",
                        "measurement_boundary": "keypress PTY write to fresh prompt, cursor restore, and full buffer in PTY output",
                    },
                    args.samples,
                    args.warmups,
                    NFR_THRESHOLDS["05"]["limit"],
                    "p99",
                    target,
                ))

            prefix = str(fixtures["completion_prefix"])
            if args.start_from in ("nfr04", "nfr06"):
                summaries.append(run_completion_group(
                    stream,
                    binary,
                    completion_fixture,
                    prefix,
                    home_root,
                    args.samples,
                    args.warmups,
                    args.settle_ms / 1000,
                ))
                summaries.append(run_complete_c_output_diagnostic_group(
                    stream,
                    binary,
                    completion_fixture,
                    prefix,
                    home_root,
                    args.samples,
                    args.warmups,
                    args.settle_ms / 1000,
                    args.nfr06_candidate_compute_diagnostics,
                ))

            if args.start_from != "nfr05":
                target = lambda: run_suggestion_key_sample(
                    binary, completion_fixture, home_root, args.settle_ms / 1000
                )
                control = lambda: run_suggestion_key_sample(
                    binary, plain_fixture, home_root, args.settle_ms / 1000
                )
                summaries.append(run_suggestion_key_group(
                    stream,
                    {
                        "completion_fixture": str(completion_fixture),
                        "completion_entries": FIXTURE_FILE_COUNT,
                        "plain_control_fixture": str(plain_fixture),
                        "binary": str(binary),
                        "typed_sequence": SUGGESTION_KEY_SEQUENCE,
                        "keypress_event": "write one ASCII character, then wait for the complete typed prefix in newly emitted PTY output",
                    },
                    args.samples,
                    args.warmups,
                    target,
                    control,
                    order_rng,
                ))
    return summaries


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Measure NFR-04 blank-Enter-to-prompt latency, NFR-05 keypress-to-full-buffer-redraw p99, and "
            "NFR-06 interactive completion latency and suggestion key responsiveness. "
            "Absolute NFR-05 and NFR-06 target timings are not adjusted by controls."
        )
    )
    parser.add_argument("--binary", required=True, help="nshell executable to measure")
    parser.add_argument(
        "--control-binary",
        default="/bin/sh",
        help="interactive same-host shell for the NFR-04 blank-Enter control (default: /bin/sh)",
    )
    parser.add_argument(
        "--from",
        dest="start_from",
        choices=("nfr04", "nfr05", "nfr06", "nfr06-keys"),
        default="nfr04",
        help="first group to measure; nfr05 measures only redraw, nfr06 skips NFR-04/05, nfr06-keys also skips completion preflight/timing (default: nfr04, all groups)",
    )
    parser.add_argument(
        "--samples",
        required=True,
        type=int,
        help="at least 100 measured samples or key sequences per selected case, excluding warmups",
    )
    parser.add_argument("--warmups", type=int, default=2, help="paired warmup runs per case (default: 2)")
    parser.add_argument("--plain-fixture", required=True, help="existing directory outside the repository and outside Git")
    parser.add_argument("--git-fixture", help="existing directory inside a Git working tree (required when --from is nfr04)")
    parser.add_argument("--completion-fixture", required=True, help="existing directory with exactly 20,000 item files for NFR-06 completion and key responsiveness")
    parser.add_argument("--completion-prefix", default="item-", help="required filename prefix in completion fixture (default: item-)")
    parser.add_argument(
        "--nfr06-candidate-compute-diagnostics",
        action="store_true",
        help="opt in to per-trial candidate-computation timing and post-completion phase diagnostics",
    )
    parser.add_argument(
        "--buffer-sizes",
        type=int,
        nargs="+",
        default=DEFAULT_BUFFER_SIZES,
        metavar="CHARS",
        help="NFR-05 input buffer lengths from 1 to 1000 (default: 1000)",
    )
    parser.add_argument("--settle-ms", type=float, default=100.0, help="wait after each prompt before input (default: 100)")
    parser.add_argument("--seed", type=int, default=4206, help="seed used to randomize paired arm order")
    parser.add_argument("--output", required=True, help="JSONL output path for metadata, raw samples, and summaries")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.samples < 100:
        parser.error("--samples must be at least 100 for the selected groups' p99 requirements")
    if args.warmups < 0:
        parser.error("--warmups must be zero or greater")
    if args.settle_ms < 0:
        parser.error("--settle-ms must be zero or greater")
    if not args.completion_prefix:
        parser.error("--completion-prefix must not be empty")
    if args.nfr06_candidate_compute_diagnostics and args.start_from not in ("nfr04", "nfr06"):
        parser.error("--nfr06-candidate-compute-diagnostics requires an NFR-06 completion run")
    try:
        output_path = Path(args.output).expanduser().resolve()
        summaries = run_measurements(args, output_path)
    except (OSError, RuntimeError, TimeoutError, ValueError, subprocess.SubprocessError) as error:
        print(f"measurement setup or run failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"output": str(output_path), "summaries": summaries}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
