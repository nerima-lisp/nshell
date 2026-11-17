#!/usr/bin/env python3
"""Run NFR-03 and write a normalized CI report."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

from nfr_thresholds import NFR_THRESHOLDS
from nfr_selection import NFR_IDS, parse_nfr_selection


ROOT = Path(__file__).resolve().parents[1]
NFR03_SAMPLES = 6
NFR03_WARMUPS = 3
RESULT_IDS = ("03",)


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        raise ValueError(f"measurement output is missing: {path.name}")
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or any(not line.strip() for line in lines):
        raise ValueError(f"measurement output is empty or has blank lines: {path.name}")
    records = [json.loads(line) for line in lines]
    if any(not isinstance(record, dict) for record in records):
        raise ValueError(f"measurement output contains a non-object record: {path.name}")
    return records


def run_command(label: str, command: list[str], log_path: Path) -> tuple[int | None, str | None]:
    print(f"Starting {label}", flush=True)
    try:
        with log_path.open("w", encoding="utf-8") as log:
            log.write(f"$ {shlex.join(command)}\n")
            result = subprocess.run(
                command,
                cwd=ROOT,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=False,
            )
    except OSError as error:
        print(f"Failed to start {label}: {error}", flush=True)
        return None, str(error)
    print(f"Finished {label} with exit status {result.returncode}", flush=True)
    return result.returncode, None


def make_result(
    nfr: str,
    *,
    metric: str,
    value: float,
    sample_count: int,
    details: dict[str, Any],
) -> dict[str, Any]:
    threshold = float(NFR_THRESHOLDS[nfr]["limit"])
    if not math.isfinite(value):
        raise ValueError(f"NFR-{nfr} produced a non-finite value")
    return {
        "record": "result",
        "schema_version": 1,
        "nfr": f"NFR-{nfr}",
        "metric": metric,
        "value": value,
        "unit": NFR_THRESHOLDS[nfr]["unit"],
        "threshold": threshold,
        "statistic": NFR_THRESHOLDS[nfr]["statistic"],
        "sample_count": sample_count,
        "status": "PASS" if value <= threshold else "FAIL",
        "details": details,
    }


def result_from_03(summary: dict[str, Any]) -> dict[str, Any]:
    threshold = float(NFR_THRESHOLDS["03"]["limit"])
    if float(summary["criterion_threshold_ms"]) != threshold:
        raise ValueError("NFR-03 measurement threshold does not match the CI threshold")
    if int(summary["sample_count"]) != NFR03_SAMPLES:
        raise ValueError("NFR-03 did not produce the configured sample count")
    return make_result(
        "03",
        metric="1,000 external commands median",
        value=float(summary["target_median_ms"]),
        sample_count=int(summary["sample_count"]),
        details={
            "target_median_ms": summary["target_median_ms"],
            "control_median_ms": summary["control_median_ms"],
            "source_record": summary["record"],
        },
    )


def error_result(nfr: str, message: str) -> dict[str, Any]:
    return {
        "record": "result",
        "schema_version": 1,
        "nfr": f"NFR-{nfr}",
        "metric": "measurement unavailable",
        "value": None,
        "unit": NFR_THRESHOLDS[nfr]["unit"],
        "threshold": NFR_THRESHOLDS[nfr]["limit"],
        "statistic": NFR_THRESHOLDS[nfr]["statistic"],
        "sample_count": 0,
        "status": "ERROR",
        "error": message,
    }


def display_number(value: float) -> str:
    return repr(float(value))


def build_summary(
    results: list[dict[str, Any]],
    system: str,
    revision: str,
    selected_nfrs: tuple[str, ...],
    *,
    full_selection: bool,
) -> str:
    rows = {result["nfr"]: result for result in results}
    lines = [
        "# NFR-03, NFR-08 and NFR-09 performance results"
        if full_selection
        else "# Selected NFR performance results",
        "",
        f"System: `{system}`  ",
        f"Revision: `{revision}`",
    ]
    if not full_selection:
        selected = ", ".join(f"NFR-{number}" for number in selected_nfrs)
        unmeasured = [number for number in NFR_IDS if number not in selected_nfrs]
        not_measured = ", ".join(f"NFR-{number}" for number in unmeasured) or "none"
        lines.extend(
            [
                "",
                f"Selected NFRs: {selected}.",
                f"Unselected NFRs were not measured: {not_measured}.",
            ]
        )
    lines.extend(["", "| NFR | Measurement | Threshold | Result |", "|---|---:|---:|---|"])
    for number in selected_nfrs:
        if number not in RESULT_IDS:
            continue
        result = rows[f"NFR-{number}"]
        if result["status"] == "ERROR":
            value = "not measured"
        else:
            value = f"{display_number(result['value'])} {result['unit']}"
        threshold = f"≤ {display_number(result['threshold'])} {result['unit']}"
        status = result["status"]
        if status == "ERROR":
            status += f": {result['error']}"
        lines.append(f"| {result['nfr']} | {value} | {threshold} | **{status}** |")
    return "\n".join(lines) + "\n"


def write_outputs(
    output_dir: Path,
    results: list[dict[str, Any]],
    system: str,
    revision: str | None,
    selected_nfrs: tuple[str, ...],
    *,
    full_selection: bool,
) -> bool:
    metadata = {
        "record": "metadata",
        "schema_version": 1,
        "system": system,
        "platform": platform.platform(),
        "machine": platform.machine(),
        "revision": revision,
        "samples": {"nfr03": NFR03_SAMPLES},
    }
    result_path = output_dir / "results.jsonl"
    result_path.write_text(
        "".join(json.dumps(record, sort_keys=True) + "\n" for record in (metadata, *results)),
        encoding="utf-8",
    )
    summary = build_summary(
        results,
        system,
        revision or "unknown",
        selected_nfrs,
        full_selection=full_selection,
    )
    summary_path = output_dir / "summary.md"
    summary_path.write_text(summary, encoding="utf-8")
    return all(result["status"] == "PASS" for result in results)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path, help="built nshell executable")
    parser.add_argument("--output-dir", required=True, type=Path, help="new directory for raw measurements and report")
    parser.add_argument("--system", default=os.environ.get("NFR_SYSTEM", platform.system()))
    parser.add_argument("--revision", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--nfrs", default="all", help="all or comma-separated NFR IDs from 03, 08, 09")
    args = parser.parse_args()
    try:
        selected = parse_nfr_selection(args.nfrs)
    except ValueError as error:
        parser.error(f"--nfrs: {error}")
    if not set(selected).intersection(RESULT_IDS):
        parser.error("--nfrs must include NFR 03 for this measurement runner")
    return args


def main() -> int:
    args = parse_args()
    binary = args.binary.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise SystemExit(f"--binary is not an executable file: {binary}")
    if output_dir == ROOT or ROOT in output_dir.parents:
        raise SystemExit("--output-dir must be outside the repository")
    if output_dir.exists():
        raise SystemExit("--output-dir must not already exist")
    output_dir.mkdir(parents=True)
    logs_dir = output_dir / "logs"
    logs_dir.mkdir()
    try:
        selected_nfrs = parse_nfr_selection(args.nfrs)
    except ValueError as error:
        raise SystemExit(f"--nfrs: {error}") from error
    full_selection = args.nfrs.strip() == "all"

    input_path = output_dir / "nfr03-input.sexp"
    input_path.write_text("(dotimes (i 1000) (^true))\n", encoding="utf-8")
    raw_path = output_dir / "nfr-03.jsonl"
    command = [
        sys.executable,
        str(ROOT / "scripts/measure-nfr-01-03.py"),
        "--nfr",
        "03",
        "--binary",
        str(binary),
        "--samples",
        str(NFR03_SAMPLES),
        "--warmups",
        str(NFR03_WARMUPS),
        "--output",
        str(raw_path),
        "--input",
        str(input_path),
    ]
    code, error = run_command("NFR-03", command, logs_dir / "nfr-03.log")
    try:
        if error:
            raise ValueError(error)
        if code != 0:
            raise ValueError(f"measurement command exited with status {code}")
        summaries = [row for row in read_jsonl(raw_path) if row.get("record") == "summary"]
        if len(summaries) != 1 or summaries[0].get("nfr") != "03":
            raise ValueError("measurement output did not contain exactly one expected summary")
        result = result_from_03(summaries[0])
    except (OSError, ValueError, KeyError, TypeError) as exc:
        result = error_result("03", str(exc))

    passed = write_outputs(
        output_dir,
        [result],
        args.system,
        args.revision,
        selected_nfrs,
        full_selection=full_selection,
    )
    print(f"Results: {output_dir / 'results.jsonl'}", flush=True)
    print(f"Summary: {output_dir / 'summary.md'}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
