#!/usr/bin/env python3
"""Deterministic tests of the bootstrap and gate G3 rules in perfstats.py.

Run: python3 scripts/perf/test_perfstats.py
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import perfstats  # noqa: E402


def startup_metric(base: list[float], cand: list[float], planned: int | None = None,
                   name: str = "startup.interactive_warm") -> dict:
    """ABBA blocks of one-value groups: two baseline and two candidate samples per block."""
    blocks = []
    for index in range(0, len(base), 2):
        blocks.append({
            "A": [[base[index]], [base[index + 1]]],
            "B": [[cand[index]], [cand[index + 1]]],
        })
    return {"name": name, "kind": "startup", "unit": "ms",
            "planned_groups_per_arm": planned if planned is not None else len(base),
            "blocks": blocks, "errors": [], "guard_failures": [], "support": {"A": True, "B": True}}


def key_metric(base_sessions: list[list[float]], cand_sessions: list[list[float]]) -> dict:
    blocks = [{"A": [base_sessions[0], base_sessions[1]], "B": [cand_sessions[0], cand_sessions[1]]}]
    return {"name": "key.bare_1", "kind": "key", "unit": "ms", "planned_groups_per_arm": 2,
            "blocks": blocks, "errors": [], "guard_failures": [], "support": {"A": True, "B": True}}


# 20 baseline samples around 100 ms with +-2 ms spread.
BASE = [100.0 + ((index * 7) % 5) - 2 for index in range(20)]


def raw(*metrics: dict, **extra) -> dict:
    data = {"arms": {"A": "a", "B": "b"}, "uptime": {"before": "load 1", "after": "load 1"},
            "metrics": list(metrics)}
    data.update(extra)
    return data


class QuantileTests(unittest.TestCase):
    def test_type7_interpolation(self):
        self.assertEqual(perfstats.quantile([1, 2, 3, 4], 0.5), 2.5)
        self.assertEqual(perfstats.quantile([5], 0.99), 5.0)
        self.assertAlmostEqual(perfstats.quantile(list(range(101)), 0.95), 95.0)

    def test_bootstrap_is_deterministic_and_brackets_shift(self):
        metric = startup_metric(BASE, [value + 10 for value in BASE])
        first = perfstats.bootstrap_difference(metric["blocks"], "median")
        second = perfstats.bootstrap_difference(metric["blocks"], "median")
        self.assertEqual(first, second)
        self.assertAlmostEqual(first["diff"], 10.0)
        self.assertLessEqual(first["ci_low"], 10.0)
        self.assertGreaterEqual(first["ci_high"], 10.0)


class StartupRuleTests(unittest.TestCase):
    def verdict(self, metric: dict, noise: dict | None = None) -> dict:
        rows = perfstats.judge_metric(metric, noise)
        self.assertEqual(len(rows), 1)
        return rows[0]

    def test_identical_arms_pass(self):
        row = self.verdict(startup_metric(BASE, list(BASE)))
        self.assertEqual(row["verdict"], "pass")
        self.assertTrue(row["resolved"])

    def test_large_shift_fails(self):
        # +20 ms on a 100 ms median: threshold is max(5 ms, 3 ms) = 5 ms.
        row = self.verdict(startup_metric(BASE, [value + 20 for value in BASE]))
        self.assertEqual(row["verdict"], "fail")
        self.assertAlmostEqual(row["threshold"], 5.0, places=1)

    def test_absolute_floor_applies_to_fast_metrics(self):
        # 40 ms median: 5% is 2 ms, so the 3 ms absolute floor is the threshold.
        base = [value - 60 for value in BASE]
        row = self.verdict(startup_metric(base, [value + 2.5 for value in base]))
        self.assertEqual(row["threshold"], 3.0)
        self.assertEqual(row["verdict"], "pass")

    def test_noise_floor_raises_threshold(self):
        metric = startup_metric(BASE, [value + 8 for value in BASE])
        self.assertEqual(self.verdict(metric)["verdict"], "fail")
        noise = {"metrics": {"startup.interactive_warm|median": {"noise_rel": 0.06}}}
        row = self.verdict(metric, noise)
        self.assertEqual(row["threshold_source"], "2x noise")
        self.assertAlmostEqual(row["threshold"], 12.0, places=0)
        self.assertEqual(row["verdict"], "pass")

    def test_missing_samples_are_inconclusive(self):
        metric = startup_metric(BASE[:4], BASE[:4], planned=20)
        row = self.verdict(metric)
        self.assertEqual(row["verdict"], "inconclusive")
        self.assertIn("valid groups", row["reason"])

    def test_guard_failure_is_inconclusive(self):
        metric = startup_metric(BASE, list(BASE))
        metric["guard_failures"] = ["A: history suggestion missing"]
        self.assertEqual(self.verdict(metric)["verdict"], "inconclusive")

    def test_unsupported_arm_is_not_gated(self):
        metric = startup_metric(BASE, list(BASE), name="startup.json_command_true")
        metric["support"] = {"A": False, "B": True}
        metric["unsupported"] = {"A": "--json rejected as a usage error (exit 1)"}
        row = self.verdict(metric)
        self.assertEqual(row["verdict"], "n/a")
        self.assertIn("arm A: --json rejected as a usage error", row["reason"])

    def test_unsupported_without_recorded_reason_is_inconclusive(self):
        # A raw file that marks an arm unsupported without saying why cannot
        # tell a missing feature from a measurement failure.
        metric = startup_metric(BASE, list(BASE), name="startup.interactive_cold")
        metric["support"] = {"A": False, "B": True}
        metric["errors"] = ["A: cold startup: wrapper has no exec -a hop"]
        row = self.verdict(metric)
        self.assertEqual(row["verdict"], "inconclusive")

    def test_unmeasured_metric_is_inconclusive(self):
        # What the harness records when the cold launcher cannot be set up.
        metric = startup_metric([], [], planned=24, name="startup.interactive_cold")
        metric["errors"] = ["A: cold startup: wrapper has no exec -a hop"]
        row = self.verdict(metric)
        self.assertEqual(row["verdict"], "inconclusive")
        self.assertIn("wrapper has no exec -a hop", row["reason"])

    def test_missing_noise_entry_is_inconclusive(self):
        # B - A = +20 ms on 100 ms. A complete noise file with noise_rel 0.2
        # raises the threshold to 40 ms; a noise file without the metric must
        # not fall back to the 5 ms table threshold.
        metric = startup_metric(BASE, [value + 20 for value in BASE])
        complete = {"metrics": {"startup.interactive_warm|median": {"noise_rel": 0.2}}}
        row = self.verdict(metric, complete)
        self.assertEqual(row["verdict"], "pass")
        self.assertAlmostEqual(row["threshold"], 40.0, places=0)
        row = self.verdict(metric, {"metrics": {}})
        self.assertEqual(row["verdict"], "inconclusive")
        self.assertIn("noise file has no entry", row["reason"])
        self.assertNotIn("threshold", row)

    def test_missing_noise_entry_reports_the_noise_run_reason(self):
        metric = startup_metric(BASE, list(BASE))
        noise = {"metrics": {}, "missing": {"startup.interactive_warm|median": "correctness guard failed: A: x"}}
        row = self.verdict(metric, noise)
        self.assertEqual(row["verdict"], "inconclusive")
        self.assertIn("correctness guard failed: A: x", row["reason"])


class KeyRuleTests(unittest.TestCase):
    def test_tail_regression_fails_p99_and_p95(self):
        base = [[5.0 + (index % 10) * 0.1 for index in range(200)] for _ in range(2)]
        # Every tenth key is 30 ms slower in the candidate.
        cand = [[value + (30.0 if index % 10 == 9 else 0.0) for index, value in enumerate(session)]
                for session in base]
        rows = {row["stat"]: row for row in perfstats.judge_metric(key_metric(base, cand), None)}
        self.assertEqual(rows["p95"]["verdict"], "fail")
        self.assertEqual(rows["p99"]["verdict"], "fail")
        self.assertEqual(rows["median"]["verdict"], "info")

    def test_equal_sessions_pass(self):
        base = [[5.0 + (index % 10) * 0.1 for index in range(200)] for _ in range(2)]
        rows = perfstats.judge_metric(key_metric(base, [list(session) for session in base]), None)
        self.assertEqual({row["verdict"] for row in rows if row["gated"]}, {"pass"})


class B3Tests(unittest.TestCase):
    def write(self, directory: Path, name: str, consing: float, file_io: float, io_gate: bool = True) -> Path:
        path = directory / name
        path.write_text(json.dumps({"uptime": "load 1", "scenarios": [{
            "name": "bare_1", "keys": 30, "bytes_consed_per_key": {"mean": consing, "p50": consing, "p95": consing},
            "stat_per_key": 0, "file_io_per_key": file_io, "spawn_per_key": 0, "io_gate": io_gate}]}))
        return path

    def runs(self, directory: Path, cand_consing: float, cand_io: float, io_gate: bool = True) -> list:
        return [
            ("A", 1, self.write(directory, "a1.json", 1000, 0, io_gate)),
            ("B", 1, self.write(directory, "b1.json", cand_consing, cand_io, io_gate)),
            ("B", 1, self.write(directory, "b2.json", cand_consing, cand_io, io_gate)),
            ("A", 1, self.write(directory, "a2.json", 1000, 0, io_gate)),
        ]

    def rows(self, runs: list) -> dict:
        report = perfstats.build_report(raw(startup_metric(BASE, list(BASE))), None, None, runs, None)
        return {row["metric"]: row for row in report["rows"]}, report

    def test_consing_and_new_io_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, report = self.rows(self.runs(Path(directory), 1200, 2))
        self.assertEqual(rows["b3.bare_1.bytes_consed_per_key"]["verdict"], "fail")
        self.assertEqual(rows["b3.bare_1.file_io_per_key"]["verdict"], "fail")
        self.assertEqual(rows["b3.bare_1.spawn_per_key"]["verdict"], "pass")
        self.assertEqual(report["verdict"], "fail")

    def test_io_gate_false_reports_counts_without_gating(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, report = self.rows(self.runs(Path(directory), 1000, 2, io_gate=False))
        self.assertEqual(rows["b3.bare_1.file_io_per_key"]["verdict"], "info")
        self.assertFalse(rows["b3.bare_1.file_io_per_key"]["gated"])
        self.assertEqual(report["verdict"], "pass")

    def test_io_gate_false_still_gates_consing(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, report = self.rows(self.runs(Path(directory), 1200, 2, io_gate=False))
        self.assertEqual(rows["b3.bare_1.file_io_per_key"]["verdict"], "info")
        self.assertEqual(rows["b3.bare_1.bytes_consed_per_key"]["verdict"], "fail")
        self.assertEqual(report["verdict"], "fail")

    def test_missing_io_gate_counts_as_true(self):
        with tempfile.TemporaryDirectory() as directory:
            runs = self.runs(Path(directory), 1000, 2)
            for _, _, path in runs:
                data = json.loads(path.read_text())
                del data["scenarios"][0]["io_gate"]
                path.write_text(json.dumps(data))
            rows, report = self.rows(runs)
        self.assertEqual(rows["b3.bare_1.file_io_per_key"]["verdict"], "fail")
        self.assertEqual(report["verdict"], "fail")

    def test_small_consing_change_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, report = self.rows(self.runs(Path(directory), 1050, 0))
        self.assertEqual(rows["b3.bare_1.bytes_consed_per_key"]["verdict"], "pass")
        self.assertEqual(report["verdict"], "pass")

    def test_noise_file_without_b3_makes_consing_inconclusive_but_still_judges_counts(self):
        # noise.sh without --src: the noise file has no B3 entries.
        noise = perfstats.build_noise(raw(startup_metric(BASE, list(BASE))), [])
        with tempfile.TemporaryDirectory() as directory:
            report = perfstats.build_report(raw(startup_metric(BASE, list(BASE))), noise, "noise.json",
                                            self.runs(Path(directory), 1000, 2), None)
        rows = {row["metric"]: row for row in report["rows"]}
        self.assertEqual(rows["b3.bare_1.bytes_consed_per_key"]["verdict"], "inconclusive")
        self.assertEqual(rows["b3.bare_1.file_io_per_key"]["verdict"], "fail")
        self.assertEqual(rows["b3.bare_1.stat_per_key"]["verdict"], "pass")
        self.assertEqual(report["verdict"], "fail")

    def test_noise_file_with_b3_judges_consing(self):
        with tempfile.TemporaryDirectory() as directory:
            noise_runs = self.runs(Path(directory), 1000, 0)
            noise = perfstats.build_noise(raw(startup_metric(BASE, list(BASE))), noise_runs)
            report = perfstats.build_report(raw(startup_metric(BASE, list(BASE))), noise, "noise.json",
                                            self.runs(Path(directory), 1050, 0), None)
        rows = {row["metric"]: row for row in report["rows"]}
        self.assertEqual(rows["b3.bare_1.bytes_consed_per_key"]["verdict"], "pass")
        self.assertEqual(report["verdict"], "pass")

    def test_missing_count_value_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            runs = self.runs(Path(directory), 1000, 0)
            data = json.loads(runs[1][2].read_text())
            del data["scenarios"][0]["file_io_per_key"]
            runs[1][2].write_text(json.dumps(data))
            rows, report = self.rows(runs)
        self.assertEqual(rows["b3.bare_1.file_io_per_key"]["verdict"], "inconclusive")
        self.assertEqual(report["verdict"], "inconclusive")

    def test_unreadable_b3_file_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            runs = self.runs(Path(directory), 1000, 0)
            runs[1] = ("B", 1, Path(directory) / "missing.json")
            _, report = self.rows(runs)
        self.assertEqual(report["verdict"], "inconclusive")


class OverallTests(unittest.TestCase):
    def test_overall_outcomes_and_exit_codes(self):
        cases = {
            "pass": (raw(startup_metric(BASE, list(BASE))), perfstats.EXIT_PASS),
            "fail": (raw(startup_metric(BASE, [value + 20 for value in BASE])), perfstats.EXIT_FAIL),
            "inconclusive": (raw(startup_metric(BASE[:4], BASE[:4], planned=20)), perfstats.EXIT_INCONCLUSIVE),
        }
        with tempfile.TemporaryDirectory() as directory:
            for expected, (data, code) in cases.items():
                path = Path(directory) / f"{expected}.json"
                path.write_text(json.dumps(data))
                out = Path(directory) / f"{expected}-verdict.json"
                exit_code = perfstats.main(["judge", str(path), "--json", str(out),
                                            "--table", str(Path(directory) / f"{expected}.txt")])
                self.assertEqual(exit_code, code, expected)
                self.assertEqual(json.loads(out.read_text())["verdict"], expected)

    def test_fail_outranks_inconclusive(self):
        data = raw(startup_metric(BASE, [value + 20 for value in BASE]),
                   startup_metric(BASE[:4], BASE[:4], planned=20, name="startup.c_true"))
        report = perfstats.build_report(data, None, None, [], None)
        self.assertEqual(report["verdict"], "fail")

    def test_harness_error_makes_pass_inconclusive(self):
        data = raw(startup_metric(BASE, list(BASE)), fatal_error="OSError: boom")
        self.assertEqual(perfstats.build_report(data, None, None, [], None)["verdict"], "inconclusive")

    def test_no_gated_metric_is_inconclusive(self):
        metric = startup_metric(BASE, list(BASE))
        metric["support"] = {"A": False, "B": False}
        self.assertEqual(perfstats.build_report(raw(metric), None, None, [], None)["verdict"], "inconclusive")

    def test_noise_file_round_trip(self):
        noise = perfstats.build_noise(raw(startup_metric(BASE, list(BASE))), [])
        entry = noise["metrics"]["startup.interactive_warm|median"]
        self.assertGreaterEqual(entry["noise_rel"], 0.0)
        self.assertLess(entry["noise_rel"], 0.05)

    def test_unmeasured_cold_startup_makes_pass_inconclusive(self):
        cold = startup_metric([], [], planned=24, name="startup.interactive_cold")
        cold["errors"] = ["A: cold startup: wrapper has no exec -a hop"]
        report = perfstats.build_report(raw(startup_metric(BASE, list(BASE)), cold), None, None, [], None)
        self.assertEqual(report["verdict"], "inconclusive")

    def test_confirmed_unsupported_metric_does_not_block_pass(self):
        json_metric = startup_metric(BASE, list(BASE), name="startup.json_command_true")
        json_metric["support"] = {"A": False, "B": False}
        json_metric["unsupported"] = {"A": "usage error", "B": "usage error"}
        report = perfstats.build_report(raw(startup_metric(BASE, list(BASE)), json_metric), None, None, [], None)
        self.assertEqual(report["verdict"], "pass")
        self.assertIn("n/a: startup.json_command_true median: unsupported by arm A: usage error",
                      perfstats.render_table(report))

    def test_noise_run_with_unmeasured_gated_metric_is_inconclusive(self):
        guarded = startup_metric(BASE, list(BASE), name="startup.interactive_history_10k")
        guarded["guard_failures"] = ["A: history suggestion missing"]
        data = raw(startup_metric(BASE, list(BASE)), guarded)
        noise = perfstats.build_noise(data, [])
        self.assertIn("startup.interactive_history_10k|median", noise["missing"])
        self.assertFalse(noise["complete"])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "raw.json"
            path.write_text(json.dumps(data))
            out = Path(directory) / "noise.json"
            self.assertEqual(perfstats.main(["noise", str(path), "--out", str(out)]), perfstats.EXIT_INCONCLUSIVE)
            self.assertTrue(out.exists())
            path.write_text(json.dumps(raw(startup_metric(BASE, list(BASE)))))
            self.assertEqual(perfstats.main(["noise", str(path), "--out", str(out)]), perfstats.EXIT_PASS)

    def test_noise_run_with_harness_or_b3_error_is_inconclusive(self):
        data = raw(startup_metric(BASE, list(BASE)), fatal_error="OSError: boom")
        self.assertFalse(perfstats.build_noise(data, [])["complete"])
        noise = perfstats.build_noise(raw(startup_metric(BASE, list(BASE))), [], "error: b3-measure.sh failed: x")
        self.assertFalse(noise["complete"])

    def test_noise_run_records_unsupported_metric_without_failing(self):
        json_metric = startup_metric(BASE, list(BASE), name="startup.json_command_true")
        json_metric["support"] = {"A": False, "B": False}
        json_metric["unsupported"] = {"A": "usage error", "B": "usage error"}
        noise = perfstats.build_noise(raw(startup_metric(BASE, list(BASE)), json_metric), [])
        self.assertTrue(noise["complete"])
        self.assertIn("startup.json_command_true|median", noise["unsupported"])

    def test_noise_entry_for_zero_consing(self):
        metric = {"name": "b3.x.bytes_consed_per_key", "kind": "consing", "unit": "bytes",
                  "planned_groups_per_arm": 2, "errors": [],
                  "blocks": [{"A": [[0.0], [0.0]], "B": [[0.0], [0.0]]}]}
        noise = perfstats.build_noise(raw(metric), [])
        self.assertEqual(noise["metrics"]["b3.x.bytes_consed_per_key|mean"]["noise_rel"], 0.0)
        self.assertTrue(noise["complete"])

    def test_usage_error_exit_code(self):
        self.assertEqual(perfstats.main(["judge"]), perfstats.EXIT_USAGE)
        self.assertEqual(perfstats.main(["judge", "/nonexistent.json", "--json", "/dev/null",
                                         "--table", "/dev/null"]), perfstats.EXIT_USAGE)


if __name__ == "__main__":
    unittest.main(verbosity=1)
