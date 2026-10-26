#!/usr/bin/env python3
"""Measure NFR-01 through NFR-03 with paired same-host controls."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
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

from wp_perf_nfr_thresholds import NFR_THRESHOLDS


PROMPT_PREFIX = "__WP_PERF_PROMPT_"
CPR_QUERY = b"\x1b[6n"
CPR_RESPONSE = b"\x1b[1;1R"
CONTROL_SCRIPT = (
    "i=0; while [ \"$i\" -lt 1000 ]; do /usr/bin/true; "
    "i=$((i + 1)); done"
)
NFR_CONFIG = {
    "01": {
        "target": "nshell startup to first prompt",
        "control": "interactive /bin/sh startup to the same unique prompt marker",
        "threshold_ms": NFR_THRESHOLDS["01"]["limit"],
    },
    "02": {
        "target": "nshell -c true",
        "control": "/bin/sh -c true",
        "threshold_ms": NFR_THRESHOLDS["02"]["limit"],
    },
    "03": {
        "target": "input script launching /usr/bin/true 1000 times",
        "control": "/bin/sh loop launching /usr/bin/true 1000 times",
        "threshold_ms": NFR_THRESHOLDS["03"]["limit"],
    },
}


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def nonnegative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be a nonnegative integer")
    return parsed


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Measure NFR-01 startup, NFR-02 paired -c true, and NFR-03 "
            "1000 external commands. Paired order alternates across warmups and samples."
        )
    )
    parser.add_argument("--nfr", required=True, choices=("01", "02", "03", "all"))
    parser.add_argument("--binary", required=True, type=Path, help="nshell executable")
    parser.add_argument(
        "--input",
        type=Path,
        help="NFR-03 input script; required for --nfr 03 or --nfr all",
    )
    parser.add_argument("--samples", required=True, type=positive_int)
    parser.add_argument(
        "--warmups",
        type=nonnegative_int,
        default=3,
        help="paired warmup count per NFR (default: 3)",
    )
    parser.add_argument("--output", required=True, type=Path, help="new JSONL output path")
    parser.add_argument("--timeout", type=positive_float, default=60.0)
    args = parser.parse_args()

    if args.nfr in ("03", "all") and args.input is None:
        parser.error("--input is required for --nfr 03 or --nfr all")
    if args.nfr in ("01", "02") and args.input is not None:
        parser.error("--input is only used for --nfr 03 or --nfr all")
    return args


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


def runtime_environment(home: Path, prompt: str | None = None) -> dict[str, str]:
    for name in ("config", "data", "state", "cache", "tmp"):
        (home / name).mkdir(parents=True, exist_ok=True)
    env = {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / "config"),
        "XDG_DATA_HOME": str(home / "data"),
        "XDG_STATE_HOME": str(home / "state"),
        "XDG_CACHE_HOME": str(home / "cache"),
        "TMPDIR": str(home / "tmp"),
        "PATH": "/usr/bin:/bin",
        "TERM": "xterm-256color",
        "LANG": "C",
        "LC_ALL": "C",
        "NSHELL_GREETING": "",
        "NSHELL_AI_COMMAND": "/nonexistent",
    }
    if prompt is not None:
        env["NSHELL_PROMPT"] = prompt
        env["PS1"] = prompt
    return env


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


def prompt_startup(
    command: list[str], env: dict[str, str], cwd: Path, marker: bytes, timeout: float
) -> dict[str, Any]:
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

    output = bytearray()
    answered_queries = 0
    try:
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        deadline = time.monotonic() + timeout
        while marker not in output:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                tail = bytes(output[-500:]).decode("utf-8", "replace")
                raise TimeoutError(f"prompt timed out after {timeout}s; output tail={tail!r}")
            ready, _, _ = select.select([master], [], [], remaining)
            if not ready:
                continue
            try:
                chunk = os.read(master, 8192)
            except OSError as exc:
                tail = bytes(output[-500:]).decode("utf-8", "replace")
                raise RuntimeError(f"process exited before prompt; output tail={tail!r}") from exc
            if not chunk:
                tail = bytes(output[-500:]).decode("utf-8", "replace")
                raise RuntimeError(f"process closed PTY before prompt; output tail={tail!r}")
            output.extend(chunk)
            query_count = output.count(CPR_QUERY)
            while answered_queries < query_count:
                os.write(master, CPR_RESPONSE)
                answered_queries += 1

        return {
            "elapsed_ns": time.perf_counter_ns() - started_ns,
            "output_bytes": len(output),
            "cpr_queries_answered": answered_queries,
        }
    finally:
        try:
            os.close(master)
        finally:
            terminate_child(pid)


def command_timing(
    command: list[str],
    env: dict[str, str],
    timeout: float,
    input_path: Path | None = None,
) -> dict[str, Any]:
    input_stream = input_path.open("rb") if input_path is not None else None
    started_ns = time.perf_counter_ns()
    try:
        try:
            result = subprocess.run(
                command,
                stdin=input_stream,
                env=env,
                capture_output=True,
                check=False,
                timeout=timeout,
            )
            timed_out = False
            returncode: int | None = result.returncode
            stdout_bytes = len(result.stdout)
            stderr_bytes = len(result.stderr)
        except subprocess.TimeoutExpired as exc:
            timed_out = True
            returncode = None
            stdout_bytes = len(exc.stdout or b"")
            stderr_bytes = len(exc.stderr or b"")
        return {
            "elapsed_ns": time.perf_counter_ns() - started_ns,
            "returncode": returncode,
            "timed_out": timed_out,
            "stdout_bytes": stdout_bytes,
            "stderr_bytes": stderr_bytes,
        }
    finally:
        if input_stream is not None:
            input_stream.close()


def measured_arm(action: Callable[[], dict[str, Any]]) -> dict[str, Any]:
    before = uptime_snapshot()
    result = action()
    after = uptime_snapshot()
    result["elapsed_ms"] = result["elapsed_ns"] / 1_000_000
    result["uptime_before"] = before
    result["uptime_after"] = after
    return result


def require_success(arm_name: str, result: dict[str, Any]) -> None:
    if result.get("timed_out"):
        raise RuntimeError(f"{arm_name} timed out")
    if result.get("returncode") not in (None, 0):
        raise RuntimeError(f"{arm_name} exited with status {result['returncode']}")


def write_record(stream: Any, record: dict[str, Any]) -> None:
    stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    stream.flush()


def summary_for(
    nfr: str,
    samples: list[dict[str, Any]],
    target_name: str,
    control_name: str,
) -> dict[str, Any]:
    target_ns = [sample["arms"][target_name]["elapsed_ns"] for sample in samples]
    control_ns = [sample["arms"][control_name]["elapsed_ns"] for sample in samples]
    paired_ns = [target - control for target, control in zip(target_ns, control_ns)]
    target_median_ns = median(target_ns)
    control_median_ns = median(control_ns)
    summary: dict[str, Any] = {
        "record": "summary",
        "nfr": nfr,
        "sample_count": len(samples),
        "target_median_ms": target_median_ns / 1_000_000,
        "control_median_ms": control_median_ns / 1_000_000,
        "absolute_difference_of_medians_ms": abs(target_median_ns - control_median_ns)
        / 1_000_000,
        "median_signed_paired_delta_ms": median(paired_ns) / 1_000_000,
        "median_absolute_paired_delta_ms": median([abs(value) for value in paired_ns])
        / 1_000_000,
        "target_samples_ns": target_ns,
        "control_samples_ns": control_ns,
    }
    if nfr == "02":
        summary["criterion_difference_ms"] = summary["absolute_difference_of_medians_ms"]
        summary["criterion_threshold_ms"] = NFR_CONFIG[nfr]["threshold_ms"]
    elif nfr in ("01", "03"):
        summary["criterion_median_ms"] = summary["target_median_ms"]
        summary["criterion_threshold_ms"] = NFR_CONFIG[nfr]["threshold_ms"]
    return summary


def nfr01_arms(binary: Path, timeout: float) -> dict[str, Callable[[], dict[str, Any]]]:
    target_marker = f"{PROMPT_PREFIX}{os.urandom(8).hex()}__"
    control_marker = f"{PROMPT_PREFIX}{os.urandom(8).hex()}__"

    def nshell_action() -> dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="wp-perf-nfr01-") as directory:
            home = Path(directory)
            env = runtime_environment(home, target_marker)
            return prompt_startup(
                [str(binary)], env, home, target_marker.encode(), timeout
            )

    def shell_action() -> dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="wp-perf-nfr01-sh-") as directory:
            home = Path(directory)
            env = runtime_environment(home, control_marker)
            return prompt_startup(
                ["/bin/sh", "-i"], env, home, control_marker.encode(), timeout
            )

    return {"target": nshell_action, "control": shell_action}


def nfr02_arms(binary: Path, timeout: float) -> dict[str, Callable[[], dict[str, Any]]]:
    def timed(command: list[str]) -> dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="wp-perf-nfr02-") as directory:
            env = runtime_environment(Path(directory))
            return command_timing(command, env, timeout)

    return {
        "target": lambda: timed([str(binary), "-c", "true"]),
        "control": lambda: timed(["/bin/sh", "-c", "true"]),
    }


def nfr03_arms(
    binary: Path, input_path: Path, timeout: float
) -> dict[str, Callable[[], dict[str, Any]]]:
    def target() -> dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="wp-perf-nfr03-") as directory:
            env = runtime_environment(Path(directory))
            return command_timing([str(binary)], env, timeout, input_path)

    def control() -> dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="wp-perf-nfr03-sh-") as directory:
            env = runtime_environment(Path(directory))
            return command_timing(["/bin/sh", "-c", CONTROL_SCRIPT], env, timeout)

    return {
        "target": target,
        "control": control,
    }


def run_group(
    nfr: str,
    binary: Path,
    input_path: Path | None,
    sample_count: int,
    warmup_count: int,
    timeout: float,
    stream: Any,
) -> dict[str, Any]:
    config = NFR_CONFIG[nfr]
    arms = (
        nfr01_arms(binary, timeout)
        if nfr == "01"
        else nfr02_arms(binary, timeout)
        if nfr == "02"
        else nfr03_arms(binary, input_path, timeout)
    )
    metadata: dict[str, Any] = {
        "record": "group",
        "nfr": nfr,
        "platform": platform.platform(),
        "machine": platform.machine(),
        "binary": str(binary),
        "sample_count": sample_count,
        "warmup_count": warmup_count,
        "timeout_seconds": timeout,
        "target": config["target"],
        "same_host_control": config["control"],
        "threshold_ms": config["threshold_ms"],
        "timing_clock": "time.perf_counter_ns",
        "uptime_command": "uptime",
        "arm_order": "target first on odd paired indices, control first on even indices",
    }
    if nfr == "03" and input_path is not None:
        metadata["input"] = str(input_path)
        metadata["input_sha256"] = hashlib.sha256(input_path.read_bytes()).hexdigest()
        metadata["control_script"] = CONTROL_SCRIPT
    write_record(stream, metadata)

    def measure_pair(pair_index: int) -> tuple[tuple[str, str], dict[str, dict[str, Any]]]:
        order = ("target", "control") if pair_index % 2 else ("control", "target")
        measured = {arm_name: measured_arm(arms[arm_name]) for arm_name in order}
        return order, measured

    for warmup_number in range(1, warmup_count + 1):
        order, measured = measure_pair(warmup_number)
        warmup = {
            "record": "warmup",
            "nfr": nfr,
            "warmup": warmup_number,
            "warmup_count": warmup_count,
            "order": list(order),
            "arms": measured,
        }
        write_record(stream, warmup)
        for arm_name in order:
            require_success(arm_name, measured[arm_name])

    samples: list[dict[str, Any]] = []
    for sample_number in range(1, sample_count + 1):
        pair_index = warmup_count + sample_number
        order, measured = measure_pair(pair_index)
        sample = {
            "record": "sample",
            "nfr": nfr,
            "sample": sample_number,
            "order": list(order),
            "arms": measured,
        }
        write_record(stream, sample)
        samples.append(sample)
        for arm_name in order:
            require_success(arm_name, measured[arm_name])

    summary = summary_for(nfr, samples, "target", "control")
    summary["warmup_count"] = warmup_count
    write_record(stream, summary)
    return summary


def main() -> int:
    args = parse_args()
    binary = args.binary.expanduser().resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise SystemExit(f"--binary must be an executable file: {binary}")
    input_path = args.input.expanduser().resolve() if args.input is not None else None
    if input_path is not None and not input_path.is_file():
        raise SystemExit(f"--input must be a file: {input_path}")
    if args.nfr in ("03", "all") and not Path("/usr/bin/true").is_file():
        raise SystemExit("NFR-03 requires /usr/bin/true")

    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    nfrs = ("01", "02", "03") if args.nfr == "all" else (args.nfr,)
    summaries = []
    try:
        stream = output.open("x", encoding="utf-8")
    except OSError as exc:
        print(f"cannot create output {output}: {exc}", file=sys.stderr)
        return 1

    try:
        with stream:
            write_record(
                stream,
                {
                    "record": "run",
                    "nfrs": list(nfrs),
                    "binary": str(binary),
                    "input": str(input_path) if input_path is not None else None,
                    "samples_per_nfr": args.samples,
                    "warmup_count_per_nfr": args.warmups,
                },
            )
            for nfr in nfrs:
                summaries.append(
                    run_group(
                        nfr,
                        binary,
                        input_path,
                        args.samples,
                        args.warmups,
                        args.timeout,
                        stream,
                    )
                )
    except Exception as exc:
        try:
            with output.open("a", encoding="utf-8") as stream:
                write_record(
                    stream,
                    {"record": "error", "error_type": type(exc).__name__, "error": str(exc)},
                )
        except OSError:
            pass
        print(f"measurement failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    print(json.dumps({"output": str(output), "summaries": summaries}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
