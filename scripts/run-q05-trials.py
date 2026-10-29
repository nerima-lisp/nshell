#!/usr/bin/env python3
"""Run the Q05 NFS PTY checks once at baseline and ten times with netem delay."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
CASES = {
    "prompt": ("Q05-nfs-git-prompt", "/mnt/q05/git"),
    "completion": ("Q05-nfs-filesystem-completion", "/mnt/q05/git"),
    "glob": ("Q05-nfs-glob-expansion", "/mnt/q05/git"),
}
SUMMARY = re.compile(
    r"SCENARIO_SUMMARY selected=1 runs=1 pass=1 xfail=0 xpass=0 fail=0"
)
NETEM_DELAY = re.compile(r"(?m)^qdisc\s+netem\b[^\n]*\bdelay\s+500ms(?:\s|$)")
BASELINE_TRIALS = 1
DELAYED_TRIALS = 10


def _atomic_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _run(command: list[str], *, timeout: float = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )


def _trial(
    phase: str,
    name: str,
    number: int,
    scenario_id: str,
    scenario_cwd: str,
    binary: Path,
    scenario_dir: Path,
    log_dir: Path,
) -> dict[str, Any]:
    command = [
        sys.executable,
        str(ROOT / "scripts" / "run-scenarios.py"),
        "--binary",
        str(binary),
        "--scenario-dir",
        str(scenario_dir),
        "--mode",
        "pty",
        "--scenario-id",
        scenario_id,
        "--scenario-cwd",
        f"{scenario_id}={scenario_cwd}",
    ]
    started = time.monotonic()
    try:
        completed = _run(command, timeout=65)
        output = completed.stdout
        exit_code = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired as error:
        output_value = error.stdout or ""
        output = output_value.decode("utf-8", errors="replace") if isinstance(output_value, bytes) else output_value
        exit_code = 124
        timed_out = True
    elapsed = time.monotonic() - started
    log_path = log_dir / f"{phase}-{name}-trial-{number:02d}.log"
    log_path.write_text(output, encoding="utf-8")
    passed = (
        not timed_out
        and exit_code == 0
        and elapsed <= 60
        and SUMMARY.search(output) is not None
    )
    result = {
        "phase": phase,
        "check": name,
        "trial": number,
        "scenario_id": scenario_id,
        "duration_seconds": round(elapsed, 3),
        "cutoff_seconds": 60,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "passed": passed,
        "log": str(log_path.relative_to(log_dir.parent)),
    }
    if elapsed > 60:
        result["error"] = "trial exceeded the 60-second cutoff"
    elif timed_out:
        result["error"] = "scenario runner exceeded its 65-second safety timeout"
    elif exit_code != 0 or SUMMARY.search(output) is None:
        result["error"] = "scenario runner did not report one passing scenario"
    print(
        f"Q05_TRIAL phase={phase} check={name} trial={number} "
        f"duration_seconds={result['duration_seconds']:.3f} exit={exit_code} "
        f"passed={str(passed).lower()} log={result['log']}",
        flush=True,
    )
    return result


def _route(interface: str) -> str:
    result = _run(["ip", "route", "get", "192.168.56.10"])
    if result.returncode != 0:
        raise RuntimeError(f"cannot inspect NFS route: {result.stdout.strip()}")
    tokens = result.stdout.split()
    if "dev" not in tokens or tokens[tokens.index("dev") + 1] != interface:
        raise RuntimeError(
            f"NFS route did not use client test interface {interface!r}: {result.stdout.strip()}"
        )
    return result.stdout.strip()


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--scenario-dir", type=Path, required=True)
    parser.add_argument("--server-interface", required=True)
    parser.add_argument("--interface", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--candidate-revision", required=True)
    arguments = parser.parse_args()

    binary = arguments.binary.resolve(strict=True)
    scenario_dir = arguments.scenario_dir.resolve(strict=True)
    output_dir = arguments.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    log_dir = output_dir / "trials"
    log_dir.mkdir(exist_ok=True)
    result_path = output_dir / "results.json"
    record: dict[str, Any] = {
        "candidate_revision": arguments.candidate_revision,
        "server_test_interface": arguments.server_interface,
        "client_test_interface": arguments.interface,
        "nfs_route": _route(arguments.interface),
        "delay": "500ms",
        "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "cutoff_seconds": 60,
        "trials": [],
        "setup_errors": [],
        "cleanup_errors": [],
    }
    _atomic_json(result_path, record)

    for name, (scenario_id, scenario_cwd) in CASES.items():
        for number in range(1, BASELINE_TRIALS + 1):
            result = _trial(
                "baseline", name, number, scenario_id, scenario_cwd,
                binary, scenario_dir, log_dir,
            )
            record["trials"].append(result)
            _atomic_json(result_path, record)

    qdisc_applied = False
    try:
        applied = _run([
            "sudo", "tc", "qdisc", "replace", "dev", arguments.interface,
            "root", "netem", "delay", "500ms",
        ])
        if applied.returncode != 0:
            record["setup_errors"].append(f"could not apply netem: {applied.stdout.strip()}")
        else:
            qdisc_applied = True
            observed = _run(["sudo", "tc", "qdisc", "show", "dev", arguments.interface])
            if observed.returncode != 0 or NETEM_DELAY.search(observed.stdout) is None:
                record["setup_errors"].append(
                    f"500ms netem was not observed on {arguments.interface}: {observed.stdout.strip()}"
                )
        _atomic_json(result_path, record)

        if not record["setup_errors"]:
            for name, (scenario_id, scenario_cwd) in CASES.items():
                for number in range(1, DELAYED_TRIALS + 1):
                    result = _trial(
                        "delayed", name, number, scenario_id, scenario_cwd,
                        binary, scenario_dir, log_dir,
                    )
                    record["trials"].append(result)
                    _atomic_json(result_path, record)
    finally:
        if qdisc_applied:
            removed = _run(["sudo", "tc", "qdisc", "del", "dev", arguments.interface, "root"])
            if removed.returncode != 0:
                record["cleanup_errors"].append(f"could not remove netem: {removed.stdout.strip()}")
        if Path("/mnt/q05").is_mount():
            checked = _run(["ls", "/mnt/q05"])
            if checked.returncode != 0:
                record["cleanup_errors"].append(
                    f"NFS mount did not respond after trials: {checked.stdout.strip()}"
                )
            unmounted = _run(["sudo", "umount", "/mnt/q05"])
            if unmounted.returncode != 0:
                record["cleanup_errors"].append(
                    f"could not unmount /mnt/q05: {unmounted.stdout.strip()}"
                )

    record["finished_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    record["passed_trials"] = sum(trial["passed"] for trial in record["trials"])
    record["failed_trials"] = len(record["trials"]) - record["passed_trials"]
    record["status"] = (
        "pass"
        if len(record["trials"]) == len(CASES) * (BASELINE_TRIALS + DELAYED_TRIALS)
        and record["failed_trials"] == 0
        and not record["setup_errors"]
        and not record["cleanup_errors"]
        else "fail"
    )
    _atomic_json(result_path, record)
    print(
        f"Q05_SUMMARY status={record['status']} trials={len(record['trials'])} "
        f"pass={record['passed_trials']} fail={record['failed_trials']}"
    )
    return 0 if record["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(_main())
