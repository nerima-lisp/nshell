#!/usr/bin/env python3
"""Collect NFR-05 per-stage diagnostics separately from the official gate."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
from decimal import Decimal
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
MEASURE_PATH = ROOT / "scripts/measure-nfr-04-06.py"
MEASURE_SPEC = importlib.util.spec_from_file_location("measure_nfr_04_06", MEASURE_PATH)
if MEASURE_SPEC is None or MEASURE_SPEC.loader is None:
    raise RuntimeError(f"cannot load measurement helpers from {MEASURE_PATH}")
MEASURE = importlib.util.module_from_spec(MEASURE_SPEC)
sys.modules[MEASURE_SPEC.name] = MEASURE
MEASURE_SPEC.loader.exec_module(MEASURE)

NFR05_STRACE_SYSCALLS = (
    "futex,futex_waitv,rt_sigprocmask,"
    "clone,clone3,fork,vfork,execve,execveat,wait4,waitid"
)
_STRACE_PROBE_CACHE: dict[str, tuple[tuple[str, ...] | None, str | None]] = {}
_SUDO_PROBE_CACHE: dict[str, tuple[bool, str]] = {}
DIAGNOSTIC_FIELDS = (
    "render_wall_ns",
    "gc_count",
    "gc_time_ns",
    "gc_real_time_ns",
    "suggestion_ns",
    "suggestion_scan_ns",
    "suggestion_history_ns",
    "suggestion_completion_ns",
    "grapheme_geometry_ns",
    "display_width_ns",
    "input_buffer_render_ns",
    "terminal_write_ns",
    "terminal_flush_ns",
)
STAGE_FIELDS = (
    "suggestion_ns",
    "suggestion_scan_ns",
    "suggestion_history_ns",
    "suggestion_completion_ns",
    "grapheme_geometry_ns",
    "display_width_ns",
    "input_buffer_render_ns",
    "terminal_write_ns",
    "terminal_flush_ns",
)


def validate_diagnostic_record(record: object) -> dict[str, object]:
    if not isinstance(record, dict):
        raise ValueError("NFR-05 diagnostic record must be a JSON object")
    if record.get("schema_version") != 2 or record.get("record") != "nfr05-render-diagnostic":
        raise ValueError("NFR-05 diagnostic record has an unexpected schema")
    if not isinstance(record.get("output_event"), str):
        raise ValueError("NFR-05 diagnostic output event must be a string")
    for field in DIAGNOSTIC_FIELDS:
        value = record.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ValueError(f"NFR-05 diagnostic {field} must be a nonnegative integer")
    if not isinstance(record.get("completion_ran"), bool):
        raise ValueError("NFR-05 diagnostic completion_ran must be a boolean")
    if not isinstance(record.get("stage_timing_relationships"), dict):
        raise ValueError("NFR-05 diagnostic stage timing relationships must be an object")
    if record.get("lock_wait_ns") is not None and (
        not isinstance(record["lock_wait_ns"], int)
        or isinstance(record["lock_wait_ns"], bool)
        or record["lock_wait_ns"] < 0
    ):
        raise ValueError("NFR-05 diagnostic lock_wait_ns must be null or a nonnegative integer")
    if not isinstance(record.get("lock_wait_source"), str) or not record["lock_wait_source"]:
        raise ValueError("NFR-05 diagnostic lock_wait_source must name its evidence source")
    if record.get("command_execution_requested") is not False:
        raise ValueError("NFR-05 marker-key diagnostic must not submit a command")
    return record


def summarize_diagnostic_samples(rows: list[dict[str, object]]) -> dict[str, object]:
    stage_rows = [
        row for row in rows if row.get("sample_role") in {"stage-control", "stage-native"}
    ]
    if not stage_rows:
        raise ValueError("NFR-05 diagnostic summary requires stage samples")

    def summary_for(field: str, samples: list[dict[str, object]]) -> dict[str, float]:
        values = [
            float(row[field] if field == "latency_ms" else row["diagnostics"][field])  # type: ignore[index]
            for row in samples
        ]
        return {
            "median": statistics.median(values),
            "p99_nearest_rank": MEASURE.percentile_nearest_rank(values, 0.99),
        }

    control_rows = [row for row in stage_rows if row.get("sample_role") == "stage-control"]
    native_rows = [row for row in stage_rows if row.get("sample_role") == "stage-native"]
    control_by_pair = {row["pair_id"]: row for row in control_rows}
    native_by_pair = {row["pair_id"]: row for row in native_rows}
    paired_deltas = [
        float(native_by_pair[pair_id]["latency_ms"]) - float(control_by_pair[pair_id]["latency_ms"])
        for pair_id in control_by_pair.keys() & native_by_pair.keys()
    ]
    lock_wait_values = [
        int(row["diagnostics"]["lock_wait_ns"])
        for row in native_rows
        if isinstance(row.get("diagnostics"), dict)
        and isinstance(row["diagnostics"].get("lock_wait_ns"), int)
        and not isinstance(row["diagnostics"].get("lock_wait_ns"), bool)
    ]

    def mode_summary(samples: list[dict[str, object]]) -> dict[str, object]:
        return {
            "sample_count": len(samples),
            "latency_ms": summary_for("latency_ms", samples),
            "render_wall_ns": summary_for("render_wall_ns", samples),
            "gc_count": summary_for("gc_count", samples),
            "gc_time_ns": summary_for("gc_time_ns", samples),
            "gc_real_time_ns": summary_for("gc_real_time_ns", samples),
            "stages": {field: summary_for(field, samples) for field in STAGE_FIELDS},
        }

    return {
        "sample_count": len(stage_rows),
        "sample_pair_count": len(control_by_pair.keys() & native_by_pair.keys()),
        "stage_control": mode_summary(control_rows) if control_rows else None,
        "stage_native": mode_summary(native_rows) if native_rows else None,
        "observed_native_latency_delta_ms": {
            "median": statistics.median(paired_deltas),
            "p99_nearest_rank": MEASURE.percentile_nearest_rank(paired_deltas, 0.99),
            "paired_sample_count": len(paired_deltas),
            "interpretation": "descriptive native-tracer overhead; diagnostic data only",
        } if paired_deltas else None,
        "native_lock_wait_ns": {
            "sample_count": len(lock_wait_values),
            "native_sample_count": len(native_rows),
            "median": statistics.median(lock_wait_values),
            "p99_nearest_rank": MEASURE.percentile_nearest_rank(lock_wait_values, 0.99),
            "scope": "capture_window; may include syscall waits outside the redraw interval",
        } if lock_wait_values else {
            "sample_count": 0,
            "native_sample_count": len(native_rows),
            "scope": "capture_window",
            "source": "native tracer does not expose syscall wait durations on this platform",
        },
        "lock_wait_note": "each native-traced stage row carries its own platform trace evidence when capture succeeds",
        "latency_interpretation": (
            "stage-control is the untraced diagnostic latency with sidecar instrumentation; "
            "stage-native is profiler-perturbed evidence for syscall attribution only; "
            "neither is used by the official acceptance gate"
        ),
        "stage_timing_relationships": {
            "suggestion_scan_history_completion_are_nested_within_suggestion": True,
            "input_buffer_render_includes_work_performed_inside_render_edit_buffer": True,
            "stage_durations_are_not_additive": True,
        },
        "acceptance_threshold_ms": None,
    }


def _parse_strace_trace(text: str) -> dict[str, object]:
    call_re = re.compile(
        r"^\s*(?:\[pid\s+(?P<bracket_pid>\d+)\]\s+|(?P<plain_pid>\d+)\s+)?"
        r"(?:(?P<timestamp>\d+(?:\.\d+)?)\s+)?"
        r"(?P<name>futex|futex_waitv|rt_sigprocmask|rt_sigreturn|read|readv|poll|ppoll|select|"
        r"pselect6|epoll_wait|epoll_pwait|epoll_pwait2|write|writev|ioctl|wait4|waitid|"
        r"clone|clone3|fork|vfork|execve|execveat)\("
    )
    duration_re = re.compile(r"<(?P<seconds>\d+(?:\.\d+)?)>\s*$")
    lines = text.splitlines()
    calls: list[dict[str, object]] = []
    for index, line in enumerate(lines):
        match = call_re.match(line)
        if match is None:
            continue
        name = match.group("name")
        if name == "futex" and not re.search(r"FUTEX_(?:WAIT|LOCK_PI)", line):
            continue
        duration = duration_re.search(line)
        duration_ns = (
            int(Decimal(duration.group("seconds")) * 1_000_000_000)
            if duration
            else None
        )
        timestamp = match.group("timestamp")
        timestamp_ns = (
            int(Decimal(timestamp) * 1_000_000_000)
            if timestamp is not None
            else None
        )
        stack: list[str] = []
        for frame in lines[index + 1 :]:
            if not frame.lstrip().startswith(">"):
                break
            stack.append(frame.strip())
        calls.append(
            {
                "syscall": name,
                "trace_pid_tid": int(
                    match.group("bracket_pid") or match.group("plain_pid")
                )
                if match.group("bracket_pid") or match.group("plain_pid")
                else None,
                "timestamp_realtime": timestamp,
                "timestamp_realtime_ns": timestamp_ns,
                "duration_ns": duration_ns,
                "stack": stack[:8],
            }
        )

    def call_group(names: set[str], *, retain_all_events: bool = False) -> dict[str, object]:
        records = [call for call in calls if call["syscall"] in names]
        durations = [int(call["duration_ns"]) for call in records if call["duration_ns"] is not None]
        return {
            "count": len(records),
            "duration_ns_total": sum(durations),
            "duration_ns_max": max(durations, default=0),
            "duration_scope": "capture_window",
            "events": records if retain_all_events else records[:5],
        }

    futex = call_group({"futex", "futex_waitv"}, retain_all_events=True)
    terminal_waits = call_group(
        {"read", "readv", "poll", "ppoll", "select", "pselect6", "epoll_wait", "epoll_pwait", "epoll_pwait2"}
    )
    process_events = {
        "clone_or_fork_count": sum(
            call["syscall"] in {"clone", "clone3", "fork", "vfork"} for call in calls
        ),
        "exec_count": sum(call["syscall"] in {"execve", "execveat"} for call in calls),
        "wait_count": sum(call["syscall"] in {"wait4", "waitid"} for call in calls),
        "source": "strace -f syscall trace attached before the keypress",
    }
    signal_mask = call_group({"rt_sigprocmask"}, retain_all_events=True)
    signal_return = call_group({"rt_sigreturn"}, retain_all_events=True)
    return {
        "lock_wait_ns": futex["duration_ns_total"],
        "lock_wait_scope": "capture_window",
        "lock_wait_source": "capture-wide strace -T FUTEX_WAIT/FUTEX_WAITV syscall duration sum",
        "futex_wait": futex,
        "signal_mask": signal_mask,
        "signal_return": signal_return,
        "terminal_waits": terminal_waits,
        "terminal_syscalls": call_group({"write", "writev", "ioctl"}),
        "process_activity": process_events,
    }


def correlate_strace_events(
    native_capture: dict[str, object], event_window: dict[str, object]
) -> dict[str, object]:
    start_ns = event_window.get("keypress_realtime_ns")
    end_ns = event_window.get("redraw_complete_realtime_ns")
    valid_bounds = (
        isinstance(start_ns, int)
        and not isinstance(start_ns, bool)
        and isinstance(end_ns, int)
        and not isinstance(end_ns, bool)
        and end_ns >= start_ns
    )
    for group_name in ("futex_wait", "signal_mask"):
        group = native_capture.get(group_name)
        if not isinstance(group, dict):
            continue
        overlap_sum = 0
        correlated_count = 0
        events = group.get("events")
        if not isinstance(events, list):
            continue
        for event in events:
            if not isinstance(event, dict):
                continue
            timestamp_ns = event.get("timestamp_realtime_ns")
            duration_ns = event.get("duration_ns")
            if not valid_bounds:
                event["redraw_overlap_ns"] = None
                event["redraw_overlap_status"] = "missing-redraw-wall-clock-bounds"
                event["origin_evidence"] = "insufficient-time-evidence"
                continue
            if (
                not isinstance(timestamp_ns, int)
                or isinstance(timestamp_ns, bool)
                or not isinstance(duration_ns, int)
                or isinstance(duration_ns, bool)
            ):
                event["redraw_overlap_ns"] = None
                event["redraw_overlap_status"] = "missing-event-timestamp-or-duration"
                event["origin_evidence"] = "insufficient-time-evidence"
                continue
            overlap_ns = max(
                0,
                min(int(end_ns), timestamp_ns + duration_ns)
                - max(int(start_ns), timestamp_ns),
            )
            event["redraw_overlap_ns"] = overlap_ns
            event["redraw_overlap_status"] = "overlap" if overlap_ns else "outside-redraw-window"
            if overlap_ns:
                overlap_sum += overlap_ns
                correlated_count += 1
                event["origin_evidence"] = (
                    "overlapping-user-stack-candidate"
                    if isinstance(event.get("stack"), list) and event["stack"]
                    else "overlap-without-user-stack"
                )
            else:
                event["origin_evidence"] = "no-redraw-overlap"
        group["redraw_overlap_ns_sum"] = overlap_sum if valid_bounds else None
        group["redraw_correlated_event_count"] = correlated_count if valid_bounds else 0
        group["redraw_overlap_scope"] = "sum of per-event interval overlaps; concurrent calls can overlap"
    native_capture["redraw_correlation_source"] = (
        "strace -ttt realtime event timestamps and -T durations compared with Python time.time_ns bounds"
        if valid_bounds
        else "unavailable; redraw wall-clock bounds are missing or invalid"
    )
    native_capture["futex_wait_redraw_overlap_ns_sum"] = (
        native_capture.get("futex_wait", {}).get("redraw_overlap_ns_sum")
        if isinstance(native_capture.get("futex_wait"), dict)
        else None
    )
    return native_capture


def _mark_untraced_strace_groups(
    profile: dict[str, object], trace_syscalls: set[str]
) -> dict[str, object]:
    for group_name, syscall_names in (
        (
            "terminal_waits",
            {
                "read",
                "readv",
                "poll",
                "ppoll",
                "select",
                "pselect6",
                "epoll_wait",
                "epoll_pwait",
                "epoll_pwait2",
            },
        ),
        ("terminal_syscalls", {"write", "writev", "ioctl"}),
        ("signal_return", {"rt_sigreturn"}),
    ):
        if syscall_names & trace_syscalls:
            continue
        profile[group_name] = {
            "status": "not-traced",
            "scope": "excluded from the low-overhead strace -k syscall filter",
            "count": None,
            "duration_ns_total": None,
            "duration_ns_max": None,
            "events": [],
        }
    return profile


def parse_strace_profile(path: Path) -> dict[str, object]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    return _parse_strace_trace(text)


def parse_sample_profile(path: Path) -> dict[str, object]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    return parse_sample_profile_from_text(text)


def parse_sample_profile_from_text(text: str) -> dict[str, object]:
    header = re.search(
        r"^Analysis of sampling (?P<process>.+?) \(pid (?P<pid>\d+)\) every "
        r"(?P<interval>\d+) millisecond",
        text,
        re.MULTILINE,
    )
    lines = text.splitlines()
    symbols = (
        "__ulock_wait",
        "__ulock_wait2",
        "__pthread_sigmask",
        "pthread_sigmask",
        "pthread_mutex",
        "pthread_cond",
        "sb_thread_wait",
        "stop_the_world",
        "GC",
        "futex",
        "writev",
        "write",
        "execve",
        "posix_spawn",
        "kevent",
        "select",
        "poll",
        "read",
    )
    categories = {
        "named_mutex_wait": (
            "pthread_mutex",
            "pthread_cond",
            "__ulock_wait",
            "sb_thread_wait",
            "mutex_wait",
            "mutex_lock",
            "semaphore_wait",
            "futex",
        ),
        "signal_mask_or_gc_stop_the_world": (
            "pthread_sigmask",
            "sigprocmask",
            "stop_the_world",
            "stop-the-world",
            "gc_stop",
            "GC_STOP",
            "GC(",
        ),
        "terminal_protocol_wait": (
            "kevent",
            "select",
            "poll",
            "read",
            "readv",
            "pselect",
            "epoll",
        ),
        "terminal_stream_serialization": (
            "stream_write",
            "terminal",
            "writev",
            "write",
            "stdio",
            "fwrite",
            "fflush",
            "tcdrain",
        ),
        "subprocess_or_pipeline": (
            "posix_spawn",
            "fork",
            "execve",
            "waitpid",
            "wait4",
            "run-program",
            "subprocess",
            "pipeline",
        ),
    }
    stack_evidence = {
        category: [
            line.strip()
            for line in lines
            if any(
                re.search(
                    rf"(?<![A-Za-z0-9]){re.escape(symbol)}(?![A-Za-z0-9])",
                    line,
                    re.IGNORECASE,
                )
                for symbol in category_symbols
            )
        ][:20]
        for category, category_symbols in categories.items()
    }
    return {
        "lock_wait_ns": None,
        "lock_wait_source": "sample full-path thread stacks; syscall wait duration unavailable",
        "sampled_process": header.group("process") if header else None,
        "sampled_pid": int(header.group("pid")) if header else None,
        "sampling_interval_ms": int(header.group("interval")) if header else None,
        "sample_symbol_occurrences": {symbol: text.count(symbol) for symbol in symbols},
        "stack_evidence": stack_evidence,
        "process_activity": {
            "source": "sampled nshell thread stacks; child-process syscalls are not captured",
            "exec_count": None,
        },
    }


def _probe_strace(strace: str) -> tuple[tuple[str, ...] | None, str | None]:
    if strace in _STRACE_PROBE_CACHE:
        return _STRACE_PROBE_CACHE[strace]
    requested = NFR05_STRACE_SYSCALLS.split(",")
    candidates = [
        requested,
        [name for name in requested if name != "futex_waitv"],
        [name for name in requested if name != "clone3"],
        [name for name in requested if name not in {"futex_waitv", "clone3"}],
    ]
    last_error = "strace -k probe failed"
    for syscalls in candidates:
        result = subprocess.run(
            [
                strace,
                "-f",
                "-k",
                "-ttt",
                "-T",
                "-e",
                f"trace={','.join(syscalls)}",
                "-o",
                os.devnull,
                "/bin/true",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            outcome = (tuple(syscalls), None)
            _STRACE_PROBE_CACHE[strace] = outcome
            return outcome
        last_error = (result.stderr or result.stdout).strip() or last_error
    outcome = (None, last_error)
    _STRACE_PROBE_CACHE[strace] = outcome
    return outcome


def _probe_passwordless_sudo(sudo: str) -> tuple[bool, str]:
    if sudo not in _SUDO_PROBE_CACHE:
        result = subprocess.run([sudo, "-n", "true"], capture_output=True, text=True, check=False)
        _SUDO_PROBE_CACHE[sudo] = (
            result.returncode == 0,
            result.stderr.strip() or result.stdout.strip(),
        )
    return _SUDO_PROBE_CACHE[sudo]


class NativeCapture:
    def __init__(self, pid: int, profile_path: Path):
        self.pid = pid
        self.profile_path = profile_path.resolve()
        self.stderr_path = self.profile_path.with_suffix(self.profile_path.suffix + ".stderr.txt")
        self.system = platform.system()
        self.process: subprocess.Popen[bytes] | None = None
        self.stderr_stream = None
        self.finished = False
        self.result: dict[str, object] = {
            "status": "unavailable",
            "pid": pid,
            "profile_path": str(self.profile_path),
            "lock_wait_ns": None,
            "lock_wait_scope": "unavailable",
            "lock_wait_source": "native capture unavailable",
            "attachment_confirmed_before_keypress": False,
        }
        self._start()

    def _start(self) -> None:
        self.profile_path.parent.mkdir(parents=True, exist_ok=True)
        self.profile_path.unlink(missing_ok=True)
        self.stderr_path.unlink(missing_ok=True)
        if self.system == "Darwin":
            self._start_sample()
        elif self.system == "Linux":
            self._start_strace()
        else:
            self.result["reason"] = f"unsupported platform: {self.system}"

    def _start_sample(self) -> None:
        sample = Path("/usr/bin/sample")
        if not sample.is_file():
            self.result["reason"] = "/usr/bin/sample is unavailable"
            return
        self.stderr_stream = self.stderr_path.open("wb")
        capture_started_ns = time.monotonic_ns()
        try:
            self.process = subprocess.Popen(
                [str(sample), str(self.pid), "1", "1", "-mayDie", "-fullPaths", "-file", str(self.profile_path)],
                stdout=subprocess.DEVNULL,
                stderr=self.stderr_stream,
                start_new_session=True,
            )
        except OSError as error:
            self._close_stderr()
            self.result["reason"] = f"could not start sample: {error}"
            return
        time.sleep(0.025)
        if self.process.poll() is not None:
            self._close_stderr()
            self.result["reason"] = self._stderr_text() or "sample exited before the keypress"
            return
        self.result.update(
            {
                "status": "running",
                "method": "sample",
                "duration_seconds": 1,
                "sampling_interval_ms": 1,
                "capture_started_monotonic_ns": capture_started_ns,
                "attachment_confirmed_before_keypress": False,
                "attachment_confirmation_source": (
                    "sample writes its profile only after capture; process liveness is not "
                    "an attach acknowledgement"
                ),
                "lock_wait_source": "sample stack profile; no syscall wait duration",
            }
        )

    def _start_strace(self) -> None:
        strace = shutil.which("strace")
        sudo = shutil.which("sudo")
        if strace is None:
            self.result["reason"] = "strace is unavailable"
            return
        if sudo is None:
            self.result["reason"] = "sudo is unavailable for child attach"
            return
        syscalls, probe_error = _probe_strace(strace)
        if syscalls is None:
            self.result["reason"] = probe_error or "strace -k probe failed"
            return
        sudo_available, sudo_error = _probe_passwordless_sudo(sudo)
        if not sudo_available:
            self.result["reason"] = sudo_error or "passwordless sudo is unavailable"
            return
        self.stderr_stream = self.stderr_path.open("wb")
        capture_started_ns = time.monotonic_ns()
        try:
            self.process = subprocess.Popen(
                [
                    sudo,
                    "-n",
                    strace,
                    "-f",
                    "-k",
                    "-ttt",
                    "-T",
                    "-e",
                    f"trace={','.join(syscalls)}",
                    "-p",
                    str(self.pid),
                    "-o",
                    str(self.profile_path),
                ],
                stdout=subprocess.DEVNULL,
                stderr=self.stderr_stream,
                start_new_session=True,
            )
        except OSError as error:
            self._close_stderr()
            self.result["reason"] = f"could not start strace: {error}"
            return
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                self._close_stderr()
                self.result["reason"] = self._stderr_text() or "strace exited before attach"
                return
            stderr_text = self._stderr_text()
            attachment_match = next(
                (
                    match
                    for line in stderr_text.splitlines()
                    if (match := re.search(r"\bProcess\s+(\d+)\s+attached\b", line, re.IGNORECASE))
                    and int(match.group(1)) == self.pid
                ),
                None,
            )
            if attachment_match is not None:
                attachment_line = attachment_match.group(0)
                self.result.update(
                    {
                        "status": "running",
                        "method": "strace",
                        "capture_started_monotonic_ns": capture_started_ns,
                        "attachment_confirmed_before_keypress": True,
                        "attachment_confirmation_source": attachment_line,
                        "syscalls": list(syscalls),
                        "lock_wait_source": "strace -T futex wait durations with -k user stacks",
                        "signal_mask_source": "strace -T rt_sigprocmask durations with -k user stacks",
                    }
                )
                return
            time.sleep(0.01)
        self.result["reason"] = "strace attach was not confirmed within five seconds"
        self._signal_capture(signal.SIGINT)
        self._wait_capture(5.0)
        self._close_stderr()

    def _stderr_text(self) -> str:
        try:
            return self.stderr_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return ""

    def _close_stderr(self) -> None:
        if self.stderr_stream is not None:
            self.stderr_stream.close()
            self.stderr_stream = None

    def _signal_capture(self, signal_number: int) -> None:
        if self.process is None or self.process.poll() is not None:
            return
        try:
            os.killpg(self.process.pid, signal_number)
        except ProcessLookupError:
            pass

    def _wait_capture(self, timeout_seconds: float) -> int | None:
        if self.process is None:
            return None
        try:
            return self.process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            self._signal_capture(signal.SIGTERM)
            try:
                return self.process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self._signal_capture(signal.SIGKILL)
                return self.process.wait(timeout=2.0)

    def finish(self) -> dict[str, object]:
        if self.finished:
            return self.result
        self.finished = True
        try:
            if self.process is None:
                return self.result
            if self.system == "Linux":
                self._signal_capture(signal.SIGINT)
            return_code = self._wait_capture(10.0)
            self._close_stderr()
            profile_bytes = self.profile_path.stat().st_size if self.profile_path.is_file() else 0
            captured = profile_bytes > 0 and return_code in (
                0,
                -signal.SIGINT,
                128 + signal.SIGINT,
            )
            self.result.update(
                {
                    "status": "captured" if captured else "failed",
                    "return_code": return_code,
                    "profile_bytes": profile_bytes,
                    "stderr_path": str(self.stderr_path),
                    "stderr_text": self._stderr_text(),
                    "capture_finished_monotonic_ns": time.monotonic_ns(),
                }
            )
            if not captured:
                self.result["reason"] = self._stderr_text() or "native profiler produced no usable profile"
            elif self.system == "Linux":
                parsed_profile = parse_strace_profile(self.profile_path)
                self.result.update(
                    _mark_untraced_strace_groups(
                        parsed_profile,
                        set(self.result.get("syscalls", [])),
                    )
                )
            else:
                sample_profile = parse_sample_profile(self.profile_path)
                target_verified = sample_profile.get("sampled_pid") == self.pid
                self.result.update(sample_profile)
                self.result["attachment_confirmed_after_capture"] = target_verified
                if not target_verified:
                    self.result.update(
                        {
                            "status": "failed",
                            "reason": (
                                "sample report did not confirm the requested nshell PID "
                                f"{self.pid}"
                            ),
                        }
                    )
        except (OSError, subprocess.SubprocessError) as error:
            self._close_stderr()
            self.result.update({"status": "failed", "reason": str(error)})
        return self.result


def native_capture_factory(profile_path: Path) -> Callable[[int], Callable[[], dict[str, object]]]:
    def start(pid: int) -> Callable[[], dict[str, object]]:
        capture = NativeCapture(pid, profile_path)
        return capture.finish

    return start


def collect_samples(
    binary: Path,
    output_dir: Path,
    *,
    sample_count: int,
    warmup_count: int,
    settle_seconds: float,
) -> dict[str, object]:
    output_dir.mkdir(parents=True, exist_ok=True)
    samples_path = output_dir / "samples.jsonl"
    sample_rows: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="nshell-nfr05-plain-") as plain_dir:
        with tempfile.TemporaryDirectory(prefix="nshell-nfr05-home-") as home_dir:
            plain_fixture = Path(plain_dir)
            home_root = Path(home_dir)
            for index in range(warmup_count):
                sample_rows.append(
                    _run_sample(
                        binary,
                        plain_fixture,
                        home_root,
                        output_dir,
                        index,
                        "warmup",
                        settle_seconds,
                    )
                )
            sample_id = warmup_count
            for index in range(sample_count):
                modes = ("stage-control", "stage-native")
                if index % 2:
                    modes = tuple(reversed(modes))
                for role in modes:
                    sample_rows.append(
                        _run_sample(
                            binary,
                            plain_fixture,
                            home_root,
                            output_dir,
                            sample_id,
                            role,
                            settle_seconds,
                            pair_id=index,
                            native=role == "stage-native",
                        )
                    )
                    sample_id += 1

    control_rows = [row for row in sample_rows if row["sample_role"] == "stage-control"]
    native_rows = [row for row in sample_rows if row["sample_role"] == "stage-native"]
    if len(control_rows) != sample_count or len(native_rows) != sample_count:
        raise RuntimeError("NFR-05 diagnostic run did not produce every paired stage sample")
    with samples_path.open("w", encoding="utf-8") as stream:
        for row in sample_rows:
            stream.write(json.dumps(row, sort_keys=True) + "\n")
    summary = summarize_diagnostic_samples(sample_rows)
    native_capture_rows = [
        row.get("native_capture")
        for row in native_rows
        if isinstance(row.get("native_capture"), dict)
    ]
    captured_count = sum(capture.get("status") == "captured" for capture in native_capture_rows)
    pre_key_confirmed_count = sum(
        capture.get("attachment_confirmed_before_keypress") is True
        for capture in native_capture_rows
    )
    profile_verified_count = sum(
        capture.get("attachment_confirmed_after_capture") is True
        for capture in native_capture_rows
    )
    native_profiles = [
        {
            "sample_id": row["sample_id"],
            "pair_id": row["pair_id"],
            "latency_ms": row["latency_ms"],
            "status": capture.get("status"),
            "pid": capture.get("pid"),
            "attachment_confirmed_before_keypress": capture.get(
                "attachment_confirmed_before_keypress"
            ),
            "attachment_confirmed_after_capture": capture.get(
                "attachment_confirmed_after_capture"
            ),
            "profile_path": capture.get("profile_path"),
            "profile_bytes": capture.get("profile_bytes"),
            "event_window": capture.get("event_window"),
        }
        for row in native_rows
        if isinstance((capture := row.get("native_capture")), dict)
    ]
    summary.update(
        {
            "record": "nfr05-diagnostic-summary",
            "schema_version": 1,
            "status": (
                "PASS"
                if captured_count == sample_count
                and pre_key_confirmed_count == sample_count
                else "WARNING"
            ),
            "binary": str(binary),
            "scenario": {
                "prompt": "marker",
                "preloaded_buffer_characters": 999,
                "keypress": "x",
                "command_execution_requested": False,
                "git_prompt_enabled": False,
            },
            "warmup_count": warmup_count,
            "stage_pair_count": sample_count,
            "stage_sample_count": len(control_rows) + len(native_rows),
            "profiler_overhead": {
                "traced_stage_sample_count": len(native_rows),
                "untraced_control_sample_count": len(control_rows),
                "native_profile_capture_count": captured_count,
                "pre_key_attachment_confirmed_count": pre_key_confirmed_count,
                "post_capture_profile_pid_verified_count": profile_verified_count,
                "interpretation": (
                    "paired traced and untraced diagnostic redraws estimate profiler impact; "
                    "these values are outside the official acceptance gate"
                ),
            },
            "native_capture": {
                "method": platform.system(),
                "status": "captured" if captured_count == sample_count else "WARNING",
                "sample_count": len(native_rows),
                "captured_count": captured_count,
                "pre_key_attachment_confirmed_count": pre_key_confirmed_count,
                "post_capture_profile_pid_verified_count": profile_verified_count,
                "profiles": native_profiles,
                "raw_profile_directory": str(output_dir / "native"),
            },
            "samples_path": str(samples_path),
        }
    )
    summary_path = output_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return summary


def _run_sample(
    binary: Path,
    plain_fixture: Path,
    home_root: Path,
    output_dir: Path,
    sample_id: int,
    role: str,
    settle_seconds: float,
    *,
    pair_id: int | None = None,
    native: bool = False,
) -> dict[str, object]:
    sidecar = output_dir / "sidecars" / f"sample-{sample_id:03d}.json"
    kwargs: dict[str, object] = {
        "diagnostic_sidecar": sidecar,
    }
    if native:
        profile_path = output_dir / "native" / f"sample-{sample_id:03d}.{platform.system().lower()}.txt"
        kwargs["native_capture"] = native_capture_factory(profile_path)
    result = MEASURE.run_redraw_sample(
        binary,
        plain_fixture,
        home_root,
        "NFR05-MARKER",
        1000,
        settle_seconds,
        **kwargs,
    )
    diagnostic = validate_diagnostic_record(result.get("diagnostics"))
    if (
        result.get("keypress") != "x"
        or result.get("preloaded_buffer_characters") != 999
        or result.get("redrawn_buffer_characters") != 1000
        or result.get("redrawn_prompt_seen") is not True
    ):
        raise RuntimeError("NFR-05 diagnostic sample did not verify the marker prompt and 1000-character redraw")
    native_capture_result = result.get("native_capture")
    if isinstance(native_capture_result, dict):
        event_window = native_capture_result.get("event_window")
        if platform.system() == "Linux" and isinstance(event_window, dict):
            correlate_strace_events(native_capture_result, event_window)
        else:
            native_capture_result["redraw_correlation_source"] = (
                "per-event realtime syscall correlation is unavailable for this capture"
            )
        native_capture_result["terminal_protocol"] = {
            "cursor_query_count": result.get("cursor_query_count"),
            "cursor_response_count": result.get("cursor_response_count"),
            "wait_syscalls": native_capture_result.get("terminal_waits"),
            "wait_syscall_scope": "capture_window; individual syscall events carry redraw overlap when available",
            "sampled_stack_wait_candidates": native_capture_result.get(
                "stack_evidence", {}
            ).get("terminal_protocol_wait", []),
        }
    return {
        "sample_id": sample_id,
        "pair_id": pair_id,
        "sample_role": role,
        "latency_ms": result["latency_ms"],
        "diagnostics": diagnostic,
        "native_capture": result.get("native_capture"),
        "redrawn_prompt_seen": result["redrawn_prompt_seen"],
        "redrawn_buffer_characters": result["redrawn_buffer_characters"],
        "cursor_queries": result["cursor_queries"],
        "cursor_query_count": result.get("cursor_query_count"),
        "cursor_response_count": result.get("cursor_response_count"),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Collect opt-in NFR-05 render and native-wait diagnostics without changing the official gate."
    )
    parser.add_argument("--binary", required=True, help="built nshell executable")
    parser.add_argument("--output-dir", required=True, help="directory for raw diagnostic samples and profiles")
    parser.add_argument("--samples", type=int, default=100, help="number of stage samples (default: 100)")
    parser.add_argument("--warmups", type=int, default=2, help="number of unreported warmups (default: 2)")
    parser.add_argument("--settle-ms", type=float, default=50.0, help="settle time before keypress (default: 50)")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.samples < 1 or args.warmups < 0 or args.settle_ms < 0:
        print("samples must be positive; warmups and settle-ms must be nonnegative", file=sys.stderr)
        return 2
    try:
        binary = MEASURE.validate_executable(args.binary, "--binary")
        output_dir = Path(args.output_dir).expanduser().resolve()
        MEASURE.ensure_outside_repository(output_dir, "--output-dir")
        summary = collect_samples(
            binary,
            output_dir,
            sample_count=args.samples,
            warmup_count=args.warmups,
            settle_seconds=args.settle_ms / 1000,
        )
    except (OSError, RuntimeError, TimeoutError, ValueError, subprocess.SubprocessError) as error:
        print(f"NFR-05 diagnostics failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
