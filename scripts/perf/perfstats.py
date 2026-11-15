#!/usr/bin/env python3
"""Statistics and gate G3 judgement for the nshell performance harness.

Input is the raw JSON written by perfharness.py (and optional B3 JSON files).
Output is a human-readable table plus a machine-readable JSON verdict.

Subcommands:
  judge RAW [--noise NOISE] [--b3 ARM:BLOCK:PATH ...] [--b3-status TEXT]
        [--note TEXT ...] --json OUT --table OUT
  noise RAW [--b3 ...] [--b3-status TEXT] --out NOISE

Exit codes of `judge`: 0 pass, 1 fail, 3 inconclusive, 2 usage or input error.
Exit codes of `noise`: 0 every gated metric has an entry, 3 the noise file was
written without some of them, 2 usage or input error.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path
from typing import Any

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_USAGE = 2
EXIT_INCONCLUSIVE = 3

BOOTSTRAP_ITERATIONS = 2000
BOOTSTRAP_SEED = 20261115
CI_LEVEL = 0.95
# A metric whose valid sample groups on either arm fall below this share of
# the planned count is judged inconclusive instead of pass or fail.
MIN_VALID_FRACTION = 0.75

# Gate G3 thresholds. A difference regresses when the lower bound of its 95%
# bootstrap CI exceeds max(relative * baseline statistic, absolute).
GATED_RULES: dict[str, list[tuple[str, float, float]]] = {
    "startup": [("median", 0.05, 3.0)],
    "key": [("p95", 0.05, 1.0), ("p99", 0.15, 2.0)],
    "consing": [("mean", 0.10, 0.0)],
}
# Reported with a CI but never gated.
INFO_STATS: dict[str, list[str]] = {
    "startup": [],
    "key": ["median"],
    "tab": ["median", "p95"],
    "prompt": ["median", "p95"],
    "rss": ["median"],
    "consing": [],
}
# B3 counters judged by the "no new per-key file I/O or spawn" rule.
COUNT_KINDS = ("count",)


def quantile(values: list[float], q: float) -> float:
    """Linear interpolation between closest ranks (Hyndman-Fan type 7)."""
    if not values:
        raise ValueError("quantile of an empty sample")
    ordered = sorted(values)
    position = (len(ordered) - 1) * q
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return float(ordered[lower])
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def statistic(name: str, values: list[float]) -> float:
    if name == "mean":
        return sum(values) / len(values)
    if name == "median":
        return quantile(values, 0.5)
    if name.startswith("p") and name[1:].isdigit():
        return quantile(values, int(name[1:]) / 100)
    raise ValueError(f"unknown statistic: {name}")


def pooled(blocks: list[dict[str, list[list[float]]]], arm: str) -> list[float]:
    return [value for block in blocks for group in block[arm] for value in group]


def bootstrap_difference(
    blocks: list[dict[str, list[list[float]]]],
    stat: str,
    iterations: int = BOOTSTRAP_ITERATIONS,
    seed: int = BOOTSTRAP_SEED,
) -> dict[str, float]:
    """CI of stat(B) - stat(A) by a hierarchical bootstrap.

    Each block is one ABBA round: {"A": [group, ...], "B": [group, ...]}, a
    group being the values from one process (one value for a startup sample,
    all measured keys for a long-lived session). Each iteration resamples
    blocks, then groups within each block and arm, then values within each
    group, so between-round drift, between-process variance and within-process
    variance all enter the interval while the ABBA pairing is kept.
    """
    if not blocks:
        raise ValueError("bootstrap needs at least one block")
    rng = random.Random(seed)
    base = statistic(stat, pooled(blocks, "A"))
    cand = statistic(stat, pooled(blocks, "B"))
    diffs = []
    for _ in range(iterations):
        chosen = rng.choices(blocks, k=len(blocks))
        arms = {}
        for arm in ("A", "B"):
            values: list[float] = []
            for block in chosen:
                groups = block[arm]
                for group in rng.choices(groups, k=len(groups)):
                    if len(group) > 1:
                        values.extend(rng.choices(group, k=len(group)))
                    else:
                        values.extend(group)
            arms[arm] = statistic(stat, values)
        diffs.append(arms["B"] - arms["A"])
    alpha = (1 - CI_LEVEL) / 2
    return {
        "base": base,
        "cand": cand,
        "diff": cand - base,
        "ci_low": quantile(diffs, alpha),
        "ci_high": quantile(diffs, 1 - alpha),
    }


def noise_key(metric: str, stat: str) -> str:
    return f"{metric}|{stat}"


def valid_blocks(metric: dict[str, Any]) -> list[dict[str, list[list[float]]]]:
    """Blocks in which both arms produced at least one group."""
    return [block for block in metric.get("blocks", []) if block.get("A") and block.get("B")]


def unjudgeable(metric: dict[str, Any]) -> tuple[str, str] | None:
    """("n/a" or "inconclusive", reason) when the metric's samples cannot be judged.

    n/a needs a recorded reason per unsupported arm, which the harness writes
    only when a binary rejects the feature; every measurement failure leaves
    the metric short of samples and therefore inconclusive.
    """
    support = metric.get("support", {"A": True, "B": True})
    missing = [arm for arm in ("A", "B") if not support.get(arm, True)]
    # A measurement failure on either arm outweighs the other arm's n/a.
    if missing and metric.get("errors"):
        return "inconclusive", "measurement failed: " + "; ".join(str(e) for e in metric["errors"][:3])
    if missing and metric.get("guard_failures"):
        return "inconclusive", "correctness guard failed: " + "; ".join(metric["guard_failures"][:3])
    if missing:
        reasons = metric.get("unsupported", {})
        if all(reasons.get(arm) for arm in missing):
            return "n/a", "unsupported by " + "; ".join(f"arm {arm}: {reasons[arm]}" for arm in missing)
        return "inconclusive", f"arm {'+'.join(missing)} marked unsupported without a recorded reason"
    if metric.get("guard_failures"):
        return "inconclusive", "correctness guard failed: " + "; ".join(metric["guard_failures"][:3])
    planned = metric.get("planned_groups_per_arm", 0)
    blocks = valid_blocks(metric)
    counts = {arm: sum(len(block[arm]) for block in blocks) for arm in ("A", "B")}
    needed = math.ceil(planned * MIN_VALID_FRACTION) if planned else 1
    if not blocks or min(counts.values()) < needed:
        reason = f"valid groups A={counts['A']} B={counts['B']}, need >= {needed} of {planned} per arm"
        if metric.get("errors"):
            reason += "; errors: " + "; ".join(str(e) for e in metric["errors"][:3])
        return "inconclusive", reason
    return None


def judge_count_metric(metric: dict[str, Any]) -> dict[str, Any]:
    blocks = valid_blocks(metric)
    gated = metric.get("io_gate", True)
    row: dict[str, Any] = {"metric": metric["name"], "stat": "per_key", "kind": "count", "gated": gated}
    problem = unjudgeable(metric)
    if problem is not None:
        row.update(verdict="inconclusive" if gated else "info", reason=problem[1])
        return row
    base_values = pooled(blocks, "A")
    cand_values = pooled(blocks, "B")
    row.update(base=max(base_values), cand=min(cand_values))
    if not gated:
        # B3 reports io_gate=false when the counts depend on wall-clock cache TTLs.
        row.update(verdict="info", reason="io_gate=false in B3 output: counts depend on cache timing")
        return row
    # "New" I/O means every candidate run does more per key than every
    # baseline run; counts are deterministic, so run-to-run spread is noise.
    if min(cand_values) > max(base_values):
        row.update(verdict="fail", reason="candidate performs more per-key operations than baseline")
    else:
        row.update(verdict="pass", reason="no new per-key operations")
    return row


def judge_metric(metric: dict[str, Any], noise: dict[str, Any] | None) -> list[dict[str, Any]]:
    kind = metric["kind"]
    if kind in COUNT_KINDS:
        return [judge_count_metric(metric)]
    rows: list[dict[str, Any]] = []
    gated = GATED_RULES.get(kind, [])
    stats: list[tuple[str, float | None, float | None]] = list(gated)
    stats += [(name, None, None) for name in INFO_STATS.get(kind, [])]
    planned = metric.get("planned_groups_per_arm", 0)
    blocks = valid_blocks(metric)
    counts = {arm: sum(len(block[arm]) for block in blocks) for arm in ("A", "B")}
    problem = unjudgeable(metric)
    for stat, relative, absolute in stats:
        row: dict[str, Any] = {
            "metric": metric["name"],
            "stat": stat,
            "kind": kind,
            "unit": metric.get("unit", "ms"),
            "gated": relative is not None,
            "groups": counts,
            "planned_groups_per_arm": planned,
            "blocks": len(blocks),
        }
        rows.append(row)
        if problem is not None:
            row.update(verdict=problem[0], reason=problem[1])
            continue
        result = bootstrap_difference(blocks, stat)
        row.update(result)
        row["diff_rel"] = result["diff"] / result["base"] if result["base"] else None
        if relative is None:
            row.update(verdict="info")
            continue
        table_threshold = max(relative * result["base"], absolute)
        threshold = table_threshold
        source = "table"
        key = noise_key(metric["name"], stat)
        entry = (noise or {}).get("metrics", {}).get(key)
        if noise is not None and entry is None:
            # The noise floor can only raise the threshold, so without it a
            # table-threshold fail or pass is not established.
            why = noise.get("missing", {}).get(key) or noise.get("unsupported", {}).get(key)
            reason = f"noise file has no entry for {key}" + (f" (noise run: {why})" if why else "")
            row.update(verdict="inconclusive", reason=reason + "; rerun noise.sh")
            continue
        if entry is not None:
            floor = 2 * entry["noise_rel"] * result["base"]
            if floor > threshold:
                threshold = floor
                source = "2x noise"
        row.update(threshold=threshold, threshold_source=source, table_threshold=table_threshold)
        if result["ci_low"] > threshold:
            row.update(verdict="fail", reason="CI lower bound exceeds threshold")
        else:
            row.update(verdict="pass")
            row["resolved"] = result["ci_high"] <= threshold
            if not row["resolved"]:
                row["reason"] = "CI upper bound above threshold: a regression of that size is not excluded"
    return rows


def b3_metrics(b3_runs: list[tuple[str, int, Path]]) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    """Turn B3 JSON files (one per run) into metrics in the raw format."""
    errors: list[str] = []
    uptimes: list[str] = []
    per_metric: dict[str, dict[str, Any]] = {}
    for arm, block_index, path in b3_runs:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            scenarios = data["scenarios"]
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(f"{arm} block {block_index}: {path.name}: {error}")
            continue
        if data.get("uptime"):
            uptimes.append(f"{arm}#{block_index}: {data['uptime']}")
        for scenario in scenarios:
            name = scenario.get("name")
            entries = [("consing", f"b3.{name}.bytes_consed_per_key", (scenario.get("bytes_consed_per_key") or {}).get("mean"))]
            for field in ("stat_per_key", "file_io_per_key", "spawn_per_key"):
                entries.append(("count", f"b3.{name}.{field}", scenario.get(field)))
            for kind, metric_name, value in entries:
                metric = per_metric.setdefault(
                    metric_name,
                    {"name": metric_name, "kind": kind, "unit": "bytes" if kind == "consing" else "ops", "blocks": {}, "errors": []},
                )
                if kind == "count" and scenario.get("io_gate") is False:
                    metric["io_gate"] = False
                if not isinstance(value, (int, float)):
                    metric["errors"].append(f"{arm} block {block_index}: missing value")
                    continue
                block = metric["blocks"].setdefault(block_index, {"A": [], "B": []})
                block[arm].append([float(value)])
    metrics = []
    for metric in per_metric.values():
        ordered = [metric["blocks"][index] for index in sorted(metric["blocks"])]
        metric["blocks"] = ordered
        arm_runs = {arm: sum(1 for run in b3_runs if run[0] == arm) for arm in ("A", "B")}
        metric["planned_groups_per_arm"] = min(arm_runs.values())
        metrics.append(metric)
    return metrics, errors, uptimes


def parse_b3_args(values: list[str]) -> list[tuple[str, int, Path]]:
    runs = []
    for value in values:
        arm, block, path = value.split(":", 2)
        if arm not in ("A", "B"):
            raise ValueError(f"--b3 arm must be A or B: {value}")
        runs.append((arm, int(block), Path(path)))
    return runs


def run_problems(raw: dict[str, Any], b3_runs: list[tuple[str, int, Path]],
                 b3_status: str | None) -> tuple[list[dict[str, Any]], list[str], list[str], list[str]]:
    """All metrics plus the run-level reasons that rule out a pass, B3 notes and uptimes."""
    metrics = list(raw.get("metrics", []))
    problems: list[str] = []
    notes: list[str] = []
    uptimes: list[str] = []
    if b3_runs:
        b3, errors, uptimes = b3_metrics(b3_runs)
        metrics += b3
        if errors:
            problems.append("B3 errors: " + "; ".join(errors))
            notes.extend(errors)
        if not b3:
            problems.append("B3 produced no scenarios")
    if raw.get("fatal_error"):
        problems.append("harness error: " + raw["fatal_error"])
        notes.append("harness error: " + raw["fatal_error"])
    if b3_status and b3_status.startswith("error"):
        problems.append(b3_status)
    return metrics, problems, notes, uptimes


def overall_verdict(rows: list[dict[str, Any]], extra_inconclusive: list[str]) -> tuple[str, int]:
    gated = [row for row in rows if row.get("gated") and row["verdict"] != "n/a"]
    if any(row["verdict"] == "fail" for row in gated):
        return "fail", EXIT_FAIL
    if extra_inconclusive or not gated or any(row["verdict"] == "inconclusive" for row in gated):
        return "inconclusive", EXIT_INCONCLUSIVE
    return "pass", EXIT_PASS


def fmt(value: Any, unit: str = "") -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        magnitude = abs(value)
        text = f"{value:.0f}" if magnitude >= 1000 else f"{value:.2f}" if magnitude >= 1 else f"{value:.3f}"
        return text + unit
    return str(value)


def render_table(report: dict[str, Any]) -> str:
    lines = []
    lines.append(f"verdict: {report['verdict'].upper()}")
    lines.append(f"A (baseline):  {report['arms']['A']}")
    lines.append(f"B (candidate): {report['arms']['B']}")
    for label, value in report["uptime"].items():
        lines.append(f"uptime {label}: {value}")
    if report["noise_file"]:
        lines.append(f"noise file: {report['noise_file']}")
    else:
        lines.append("noise file: none (table thresholds only; WARNING: thresholds are not floored at 2x same-binary noise)")
    lines.append(f"B3: {report['b3_status']}")
    for note in report["notes"]:
        lines.append(f"note: {note}")
    header = ("metric", "stat", "A", "B", "B-A", "B-A %", "95% CI of B-A", "threshold", "n A/B", "verdict")
    table = [header]
    for row in report["rows"]:
        unit = row.get("unit", "")
        ci = "-"
        if "ci_low" in row:
            ci = f"[{fmt(row['ci_low'])}, {fmt(row['ci_high'])}]"
        threshold = "-"
        if "threshold" in row:
            threshold = f"{fmt(row['threshold'])} ({row['threshold_source']})"
        rel = row.get("diff_rel")
        verdict = row["verdict"]
        if verdict == "pass" and row.get("resolved") is False:
            verdict = "pass*"
        groups = row.get("groups")
        table.append((
            row["metric"],
            row["stat"],
            fmt(row.get("base")) + (f" {unit}" if "base" in row else ""),
            fmt(row.get("cand")),
            fmt(row.get("diff")),
            "-" if rel is None else f"{rel * 100:+.1f}%",
            ci,
            threshold,
            f"{groups['A']}/{groups['B']}" if groups else "-",
            verdict,
        ))
    widths = [max(len(str(line[i])) for line in table) for i in range(len(header))]
    for index, line in enumerate(table):
        lines.append("  ".join(str(cell).ljust(widths[i]) for i, cell in enumerate(line)).rstrip())
        if index == 0:
            lines.append("  ".join("-" * width for width in widths))
    lines.append("pass* = not a regression by the gate rule, but the CI upper bound exceeds the threshold.")
    reasons = [row for row in report["rows"] if row.get("reason") and row["verdict"] in ("fail", "inconclusive", "n/a")]
    for row in reasons:
        lines.append(f"{row['verdict']}: {row['metric']} {row['stat']}: {row['reason']}")
    for reason in report["inconclusive_reasons"]:
        lines.append(f"inconclusive: {reason}")
    return "\n".join(lines) + "\n"


def build_report(raw: dict[str, Any], noise: dict[str, Any] | None, noise_path: str | None,
                 b3_runs: list[tuple[str, int, Path]], b3_status: str | None) -> dict[str, Any]:
    metrics, extra_inconclusive, b3_notes, uptimes = run_problems(raw, b3_runs, b3_status)
    notes: list[str] = list(raw.get("notes", [])) + b3_notes
    uptime = dict(raw.get("uptime", {}))
    for index, value in enumerate(uptimes):
        uptime[f"b3 {index}"] = value
    if b3_runs:
        status = b3_status or f"measured ({len(b3_runs)} runs)"
    else:
        status = b3_status or "not measured"
    rows: list[dict[str, Any]] = []
    for metric in metrics:
        rows.extend(judge_metric(metric, noise))
    verdict, code = overall_verdict(rows, extra_inconclusive)
    return {
        "schema": "nshell-perf-verdict/1",
        "verdict": verdict,
        "exit_code": code,
        "arms": raw.get("arms", {}),
        "uptime": uptime,
        "noise_file": noise_path,
        "b3_status": status,
        "inconclusive_reasons": extra_inconclusive,
        "notes": notes,
        "config": raw.get("config", {}),
        "rows": rows,
    }


def build_noise(raw: dict[str, Any], b3_runs: list[tuple[str, int, Path]],
                b3_status: str | None = None) -> dict[str, Any]:
    metrics, problems, _, _ = run_problems(raw, b3_runs, b3_status)
    entries: dict[str, Any] = {}
    missing: dict[str, str] = {}
    unsupported: dict[str, str] = {}
    for metric in metrics:
        stats = [rule[0] for rule in GATED_RULES.get(metric["kind"], [])]
        problem = unjudgeable(metric)
        for stat in stats:
            key = noise_key(metric["name"], stat)
            if problem is not None:
                (unsupported if problem[0] == "n/a" else missing)[key] = problem[1]
                continue
            result = bootstrap_difference(valid_blocks(metric), stat)
            magnitude = max(abs(result["ci_low"]), abs(result["ci_high"]))
            if result["base"]:
                noise_rel = magnitude / result["base"]
            elif magnitude == 0:
                noise_rel = 0.0
            else:
                missing[key] = f"A statistic is 0 but the A-vs-A CI is [{result['ci_low']}, {result['ci_high']}]"
                continue
            entries[key] = {
                "noise_rel": noise_rel,
                "base": result["base"],
                "diff": result["diff"],
                "ci_low": result["ci_low"],
                "ci_high": result["ci_high"],
            }
    return {
        "schema": "nshell-perf-noise/1",
        "definition": "noise_rel = max(|CI low|, |CI high|) of the A-vs-A difference divided by the A statistic",
        "arms": raw.get("arms", {}),
        "uptime": raw.get("uptime", {}),
        "config": raw.get("config", {}),
        "complete": not (missing or problems or not entries),
        "incomplete_reasons": problems + ([] if entries else ["no gated metric was measured"]),
        "metrics": entries,
        "missing": missing,
        "unsupported": unsupported,
    }


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    judge = sub.add_parser("judge")
    judge.add_argument("raw")
    judge.add_argument("--noise")
    judge.add_argument("--b3", action="append", default=[])
    judge.add_argument("--b3-status")
    judge.add_argument("--note", action="append", default=[], help="free text recorded with the result (repeatable)")
    judge.add_argument("--json", required=True)
    judge.add_argument("--table", required=True)
    noise = sub.add_parser("noise")
    noise.add_argument("raw")
    noise.add_argument("--b3", action="append", default=[])
    noise.add_argument("--b3-status")
    noise.add_argument("--out", required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit as error:
        return EXIT_USAGE if error.code else EXIT_PASS
    try:
        raw = load_json(args.raw)
        b3_runs = parse_b3_args(args.b3)
        if args.command == "noise":
            noise_report = build_noise(raw, b3_runs, args.b3_status)
            Path(args.out).write_text(json.dumps(noise_report, indent=2) + "\n", encoding="utf-8")
            if noise_report["complete"]:
                return EXIT_PASS
            for reason in noise_report["incomplete_reasons"]:
                print(f"perfstats: noise run incomplete: {reason}", file=sys.stderr)
            for key, reason in noise_report["missing"].items():
                print(f"perfstats: noise run has no entry for {key}: {reason}", file=sys.stderr)
            return EXIT_INCONCLUSIVE
        noise_data = load_json(args.noise) if args.noise else None
    except (OSError, ValueError) as error:
        print(f"perfstats: {error}", file=sys.stderr)
        return EXIT_USAGE
    report = build_report(raw, noise_data, args.noise, b3_runs, args.b3_status)
    report["notes"] = list(args.note) + report["notes"]
    Path(args.json).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    table = render_table(report)
    Path(args.table).write_text(table, encoding="utf-8")
    sys.stdout.write(table)
    return report["exit_code"]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
