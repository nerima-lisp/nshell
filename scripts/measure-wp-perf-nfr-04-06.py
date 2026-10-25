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


DEFAULT_BUFFER_SIZES = (1000,)
PROMPT_TIMEOUT_SECONDS = 15
OUTPUT_TIMEOUT_SECONDS = 5
CPR_QUERY = b"\x1b[6n"
CPR_RESPONSE = b"\x1b[1;1R"
BRACKETED_PASTE_START = b"\x1b[200~"
BRACKETED_PASTE_END = b"\x1b[201~"
ANSI_SEQUENCE_RE = re.compile(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[@-_])")
FIXTURE_FILE_COUNT = 20_000
SUGGESTION_KEY_SEQUENCE = "source item-"
CHILD_REAP_TIMEOUT_SECONDS = 0.5


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


def rendered_x_count(data: bytes, start: int, marker: bytes, control_shell: bool) -> int:
    output = data[start:]
    if not control_shell:
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


def child_environment(home: Path, prompt: str | None = None, git_prompt: bool = False) -> dict[str, str]:
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
    return env


class PtySession:
    def __init__(self, argv: list[str], cwd: Path, env: dict[str, str]):
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
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))

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
        start_ns = time.monotonic_ns()
        os.write(session.master, b"\r")
        end_ns = session.wait_for_marker(marker, occurrence=2)
        return {
            "latency_ms": (end_ns - start_ns) / 1_000_000,
            "cursor_queries": session.responses_sent,
            "prompt_markers_seen": session.data.count(marker),
        }
    finally:
        session.close()


def run_redraw_sample(
    executable: Path,
    cwd: Path,
    home_root: Path,
    marker_text: str,
    buffer_length: int,
    control_shell: bool,
    settle_seconds: float,
) -> dict[str, object]:
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    env = child_environment(home, marker_text) if not control_shell else child_environment(home)
    if control_shell:
        env["PS1"] = marker_text + " "
        argv = [str(executable), "-i"]
    else:
        argv = [str(executable)]
    session = PtySession(argv, cwd, env)
    buffer = b"x" * buffer_length
    try:
        session.wait_for_marker(marker)
        session.pump_for(settle_seconds)
        input_start = len(session.data)
        os.write(session.master, BRACKETED_PASTE_START + buffer + BRACKETED_PASTE_END)
        # Each key redraws the line, so cumulative character counts can reach
        # the target length before the complete input has been rendered.
        session.wait_for_output(
            lambda data: rendered_x_count(data, input_start, marker, control_shell) == buffer_length,
            timeout_seconds=OUTPUT_TIMEOUT_SECONDS,
        )
        session.pump_for(0.05)
        response_start = len(session.data)
        start_ns = time.monotonic_ns()
        os.write(session.master, b"\x0c")  # Ctrl-L clears and redraws the current line.
        end_ns = session.wait_for_output(
            lambda data: (
                marker in data[response_start:]
                and rendered_x_count(data, response_start, marker, control_shell) == buffer_length
            ),
            timeout_seconds=OUTPUT_TIMEOUT_SECONDS,
        )
        response = bytes(session.data[response_start:])
        visible_response = visible_terminal_text(response)
        response_buffer_characters = rendered_x_count(
            session.data, response_start, marker, control_shell
        )
        if (
            marker not in visible_response
            or response_buffer_characters != buffer_length
        ):
            raise RuntimeError("NFR-05 redraw did not reproduce the prompt and full input buffer")
        return {
            "latency_ms": (end_ns - start_ns) / 1_000_000,
            "redrawn_prompt_seen": marker in visible_response,
            "redrawn_buffer_characters": response_buffer_characters,
            "response_bytes": len(response),
            "cursor_queries": session.responses_sent,
        }
    finally:
        session.close()


def verify_redraw_support(
    executable: Path,
    cwd: Path,
    home_root: Path,
    marker_text: str,
    control_shell: bool,
) -> dict[str, object]:
    marker = marker_text.encode()
    home = home_root / f"home-{uuid.uuid4().hex}"
    env = child_environment(home, marker_text) if not control_shell else child_environment(home)
    if control_shell:
        env["PS1"] = marker_text + " "
        argv = [str(executable), "-i"]
    else:
        argv = [str(executable)]
    probe_length = 32
    probe_buffer = b"x" * probe_length
    session = PtySession(argv, cwd, env)
    try:
        session.wait_for_marker(marker)
        session.pump_for(0.05)
        input_start = len(session.data)
        os.write(
            session.master,
            BRACKETED_PASTE_START + probe_buffer + BRACKETED_PASTE_END,
        )
        session.wait_for_output(
            lambda data: rendered_x_count(data, input_start, marker, control_shell) == probe_length
        )
        session.pump_for(0.05)
        response_start = len(session.data)
        os.write(session.master, b"\x0c")
        session.wait_for_output(
            lambda data: (
                marker in data[response_start:]
                and rendered_x_count(data, response_start, marker, control_shell) == probe_length
            )
        )
        response = bytes(session.data[response_start:])
        visible_response = visible_terminal_text(response)
        response_buffer_characters = rendered_x_count(
            session.data, response_start, marker, control_shell
        )
        if marker not in visible_response or response_buffer_characters != probe_length:
            raise RuntimeError("NFR-05 redraw preflight did not reproduce the prompt and full input buffer")
        return {
            "supported": True,
            "probe_buffer_length": probe_length,
            "redrawn_prompt_seen": marker in visible_response,
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


def run_completion_sample(
    binary: Path,
    fixture: Path,
    prefix: str,
    home_root: Path,
    expected_output: bytes,
) -> dict[str, object]:
    home = home_root / f"home-{uuid.uuid4().hex}"
    env = child_environment(home)
    started_ns = time.monotonic_ns()
    result = subprocess.run(
        completion_command(binary, fixture, prefix),
        cwd=fixture,
        env=env,
        check=False,
        capture_output=True,
    )
    elapsed_ms = (time.monotonic_ns() - started_ns) / 1_000_000
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
    if result.stdout != expected_output:
        raise RuntimeError("completion output differed from the verified reference output")
    return {
        "latency_ms": elapsed_ms,
        "candidate_count": len(rows),
        "output_bytes": len(result.stdout),
        "output_sha256": hashlib.sha256(result.stdout).hexdigest(),
    }


def run_suggestion_key_sample(
    binary: Path,
    cwd: Path,
    home_root: Path,
    settle_seconds: float,
) -> dict[str, object]:
    marker_text = f"WP_PERF_NFR06_{uuid.uuid4().hex}_PROMPT"
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
        control_p99 = float(pair["control"]["sequence_stats"]["p99_ms"])
        row = {
            "record": "sample",
            "metric": metric,
            **context,
            "sample": index + 1,
            "warmup": index < warmups,
            "execution_order": order,
            "target": pair["target"],
            "control": pair["control"],
            "paired_sequence_p99_delta_ms": target_p99 - control_p99,
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
    control_latencies = [
        float(event["raw_keypress_to_visible_buffer_ms"])
        for row in rows
        for event in row["control"]["keypresses"]
    ]
    sequence_p99_deltas = [float(row["paired_sequence_p99_delta_ms"]) for row in rows]
    target_stats = stats(target_latencies)
    control_stats = stats(control_latencies)
    summary = {
        "record": "group-summary",
        "metric": metric,
        **context,
        "measured_sequences": samples,
        "keypress_samples_per_fixture": len(target_latencies),
        "warmups": warmups,
        "criterion": "raw p99 keypress-to-visible-buffer latency and target-minus-plain-control p99 delta",
        "target": target_stats,
        "control": control_stats,
        "control_delta_p99_ms": target_stats["p99_ms"] - control_stats["p99_ms"],
        "paired_sequence_p99_delta_median_ms": statistics.median(sequence_p99_deltas),
        "paired_sequence_p99_delta_p99_ms": percentile_nearest_rank(sequence_p99_deltas, 0.99),
        "specified_nfr06_keypress_p99_threshold_ms": None,
        "inferred_nfr05_p99_threshold_ms": 16.0,
        "inferred_nfr05_threshold_met_by_target": target_stats["p99_ms"] <= 16.0,
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
    order_rng: random.Random,
) -> dict[str, object]:
    command = completion_command(binary, completion_fixture, prefix)
    preflight = subprocess.run(
        command,
        cwd=completion_fixture,
        env=child_environment(home_root / f"home-{uuid.uuid4().hex}"),
        check=False,
        capture_output=True,
    )
    if preflight.returncode != 0 or preflight.stderr:
        raise RuntimeError(
            "completion preflight failed: "
            f"status={preflight.returncode}, stderr={preflight.stderr[-500:]!r}"
        )
    reference_rows = preflight.stdout.splitlines()
    if len(reference_rows) != FIXTURE_FILE_COUNT or len(set(reference_rows)) != FIXTURE_FILE_COUNT:
        raise RuntimeError(
            f"completion preflight returned {len(reference_rows)} rows and "
            f"{len(set(reference_rows))} unique rows; expected {FIXTURE_FILE_COUNT}"
        )
    expected_output = preflight.stdout
    target = lambda: run_completion_sample(
        binary, completion_fixture, prefix, home_root, expected_output
    )
    control = lambda: run_completion_sample(
        binary, completion_fixture, prefix, home_root, expected_output
    )
    return run_group(
        stream,
        "NFR-06",
        {
            "completion_entries": FIXTURE_FILE_COUNT,
            "completion_prefix": prefix,
            "command": command,
        },
        samples,
        warmups,
        100.0,
        "median",
        target,
        control,
        order_rng,
    )


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
    with tempfile.TemporaryDirectory(prefix="wp-perf-nfr-04-06-") as temp:
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
            "nfr05_action": "Ctrl-L-to-full-line-redraw after preloading the selected buffer length",
            "nfr05_control": (
                "randomized A/A arm using the same binary and 1000-character buffer"
                if args.start_from in ("nfr04", "nfr05")
                else None
            ),
            "nfr05_control_binary": (
                str(binary) if args.start_from in ("nfr04", "nfr05") else None
            ),
            "nfr06_control": (
                "randomized A/A arm using the same binary, command, and 20,000-entry fixture"
                if args.start_from in ("nfr04", "nfr06")
                else None
            ),
            "nfr06_suggestion_key_metric": "raw per-key latency from writing one character to observing the full typed prefix in subsequent PTY output",
            "nfr06_suggestion_key_control": "same binary and typed sequence in the plain fixture directory",
            "nfr06_suggestion_key_sequence": SUGGESTION_KEY_SEQUENCE,
            "terminal_size": {"rows": 24, "columns": 100},
            "percentile": "nearest-rank p99",
        }

        with output_path.open("w", encoding="utf-8") as stream:
            stream.write(json.dumps(metadata, sort_keys=True) + "\n")
            stream.flush()

            if args.start_from in ("nfr04", "nfr05"):
                redraw_preflight = {
                    "record": "control-preflight",
                    "metric": "NFR-05",
                    "trigger": "Ctrl-L-to-full-line-redraw",
                    "target": verify_redraw_support(
                        binary,
                        plain_fixture,
                        home_root,
                        f"W5PT_{uuid.uuid4().hex}",
                        control_shell=False,
                    ),
                    "control": verify_redraw_support(
                        binary,
                        plain_fixture,
                        home_root,
                        f"W5PC_{uuid.uuid4().hex}",
                        control_shell=False,
                    ),
                }
                stream.write(json.dumps(redraw_preflight, sort_keys=True) + "\n")
                stream.flush()

            for git_enabled, cwd, label in (
                ((False, plain_fixture, "git-disabled"), (True, git_fixture, "git-enabled"))
                if args.start_from == "nfr04"
                else ()
            ):
                prompt = f"WP_PERF_NFR04_{uuid.uuid4().hex}_PROMPT"
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
                    60.0,
                    "median",
                    target,
                    control,
                    order_rng,
                ))

            for buffer_length in (buffer_sizes if args.start_from in ("nfr04", "nfr05") else ()):
                prompt = f"WP_PERF_NFR05_{uuid.uuid4().hex}_PROMPT"
                target = lambda buffer_length=buffer_length, prompt=prompt: run_redraw_sample(
                    binary,
                    plain_fixture,
                    home_root,
                    prompt,
                    buffer_length,
                    control_shell=False,
                    settle_seconds=args.settle_ms / 1000,
                )
                control = lambda buffer_length=buffer_length, prompt=prompt: run_redraw_sample(
                    binary,
                    plain_fixture,
                    home_root,
                    prompt,
                    buffer_length,
                    control_shell=False,
                    settle_seconds=args.settle_ms / 1000,
                )
                summaries.append(run_group(
                    stream,
                    "NFR-05",
                    {"buffer_length": buffer_length, "trigger": "Ctrl-L-to-full-line-redraw"},
                    args.samples,
                    args.warmups,
                    16.0,
                    "p99",
                    target,
                    control,
                    order_rng,
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
                    order_rng,
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
            "Measure NFR-04 blank-Enter latency, NFR-05 Ctrl-L-to-full-line-redraw p99, and "
            "NFR-06 completion latency and suggestion key responsiveness. Each group records uptime before and after "
            "and paired same-host controls."
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
