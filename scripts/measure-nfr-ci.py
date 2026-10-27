#!/usr/bin/env python3
"""Run NFR-01 through NFR-07 and write a normalized CI report."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import shlex
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from nfr_thresholds import NFR_THRESHOLDS


ROOT = Path(__file__).resolve().parents[1]
NFR01_02_SAMPLES = 30
NFR03_SAMPLES = 6
NFR01_03_WARMUPS = 3
NFR04_06_SAMPLES = 100
NFR04_06_WARMUPS = 2
NFR07_SAMPLES = 5
NFR07_INTERVAL_SECONDS = 1.0
RESULT_IDS = ("01", "02", "03", "04", "05", "06", "07")


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


def result_from_01_03(nfr: str, summary: dict[str, Any]) -> dict[str, Any]:
    threshold = float(NFR_THRESHOLDS[nfr]["limit"])
    if float(summary["criterion_threshold_ms"]) != threshold:
        raise ValueError(f"NFR-{nfr} measurement threshold does not match the CI threshold")
    expected_samples = NFR03_SAMPLES if nfr == "03" else NFR01_02_SAMPLES
    if int(summary["sample_count"]) != expected_samples:
        raise ValueError(f"NFR-{nfr} did not produce the configured sample count")
    metric_by_nfr = {
        "01": ("startup to first prompt median", "target_median_ms"),
        "02": ("absolute difference between shell medians", "absolute_difference_of_medians_ms"),
        "03": ("1,000 external commands median", "target_median_ms"),
    }
    metric, value_key = metric_by_nfr[nfr]
    return make_result(
        nfr,
        metric=metric,
        value=float(summary[value_key]),
        sample_count=int(summary["sample_count"]),
        details={
            "target_median_ms": summary["target_median_ms"],
            "control_median_ms": summary["control_median_ms"],
            "source_record": summary["record"],
        },
    )


def result_from_04_06(nfr: str, summary: dict[str, Any]) -> dict[str, Any]:
    threshold = float(NFR_THRESHOLDS[nfr]["limit"])
    if float(summary["threshold_ms"]) != threshold:
        raise ValueError(f"NFR-{nfr} measurement threshold does not match the CI threshold")
    if summary["acceptance_statistic"] != NFR_THRESHOLDS[nfr]["statistic"]:
        raise ValueError(f"NFR-{nfr} measurement statistic does not match the requirement")
    if int(summary["measured_samples"]) != NFR04_06_SAMPLES:
        raise ValueError(f"NFR-{nfr} did not produce the configured sample count")
    target = summary["target"]
    statistic = str(summary["acceptance_statistic"])
    value = float(target["p99_ms"] if statistic == "p99" else target["median_ms"])
    if bool(summary.get("target_threshold_met")) != (value <= threshold):
        raise ValueError(f"NFR-{nfr} measurement summary disagrees with its threshold comparison")
    details = {
        "target": target,
        "context": summary.get("context"),
        "git_prompt_enabled": summary.get("git_prompt_enabled"),
    }
    if "same_process_repeat" in summary:
        details["same_process_repeat"] = summary["same_process_repeat"]
    if "control" in summary:
        details["control"] = summary["control"]
    return make_result(
        nfr,
        metric={
            "04": "blank Enter to next prompt median, worst of Git and non-Git contexts",
            "05": "1,000-character keypress-to-prompt-and-buffer-redraw p99",
            "06": "20,000-entry interactive completion median, Enter-to-results-and-prompt",
        }[nfr],
        value=value,
        sample_count=int(summary["measured_samples"]),
        details=details,
    )


def nfr06_phase_timing_from_jsonl(path: Path) -> dict[str, Any]:
    records = read_jsonl(path)
    metadata_rows = [row for row in records if row.get("record") == "metadata"]
    summaries = [
        row for row in records
        if row.get("record") == "group-summary" and row.get("metric") == "NFR-06"
    ]
    if len(metadata_rows) != 1 or len(summaries) != 1:
        raise ValueError("NFR-06 phase output must contain one metadata row and one completion summary")
    protocol = metadata_rows[0].get("nfr06_candidate_compute_diagnostics")
    required_boundaries = (
        "candidate_compute_boundary",
        "candidate_output_preparation_boundary",
        "candidate_output_to_prompt_boundary",
    )
    if not isinstance(protocol, dict) or any(
        not isinstance(protocol.get(boundary), str) for boundary in required_boundaries
    ):
        raise ValueError("NFR-06 phase output is missing its diagnostic protocol metadata")
    summary = summaries[0]
    if int(summary.get("measured_samples", -1)) != NFR04_06_SAMPLES:
        raise ValueError("NFR-06 phase output did not produce the configured first-completion samples")
    repeats = summary.get("same_process_repeat")
    if (
        not isinstance(repeats, dict)
        or int(repeats.get("repeats_per_process", -1)) != 3
        or int(repeats.get("measured_samples", -1)) != NFR04_06_SAMPLES * 3
    ):
        raise ValueError("NFR-06 phase output did not produce the configured same-process repeats")
    timing = summary.get("candidate_compute_phase_timing")
    if not isinstance(timing, dict):
        raise ValueError("NFR-06 phase output has no candidate-compute timing")
    first = timing.get("first_completion")
    repeated = timing.get("same_process_repeats")
    if not isinstance(first, dict) or not isinstance(repeated, dict):
        raise ValueError("NFR-06 phase output is missing first or repeat timing")
    if (
        int(first.get("measured_samples", -1)) != NFR04_06_SAMPLES
        or int(repeated.get("measured_samples", -1)) != NFR04_06_SAMPLES * 3
    ):
        raise ValueError("NFR-06 phase timing sample counts do not match the configured samples")
    for phase in (first, repeated):
        for key in (
            "candidate_compute",
            "candidate_output_preparation",
            "candidate_output_to_prompt",
        ):
            values = phase.get(key)
            if not isinstance(values, dict) or not math.isfinite(float(values.get("median_ms", math.nan))):
                raise ValueError(f"NFR-06 phase output is missing a finite {key} median")
    return {
        "source": path.name,
        "measurement_samples": NFR04_06_SAMPLES,
        "repeats_per_process": 3,
        "first_completion": first,
        "same_process_repeats": repeated,
        "protocol": protocol,
    }


def result_from_07(report_path: Path) -> dict[str, Any]:
    if not report_path.is_file():
        raise ValueError("NFR-07 measurement report is missing")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    report_status = report.get("status")
    if report_status not in {"success", "fail"}:
        raise ValueError(f"NFR-07 source report is not a valid completed measurement: {report_status!r}")
    operations = report.get("operations")
    if not isinstance(operations, list):
        raise ValueError("NFR-07 report has no operations list")
    target = next((row for row in operations if row.get("name") == "nfr07_nshell_idle_rss"), None)
    control = next((row for row in operations if row.get("name") == "nfr07_bin_sh_control_idle_rss"), None)
    if target is None or control is None:
        raise ValueError("NFR-07 target or /bin/sh control measurement is missing")
    if target.get("status") not in {"success", "fail"} or control.get("status") != "success":
        raise ValueError("NFR-07 target or /bin/sh control measurement failed")
    if target.get("limit_applies") is not True or control.get("limit_applies") is not False:
        raise ValueError("NFR-07 threshold must apply only to the nshell target")
    rss_kib = target.get("rss_kib_samples")
    if not isinstance(rss_kib, list) or len(rss_kib) != NFR07_SAMPLES:
        raise ValueError("NFR-07 did not produce the configured RSS sample count")
    control_samples = control.get("rss_kib_samples")
    if not isinstance(control_samples, list) or len(control_samples) != NFR07_SAMPLES:
        raise ValueError("NFR-07 /bin/sh control did not produce the configured RSS sample count")
    median_kib = float(statistics.median(rss_kib))
    value_mb = median_kib * 1024 / 1_000_000
    threshold_mib = float(NFR_THRESHOLDS["07"]["limit"]) * 1_000_000 / (1024 * 1024)
    if float(target["target_mib"]) != threshold_mib:
        raise ValueError("NFR-07 measurement threshold does not match the CI threshold")
    expected_status = "success" if target["limit_met"] else "fail"
    if target["status"] != expected_status or bool(target["target_passed"]) != bool(target["limit_met"]):
        raise ValueError("NFR-07 target status disagrees with its threshold comparison")
    if bool(target["limit_met"]) != (value_mb <= float(NFR_THRESHOLDS["07"]["limit"])):
        raise ValueError("NFR-07 measurement summary disagrees with the MB threshold comparison")
    result = make_result(
        "07",
        metric="idle resident memory median",
        value=value_mb,
        sample_count=len(rss_kib),
        details={
            "value_mib": median_kib / 1024,
            "maximum_mib": target["rss_mib_max"],
            "rss_kib_samples": rss_kib,
            "control_median_mib": control.get("rss_mib_median"),
            "control_limit_met": control.get("limit_met"),
            "source_report_status": report_status,
            "page_size_bytes": report.get("host", {}).get("page_size_bytes"),
        },
    )
    return result


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
    diagnostic: dict[str, Any] | None,
    system: str,
    revision: str,
) -> str:
    rows = {result["nfr"]: result for result in results}
    lines = [
        "# NFR-01 to NFR-07 performance results",
        "",
        f"System: `{system}`  ",
        f"Revision: `{revision}`",
        "",
        "| NFR | Measurement | Threshold | Result |",
        "|---|---:|---:|---|",
    ]
    for number in RESULT_IDS:
        result = rows[f"NFR-{number}"]
        if result["status"] == "ERROR":
            value = "not measured"
        elif number == "04":
            cases = result["details"]["cases"]
            value = f"Git off {display_number(cases['git_off_ms'])} ms; Git on {display_number(cases['git_on_ms'])} ms"
        else:
            value = f"{display_number(result['value'])} {result['unit']}"
        threshold = f"≤ {display_number(result['threshold'])} {result['unit']}"
        status = result["status"]
        if status == "ERROR":
            status += f": {result['error']}"
        lines.append(f"| {result['nfr']} | {value} | {threshold} | **{status}** |")
    nfr06_details = rows["NFR-06"].get("details", {})
    repeat = nfr06_details.get("same_process_repeat")
    if repeat is not None:
        lines.extend(
            [
                "",
                "NFR-06 first-completion median per new nshell process: "
                f"{display_number(rows['NFR-06']['value'])} ms "
                f"({rows['NFR-06']['sample_count']} samples).",
                "NFR-06 same-process completions after the first: "
                f"{display_number(repeat['median_ms'])} ms median across "
                f"{repeat['measured_samples']} repeats "
                f"({repeat['repeats_per_process']} per process).",
            ]
        )
    phase_timing = nfr06_details.get("candidate_compute_phase_timing")
    if phase_timing is not None:
        first = phase_timing["first_completion"]
        repeated = phase_timing["same_process_repeats"]
        lines.extend(
            [
                "",
                "NFR-06 phase timing (separately instrumented diagnostic run):",
                f"first completion, candidate calculation median {display_number(first['candidate_compute']['median_ms'])} ms; "
                f"candidate text preparation median {display_number(first['candidate_output_preparation']['median_ms'])} ms; "
                f"visible candidate output through prompt restoration median {display_number(first['candidate_output_to_prompt']['median_ms'])} ms "
                f"({first['measured_samples']} samples).",
                f"same-process repeats, candidate calculation median {display_number(repeated['candidate_compute']['median_ms'])} ms; "
                f"candidate text preparation median {display_number(repeated['candidate_output_preparation']['median_ms'])} ms; "
                f"visible candidate output through prompt restoration median {display_number(repeated['candidate_output_to_prompt']['median_ms'])} ms "
                f"({repeated['measured_samples']} repeats).",
                "Candidate calculation and text preparation use SBCL internal time. Visible output timing uses the driver's monotonic clock from the first expected candidate row observed in PTY output to the fully restored prompt; it excludes pre-output dispatch and candidate computation and includes PTY output and prompt restoration. "
                "This diagnostic runs separately from the NFR-06 gate and its phases are not additive to the Enter-to-prompt latency.",
            ]
        )
    elif "phase_timing_error" in rows["NFR-06"]:
        lines.extend(["", f"NFR-06 phase timing diagnostic failed: {rows['NFR-06']['phase_timing_error']}"])
    if diagnostic is not None:
        lines.extend(
            [
                "",
                "NFR-06 suggestion-key response (diagnostic, no separate numeric requirement): "
                f"target p99 {display_number(diagnostic['target_p99_ms'])} ms; "
                f"plain-fixture p99 {display_number(diagnostic['plain_fixture_p99_ms'])} ms; "
                f"paired p99 delta {display_number(diagnostic['paired_sequence_p99_delta_p99_ms'])} ms.",
            ]
        )
    return "\n".join(lines) + "\n"


def write_outputs(
    output_dir: Path,
    results: list[dict[str, Any]],
    diagnostic: dict[str, Any] | None,
    system: str,
    revision: str | None,
) -> bool:
    metadata = {
        "record": "metadata",
        "schema_version": 1,
        "system": system,
        "platform": platform.platform(),
        "machine": platform.machine(),
        "revision": revision,
        "samples": {
            "nfr01": NFR01_02_SAMPLES,
            "nfr02": NFR01_02_SAMPLES,
            "nfr03": NFR03_SAMPLES,
            "nfr04_nfr05_nfr06": NFR04_06_SAMPLES,
            "nfr07_rss": NFR07_SAMPLES,
        },
    }
    result_path = output_dir / "results.jsonl"
    records = [metadata, *results]
    if diagnostic is not None:
        records.append({"record": "diagnostic", "schema_version": 1, **diagnostic})
    result_path.write_text(
        "".join(json.dumps(record, sort_keys=True) + "\n" for record in records),
        encoding="utf-8",
    )
    summary = build_summary(results, diagnostic, system, revision or "unknown")
    summary_path = output_dir / "summary.md"
    summary_path.write_text(summary, encoding="utf-8")
    return all(
        result["status"] == "PASS" and result.get("phase_timing_status", "PASS") == "PASS"
        for result in results
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path, help="built nshell executable")
    parser.add_argument("--output-dir", required=True, type=Path, help="new directory for raw measurements and report")
    parser.add_argument("--system", default=os.environ.get("NFR_SYSTEM", platform.system()))
    parser.add_argument("--revision", default=os.environ.get("GITHUB_SHA"))
    return parser.parse_args()


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
    errors: dict[str, str] = {}
    results: dict[str, dict[str, Any]] = {}
    diagnostic = None
    py = sys.executable
    script_01_03 = str(ROOT / "scripts/measure-nfr-01-03.py")
    input_path = output_dir / "nfr03-input.sh"
    target_iterations = " ".join(str(index) for index in range(1, 1_001))
    input_path.write_text(
        f"for i in {target_iterations}; /usr/bin/true; end\n",
        encoding="utf-8",
    )

    for nfr, samples in (("01", NFR01_02_SAMPLES), ("02", NFR01_02_SAMPLES), ("03", NFR03_SAMPLES)):
        raw_path = output_dir / f"nfr-{nfr}.jsonl"
        command = [
            py,
            script_01_03,
            "--nfr",
            nfr,
            "--binary",
            str(binary),
            "--samples",
            str(samples),
            "--warmups",
            str(NFR01_03_WARMUPS),
            "--output",
            str(raw_path),
        ]
        if nfr == "03":
            command.extend(("--input", str(input_path)))
        code, error = run_command(f"NFR-{nfr}", command, logs_dir / f"nfr-{nfr}.log")
        try:
            if error:
                raise ValueError(error)
            if code != 0:
                raise ValueError(f"measurement command exited with status {code}")
            summaries = [row for row in read_jsonl(raw_path) if row.get("record") == "summary"]
            if len(summaries) != 1 or summaries[0].get("nfr") != nfr:
                raise ValueError("measurement output did not contain exactly one expected summary")
            results[nfr] = result_from_01_03(nfr, summaries[0])
        except (OSError, ValueError, KeyError, TypeError) as exc:
            errors[nfr] = str(exc)

    try:
        with tempfile.TemporaryDirectory(prefix="nshell-nfr-plain-") as plain_dir, tempfile.TemporaryDirectory(
            prefix="nshell-nfr-completion-"
        ) as completion_dir, tempfile.TemporaryDirectory(prefix="nshell-nfr-git-") as git_dir:
            subprocess.run(["git", "init", "--quiet", git_dir], check=True)
            completion_fixture = Path(completion_dir)
            for index in range(20_000):
                (completion_fixture / f"item-{index:05d}").touch()
            raw_path = output_dir / "nfr-04-06.jsonl"
            command = [
                py,
                str(ROOT / "scripts/measure-nfr-04-06.py"),
                "--binary",
                str(binary),
                "--from",
                "nfr04",
                "--samples",
                str(NFR04_06_SAMPLES),
                "--warmups",
                str(NFR04_06_WARMUPS),
                "--plain-fixture",
                plain_dir,
                "--git-fixture",
                git_dir,
                "--completion-fixture",
                str(completion_fixture),
                "--output",
                str(raw_path),
            ]
            code, error = run_command("NFR-04 through NFR-06", command, logs_dir / "nfr-04-06.log")
            if error:
                raise ValueError(error)
            if code != 0:
                raise ValueError(f"measurement command exited with status {code}")
            records = read_jsonl(raw_path)
            summaries = [row for row in records if row.get("record") == "group-summary"]
            summaries_04 = [row for row in summaries if row.get("metric") == "NFR-04"]
            if len(summaries_04) != 2:
                raise ValueError("NFR-04 output must contain Git-on and Git-off summaries")
            cases = {}
            for row in summaries_04:
                case = "git_on_ms" if row.get("git_prompt_enabled") is True else "git_off_ms"
                if case in cases:
                    raise ValueError(f"NFR-04 output has duplicate {case} summary")
                result = result_from_04_06("04", row)
                cases[case] = float(result["value"])
            if set(cases) != {"git_on_ms", "git_off_ms"}:
                raise ValueError("NFR-04 output is missing a Git-on or Git-off summary")
            results["04"] = make_result(
                "04",
                metric="blank Enter to next prompt median, Git-on and Git-off",
                value=max(cases.values()),
                sample_count=NFR04_06_SAMPLES,
                details={"cases": cases},
            )
            for nfr in ("05", "06"):
                candidates = [row for row in summaries if row.get("metric") == f"NFR-{nfr}"]
                if len(candidates) != 1:
                    raise ValueError(f"NFR-{nfr} output must contain exactly one criterion summary")
                results[nfr] = result_from_04_06(nfr, candidates[0])
            key_rows = [
                row
                for row in summaries
                if str(row.get("metric", "")).startswith("NFR-06") and row.get("metric") != "NFR-06"
            ]
            if len(key_rows) != 1:
                raise ValueError("NFR-06 output must contain exactly one suggestion-key diagnostic")
            diagnostic = {
                "nfr": "NFR-06 suggestion-key responsiveness",
                "target_p99_ms": float(key_rows[0]["target"]["p99_ms"]),
                "plain_fixture_p99_ms": float(key_rows[0]["plain_fixture"]["p99_ms"]),
                "paired_sequence_p99_delta_median_ms": float(
                    key_rows[0]["paired_sequence_p99_delta_median_ms"]
                ),
                "paired_sequence_p99_delta_p99_ms": float(key_rows[0]["paired_sequence_p99_delta_p99_ms"]),
                "sample_count": int(key_rows[0]["measured_sequences"]),
                "threshold": None,
                "status": "INFO",
            }
            results["06"]["details"]["suggestion_key_diagnostic"] = diagnostic
            phase_path = output_dir / "nfr-06-phase-diagnostics.jsonl"
            phase_command = [
                py,
                str(ROOT / "scripts/measure-nfr-04-06.py"),
                "--binary",
                str(binary),
                "--from",
                "nfr06",
                "--samples",
                str(NFR04_06_SAMPLES),
                "--warmups",
                str(NFR04_06_WARMUPS),
                "--plain-fixture",
                plain_dir,
                "--completion-fixture",
                str(completion_fixture),
                "--nfr06-candidate-compute-diagnostics",
                "--output",
                str(phase_path),
            ]
            try:
                code, error = run_command(
                    "NFR-06 calculation and render phase diagnostics",
                    phase_command,
                    logs_dir / "nfr-06-phase-diagnostics.log",
                )
                if error:
                    raise ValueError(error)
                if code != 0:
                    raise ValueError(f"phase diagnostic command exited with status {code}")
                results["06"]["details"]["candidate_compute_phase_timing"] = nfr06_phase_timing_from_jsonl(phase_path)
                results["06"]["phase_timing_status"] = "PASS"
            except (OSError, ValueError, KeyError, TypeError) as exc:
                results["06"]["phase_timing_error"] = str(exc)
                results["06"]["phase_timing_status"] = "ERROR"
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as exc:
        for nfr in ("04", "05", "06"):
            errors[nfr] = str(exc)

    nfr07_path = output_dir / "nfr-07.json"
    code, error = run_command(
        "NFR-07",
        [
            py,
            str(ROOT / "scripts/measure-nfr-07-09.py"),
            "--mode",
            "nfr07",
            "--binary",
            str(binary),
            "--rss-samples",
            str(NFR07_SAMPLES),
            "--rss-interval",
            str(NFR07_INTERVAL_SECONDS),
            "--output",
            str(nfr07_path),
        ],
        logs_dir / "nfr-07.log",
    )
    try:
        if error:
            raise ValueError(error)
        if code not in (0, 1):
            raise ValueError(f"measurement command exited with status {code}")
        result = result_from_07(nfr07_path)
        results["07"] = result
    except (OSError, ValueError, KeyError, TypeError) as exc:
        errors["07"] = str(exc)

    final_results = [results.get(nfr, error_result(nfr, errors.get(nfr, "no result was produced"))) for nfr in RESULT_IDS]
    passed = write_outputs(output_dir, final_results, diagnostic, args.system, args.revision)
    print(f"Results: {output_dir / 'results.jsonl'}", flush=True)
    print(f"Summary: {output_dir / 'summary.md'}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
