#!/usr/bin/env python3
"""Measure nshell startup with 10,000 persisted history records."""

from __future__ import annotations

import argparse
import collections
import fcntl
import hashlib
import json
import os
import platform
import pty
import re
import select
import shutil
import signal
import statistics
import struct
import subprocess
import sys
import termios
import time
import uuid
from pathlib import Path
from typing import Any


RECORD_COUNT = 10_000
HISTORY_PREFIX = b"# nshell-history-v3 "
PROMPT_TIMEOUT_SECONDS = 60.0
PROMPT_THRESHOLD_MS = 150.0
SAMPLE_COUNT = 30
WARMUP_COUNT = 3
CPR_QUERY = b"\x1b[6n"
CPR_RESPONSE = b"\x1b[1;1R"
LOGS_PATH_PARTS = (".mediator", "nshell-work", "logs")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure startup to first prompt with 10,000 valid history records."
    )
    parser.add_argument("--binary", required=True, type=Path, help="built nshell executable")
    parser.add_argument(
        "--system",
        required=True,
        choices=("aarch64-darwin", "x86_64-linux"),
        help="system label for this measurement host",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="new JSON report path inside .mediator/nshell-work/logs",
    )
    return parser.parse_args()


def is_under_launch_logs(path: Path) -> bool:
    parts = path.parts
    return any(
        parts[index : index + len(LOGS_PATH_PARTS)] == LOGS_PATH_PARTS
        for index in range(len(parts) - len(LOGS_PATH_PARTS) + 1)
    )


def validate_host(system: str) -> None:
    expected = {
        "aarch64-darwin": ("Darwin", {"arm64", "aarch64"}),
        "x86_64-linux": ("Linux", {"x86_64", "amd64"}),
    }
    os_name, architectures = expected[system]
    actual_os = platform.system()
    actual_architecture = platform.machine().lower()
    if actual_os != os_name or actual_architecture not in architectures:
        raise RuntimeError(
            f"--system {system} does not match host {actual_architecture}-{actual_os.lower()}"
        )



def uptime_snapshot() -> dict[str, Any]:
    raw = subprocess.check_output(["uptime"], text=True).strip()
    match = re.search(
        r"load averages?:\s*([0-9]+(?:\.[0-9]+)?)\D+"
        r"([0-9]+(?:\.[0-9]+)?)\D+([0-9]+(?:\.[0-9]+)?)",
        raw,
        re.IGNORECASE,
    )
    if match is None:
        raise RuntimeError(f"cannot parse load averages from uptime output: {raw}")
    return {
        "raw": raw,
        "load_average_1_5_15": [float(match.group(index)) for index in (1, 2, 3)],
    }


def history_record_payload(index: int) -> bytes:
    text = f"echo NSHELL_E02_RECORD_{index:05d}"
    payload = (
        f'(:text "{text}" :timestamp {1_700_000_000 + index} '
        ':cwd "/e02-measurement" :exit-code 0 :duration-ms 1 '
        ':origin :typed :host "nshell-e02-measurement")'
    )
    return payload.encode("ascii")


def write_history_fixture(path: Path) -> dict[str, Any]:
    with path.open("xb") as stream:
        for index in range(RECORD_COUNT):
            payload = history_record_payload(index)
            stream.write(HISTORY_PREFIX + str(len(payload)).encode("ascii") + b"\n")
            stream.write(payload + b"\n")
    return validate_history_fixture(path)


def validate_history_fixture(path: Path) -> dict[str, Any]:
    validated_count = 0
    with path.open("rb") as stream:
        while header := stream.readline():
            if not header.startswith(HISTORY_PREFIX) or not header.endswith(b"\n"):
                raise RuntimeError(f"invalid history header at record {validated_count}")
            length_text = header[len(HISTORY_PREFIX) : -1]
            if not length_text.isdigit():
                raise RuntimeError(f"invalid history length at record {validated_count}")
            payload = stream.read(int(length_text))
            if payload != history_record_payload(validated_count):
                raise RuntimeError(f"invalid history payload at record {validated_count}")
            if stream.read(1) != b"\n":
                raise RuntimeError(f"invalid history separator at record {validated_count}")
            validated_count += 1
            if validated_count > RECORD_COUNT:
                raise RuntimeError("history fixture contains more than 10,000 records")

    if validated_count != RECORD_COUNT:
        raise RuntimeError(f"history fixture has {validated_count} records, expected {RECORD_COUNT}")

    fixture_bytes = path.read_bytes()
    return {
        "path": str(path),
        "expected_record_count": RECORD_COUNT,
        "validated_record_count": validated_count,
        "file_bytes": len(fixture_bytes),
        "sha256": hashlib.sha256(fixture_bytes).hexdigest(),
        "first_record": "echo NSHELL_E02_RECORD_00000",
        "last_record": f"echo NSHELL_E02_RECORD_{RECORD_COUNT - 1:05d}",
    }


def runtime_environment(home: Path, prompt: str) -> dict[str, str]:
    directories = {
        "HOME": home,
        "XDG_CONFIG_HOME": home / "config",
        "XDG_DATA_HOME": home / "data",
        "XDG_STATE_HOME": home / "state",
        "XDG_CACHE_HOME": home / "cache",
        "TMPDIR": home / "tmp",
    }
    for path in directories.values():
        path.mkdir(parents=True, exist_ok=True)
    return {
        **{name: str(path) for name, path in directories.items()},
        "PATH": "/usr/bin:/bin",
        "TERM": "xterm-256color",
        "LANG": "C",
        "LC_ALL": "C",
        "NSHELL_GREETING": "",
        "NSHELL_AI_COMMAND": "/nonexistent",
        "NSHELL_PROMPT": prompt,
        "NSHELL_E02_HISTORY_DONE": f"NSHELL_E02_HISTORY_DONE_{uuid.uuid4().hex}",
        "PS1": prompt,
    }


def write_all(fd: int, payload: bytes) -> None:
    view = memoryview(payload)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            raise OSError("PTY write made no progress")
        view = view[written:]


def wait_for_marker(
    master: int,
    output: bytearray,
    marker: bytes,
    answered_queries: int,
    timeout: float,
) -> tuple[int, int]:
    deadline = time.monotonic() + timeout
    while marker not in output:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            tail = bytes(output[-800:]).decode("utf-8", "replace")
            raise TimeoutError(f"prompt marker timed out after {timeout}s; output tail={tail!r}")
        ready, _, _ = select.select([master], [], [], remaining)
        if not ready:
            continue
        try:
            chunk = os.read(master, 8192)
        except OSError as exc:
            tail = bytes(output[-800:]).decode("utf-8", "replace")
            raise RuntimeError(f"PTY exited before prompt marker; output tail={tail!r}") from exc
        if not chunk:
            tail = bytes(output[-800:]).decode("utf-8", "replace")
            raise RuntimeError(f"PTY closed before prompt marker; output tail={tail!r}")
        output.extend(chunk)
        marker_seen_ns = time.perf_counter_ns() if marker in output else None
        query_count = output.count(CPR_QUERY)
        while answered_queries < query_count:
            write_all(master, CPR_RESPONSE)
            answered_queries += 1
        if marker_seen_ns is not None:
            return answered_queries, marker_seen_ns
    raise RuntimeError("marker was already present before PTY wait")


def terminate_child(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

    deadline = time.monotonic() + 1.0
    while time.monotonic() < deadline:
        try:
            waited, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return
        if waited == pid:
            return
        time.sleep(0.01)

    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def loaded_record_summary(path: Path) -> dict[str, Any]:
    pattern = re.compile(rb"^echo NSHELL_E02_RECORD_(\d{5})$")
    counts: collections.Counter[int] = collections.Counter()
    with path.open("rb") as stream:
        for line in stream.read().splitlines():
            match = pattern.fullmatch(line)
            if match:
                counts[int(match.group(1))] += 1

    expected = set(range(RECORD_COUNT))
    loaded = set(counts)
    missing = sorted(expected - loaded)
    duplicates = sorted(index for index, count in counts.items() if count != 1)
    return {
        "history_output_path": str(path),
        "loaded_record_count": len(loaded),
        "expected_record_count": RECORD_COUNT,
        "missing_record_count": len(missing),
        "duplicate_record_count": len(duplicates),
        "first_loaded_record": (
            f"echo NSHELL_E02_RECORD_{min(loaded):05d}" if loaded else None
        ),
        "last_loaded_record": (
            f"echo NSHELL_E02_RECORD_{max(loaded):05d}" if loaded else None
        ),
        "all_records_loaded_once": not missing and not duplicates and loaded == expected,
    }


def measure_pty(
    command: list[str],
    env: dict[str, str],
    cwd: Path,
    marker: str,
    artifact_dir: Path,
    report: dict[str, Any],
    verify_history: bool,
) -> None:
    output = bytearray()
    log_path = artifact_dir / "pty-output.bin"
    pid: int | None = None
    master: int | None = None
    try:
        started_ns = time.perf_counter_ns()
        pid, master = pty.fork()
        if pid == 0:
            try:
                os.chdir(cwd)
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
                os.execve(command[0], command, env)
            except OSError as exc:
                try:
                    os.write(2, f"exec failed: {exc}\n".encode())
                except OSError:
                    pass
                os._exit(127)

        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        answered_queries, first_prompt_ns = wait_for_marker(
            master,
            output,
            marker.encode("ascii"),
            0,
            PROMPT_TIMEOUT_SECONDS,
        )
        elapsed_ns = first_prompt_ns - started_ns
        report["startup"] = {
            "elapsed_ns": elapsed_ns,
            "elapsed_ms": elapsed_ns / 1_000_000,
            "threshold_ms": PROMPT_THRESHOLD_MS,
            "threshold_passed": elapsed_ns <= PROMPT_THRESHOLD_MS * 1_000_000,
            "measurement_boundary": "PTY fork start through first unique prompt marker",
            "prompt_marker": marker,
            "cpr_queries_answered": answered_queries,
        }

        if verify_history:
            history_done_marker = env["NSHELL_E02_HISTORY_DONE"].encode("ascii")
            write_all(
                master,
                b'history > e02-loaded-history.txt; echo "$NSHELL_E02_HISTORY_DONE"\r',
            )
            answered_queries, _ = wait_for_marker(
                master,
                output,
                history_done_marker,
                answered_queries,
                PROMPT_TIMEOUT_SECONDS,
            )
            report["startup"]["cpr_queries_answered_total"] = answered_queries
            loaded = loaded_record_summary(cwd / "e02-loaded-history.txt")
            report["history_load_verification"] = loaded
            if not loaded["all_records_loaded_once"]:
                raise RuntimeError(
                    "history output did not contain each of the 10,000 fixture records exactly once"
                )
    finally:
        log_path.write_bytes(output)
        report["pty_log"] = {
            "path": str(log_path),
            "bytes": len(output),
            "sha256": hashlib.sha256(output).hexdigest(),
        }
        if master is not None:
            try:
                os.close(master)
            except OSError:
                pass
        if pid is not None and pid != 0:
            terminate_child(pid)



def run_arm(
    arm: str,
    process_name: str,
    binary: Path,
    fixture_path: Path,
    fixture_sha256: str,
    artifact_dir: Path,
    report: dict[str, Any],
) -> None:
    process_dir = artifact_dir / process_name
    process_dir.mkdir()
    home = process_dir / "home"
    cwd = process_dir / "work"
    cwd.mkdir()
    prompt = f"NSHELL_E02_PROMPT_{uuid.uuid4().hex}_END> "
    env = runtime_environment(home, prompt)
    history_path = Path(env["XDG_DATA_HOME"]) / "nshell" / "history"
    history_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fixture_path, history_path)
    restored_fixture = validate_history_fixture(history_path)
    if restored_fixture["sha256"] != fixture_sha256:
        raise RuntimeError(f"{process_name}: restored history fixture digest changed")

    report.update({
        "arm": arm,
        "process": process_name,
        "fixture_before_startup": restored_fixture,
        "isolated_environment": {
            name: env[name]
            for name in (
                "HOME",
                "XDG_CONFIG_HOME",
                "XDG_DATA_HOME",
                "XDG_STATE_HOME",
                "XDG_CACHE_HOME",
                "TMPDIR",
            )
        },
    })
    command = [str(binary)] if arm == "target" else ["/bin/sh", "-i"]
    report["uptime_before"] = uptime_snapshot()
    measure_pty(
        command,
        env,
        cwd,
        prompt,
        process_dir,
        report,
        verify_history=arm == "target",
    )
    report["uptime_after"] = uptime_snapshot()


def run_pair(
    phase: str,
    number: int,
    pair_index: int,
    binary: Path,
    fixture_path: Path,
    fixture_sha256: str,
    artifact_dir: Path,
    pairs: list[dict[str, Any]],
) -> None:
    order = ("target", "control") if pair_index % 2 else ("control", "target")
    pair: dict[str, Any] = {
        "record": phase,
        "pair_index": pair_index,
        phase: number,
        "order": list(order),
        "arms": {},
    }
    pairs.append(pair)
    for arm in order:
        arm_report: dict[str, Any] = {}
        pair["arms"][arm] = arm_report
        run_arm(
            arm,
            f"{phase}-{number:02d}-{arm}",
            binary,
            fixture_path,
            fixture_sha256,
            artifact_dir,
            arm_report,
        )


def summary_for(samples: list[dict[str, Any]]) -> dict[str, Any]:
    target_ns = [sample["arms"]["target"]["startup"]["elapsed_ns"] for sample in samples]
    control_ns = [sample["arms"]["control"]["startup"]["elapsed_ns"] for sample in samples]
    paired_ns = [target - control for target, control in zip(target_ns, control_ns)]
    target_median_ns = statistics.median(target_ns)
    control_median_ns = statistics.median(control_ns)
    target_median_ms = target_median_ns / 1_000_000
    control_median_ms = control_median_ns / 1_000_000
    return {
        "sample_count": len(samples),
        "target_samples_ns": target_ns,
        "target_samples_ms": [value / 1_000_000 for value in target_ns],
        "control_samples_ns": control_ns,
        "control_samples_ms": [value / 1_000_000 for value in control_ns],
        "paired_delta_ms": [value / 1_000_000 for value in paired_ns],
        "target_median_ms": target_median_ms,
        "control_median_ms": control_median_ms,
        "absolute_difference_of_medians_ms": abs(target_median_ns - control_median_ns)
        / 1_000_000,
        "median_signed_paired_delta_ms": statistics.median(paired_ns) / 1_000_000,
        "median_absolute_paired_delta_ms": statistics.median(
            [abs(value) for value in paired_ns]
        )
        / 1_000_000,
        "criterion_median_ms": target_median_ms,
        "criterion_threshold_ms": PROMPT_THRESHOLD_MS,
        "threshold_passed": target_median_ns <= PROMPT_THRESHOLD_MS * 1_000_000,
    }


def main() -> int:
    args = parse_args()
    output_path = args.output.expanduser().resolve()
    if not is_under_launch_logs(output_path):
        print("--output must be inside .mediator/nshell-work/logs", file=sys.stderr)
        return 2
    if output_path.exists():
        print(f"report already exists: {output_path}", file=sys.stderr)
        return 2

    output_path.parent.mkdir(parents=True, exist_ok=True)
    artifact_dir = output_path.parent / f"{output_path.stem}-artifacts-{uuid.uuid4().hex}"
    artifact_dir.mkdir(parents=True, exist_ok=False)
    report: dict[str, Any] = {
        "schema_version": 1,
        "measurement": "E02",
        "system": args.system,
        "platform": platform.platform(),
        "machine": platform.machine(),
        "binary": str(args.binary.expanduser().resolve()),
        "artifact_dir": str(artifact_dir),
        "sample_count": SAMPLE_COUNT,
        "warmup_count": WARMUP_COUNT,
        "timing_clock": "time.perf_counter_ns",
        "target": "nshell interactive startup with 10,000 history records",
        "same_host_control": "/bin/sh -i startup in the same isolated environment",
        "arm_order": "target first on odd paired indices, control first on even indices",
        "warmups": [],
        "samples": [],
        "status": "error",
    }

    try:
        validate_host(args.system)
        binary = args.binary.expanduser().resolve(strict=True)
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise RuntimeError(f"binary is not an executable file: {binary}")

        fixture_path = artifact_dir / "history-v3.fixture"
        fixture = write_history_fixture(fixture_path)
        report["history_fixture"] = fixture
        for warmup_number in range(1, WARMUP_COUNT + 1):
            run_pair(
                "warmup",
                warmup_number,
                warmup_number,
                binary,
                fixture_path,
                fixture["sha256"],
                artifact_dir,
                report["warmups"],
            )
        for sample_number in range(1, SAMPLE_COUNT + 1):
            pair_index = WARMUP_COUNT + sample_number
            run_pair(
                "sample",
                sample_number,
                pair_index,
                binary,
                fixture_path,
                fixture["sha256"],
                artifact_dir,
                report["samples"],
            )

        summary = summary_for(report["samples"])
        report["summary"] = summary
        report["threshold_passed"] = summary["threshold_passed"]
        report["status"] = "measured"
        exit_code = 0
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
        exit_code = 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(report, indent=2, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
