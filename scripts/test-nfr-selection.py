#!/usr/bin/env python3
"""Tests for workflow NFR selection parsing."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("nfr_selection.py")
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("nfr_selection", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
nfr_selection = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nfr_selection)
MEASURE_PATH = Path(__file__).with_name("measure-nfr-ci.py")
MEASURE_SPEC = importlib.util.spec_from_file_location("measure_nfr_ci", MEASURE_PATH)
assert MEASURE_SPEC is not None and MEASURE_SPEC.loader is not None
measure_nfr_ci = importlib.util.module_from_spec(MEASURE_SPEC)
MEASURE_SPEC.loader.exec_module(measure_nfr_ci)
DRIVER_PATH = Path(__file__).with_name("measure-nfr-04-06.py")
DRIVER_SPEC = importlib.util.spec_from_file_location("measure_nfr_04_06", DRIVER_PATH)
assert DRIVER_SPEC is not None and DRIVER_SPEC.loader is not None
measure_nfr_04_06 = importlib.util.module_from_spec(DRIVER_SPEC)
DRIVER_SPEC.loader.exec_module(measure_nfr_04_06)


class NfrSelectionTests(unittest.TestCase):
    def test_all_selects_every_nfr(self) -> None:
        self.assertEqual(nfr_selection.parse_nfr_selection("all"), nfr_selection.NFR_IDS)

    def test_comma_separated_selection_trims_whitespace(self) -> None:
        self.assertEqual(nfr_selection.parse_nfr_selection(" 01, 03 "), ("01", "03"))

    def test_invalid_selections_are_rejected(self) -> None:
        for value in ("", "01,", "1", "10", "01,01", "all,05"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                nfr_selection.parse_nfr_selection(value)

    def test_workflow_outputs_mark_unselected_nfrs_false(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output_path = Path(temporary) / "outputs"
            output_path.touch()
            nfr_selection.write_github_outputs("05", output_path)
            outputs = dict(line.split("=", 1) for line in output_path.read_text().splitlines())

        self.assertEqual(outputs["selected"], "05")
        self.assertEqual(outputs["all"], "false")
        self.assertEqual(outputs["requires_binary"], "true")
        self.assertEqual(outputs["measures_01_07"], "true")
        self.assertEqual(outputs["nfr_05"], "true")
        self.assertEqual(outputs["nfr_04"], "false")

    def test_nfr09_selection_skips_binary_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output_path = Path(temporary) / "outputs"
            output_path.touch()
            nfr_selection.write_github_outputs("09", output_path)
            outputs = dict(line.split("=", 1) for line in output_path.read_text().splitlines())

        self.assertEqual(outputs["all"], "false")
        self.assertEqual(outputs["requires_binary"], "false")
        self.assertEqual(outputs["measures_01_07"], "false")
        self.assertEqual(outputs["nfr_09"], "true")

    def test_selected_summary_lists_only_selected_nfr_without_false_passes(self) -> None:
        result = measure_nfr_ci.error_result("05", "measurement unavailable")
        summary = measure_nfr_ci.build_summary(
            [result], None, [], "aarch64-darwin", "revision", ("05",), full_selection=False
        )

        self.assertIn("Selected NFRs: NFR-05.", summary)
        self.assertIn("Unselected NFRs were not measured:", summary)
        self.assertIn("| NFR-05 | not measured |", summary)
        self.assertIn("**ERROR: measurement unavailable**", summary)
        self.assertNotIn("| NFR-04 |", summary)
        self.assertNotIn("**PASS**", summary)

    def test_nfr04_only_fixtures_do_not_require_completion_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            plain_fixture = root / "plain"
            git_fixture = root / "git"
            plain_fixture.mkdir()
            git_fixture.mkdir()
            args = measure_nfr_04_06.build_parser().parse_args(
                [
                    "--binary",
                    "/bin/sh",
                    "--from",
                    "nfr04-only",
                    "--samples",
                    "100",
                    "--plain-fixture",
                    str(plain_fixture),
                    "--git-fixture",
                    str(git_fixture),
                    "--output",
                    str(root / "output.jsonl"),
                ]
            )
            with (
                patch.object(
                    measure_nfr_04_06,
                    "find_git_root",
                    side_effect=[None, git_fixture.resolve()],
                ),
                patch.object(
                    measure_nfr_04_06.subprocess,
                    "run",
                    return_value=SimpleNamespace(stdout="main\\n"),
                ),
            ):
                fixtures = measure_nfr_04_06.validate_fixtures(args)

        self.assertIsNone(fixtures["completion_fixture"])
        self.assertEqual(fixtures["completion_entries"], 0)

    def test_all_summary_keeps_the_full_measurement_table_shape(self) -> None:
        results = [measure_nfr_ci.error_result(nfr, "unavailable") for nfr in nfr_selection.NFR_IDS[:7]]
        summary = measure_nfr_ci.build_summary(
            results,
            None,
            [],
            "aarch64-darwin",
            "revision",
            nfr_selection.NFR_IDS,
            full_selection=True,
        )

        self.assertTrue(summary.startswith("# NFR-01 to NFR-07 performance results\n"))
        self.assertNotIn("Selected NFRs:", summary)
        self.assertEqual(summary.count("| NFR-"), 7)

    def test_group_summaries_survive_later_diagnostic_failure(self) -> None:
        def summary(metric: str, value: float, statistic: str, threshold: float, **context: object) -> dict[str, object]:
            return {
                "record": "group-summary",
                "metric": metric,
                "threshold_ms": threshold,
                "acceptance_statistic": statistic,
                "measured_samples": 100,
                "target_threshold_met": value <= threshold,
                "target": {statistic + "_ms": value},
                **context,
            }

        group_summaries = [
            summary("NFR-04", 8.4, "median", 60.0, git_prompt_enabled=False),
            summary("NFR-04", 10.5, "median", 60.0, git_prompt_enabled=True),
            summary("NFR-05", 33.0, "p99", 16.0),
            summary("NFR-06", 34.9, "median", 100.0),
        ]

        with tempfile.TemporaryDirectory() as temporary:
            output_dir = Path(temporary) / "output"
            output_dir.mkdir()

            def write_partial_output(label: str, command: list[str], log_path: Path) -> tuple[int, None]:
                raw_path = Path(command[command.index("--output") + 1])
                raw_path.write_text(
                    "".join(json.dumps(row) + "\n" for row in group_summaries),
                    encoding="utf-8",
                )
                return 1, None

            with patch.object(measure_nfr_ci, "run_command", side_effect=write_partial_output):
                rows, diagnostic, metric_errors, diagnostic_errors = measure_nfr_ci.measure_all_nfr_04_06(
                    Path("/bin/sh"), output_dir, output_dir / "logs"
                )

            selected_output_dir = Path(temporary) / "selected"
            selected_output_dir.mkdir()
            with patch.object(measure_nfr_ci, "run_command", side_effect=write_partial_output):
                selected_result, selected_diagnostic, selected_errors = measure_nfr_ci.measure_nfr_04_06(
                    "06", Path("/bin/sh"), selected_output_dir, selected_output_dir / "logs"
                )

        self.assertIsNone(diagnostic)
        self.assertEqual(metric_errors, {})
        self.assertEqual(selected_result["value"], 34.9)
        self.assertIsNone(selected_diagnostic)
        self.assertTrue(selected_errors)
        self.assertTrue(any("exited with status 1" in error for error in diagnostic_errors))
        self.assertTrue(any("complete-C output diagnostic" in error for error in diagnostic_errors))
        self.assertEqual(rows["04"]["value"], 10.5)
        self.assertEqual(rows["04"]["status"], "PASS")
        self.assertEqual(rows["05"]["value"], 33.0)
        self.assertEqual(rows["05"]["status"], "FAIL")
        self.assertEqual(rows["06"]["value"], 34.9)
        self.assertEqual(rows["06"]["status"], "PASS")
        self.assertTrue(diagnostic_errors)

        with tempfile.TemporaryDirectory() as temporary:
            output_dir = Path(temporary)
            passed = measure_nfr_ci.write_outputs(
                output_dir,
                list(rows.values()),
                diagnostic,
                diagnostic_errors,
                "aarch64-darwin",
                "revision",
                ("04", "05", "06"),
                full_selection=False,
            )
            summary_text = (output_dir / "summary.md").read_text()
            result_records = [
                json.loads(line)
                for line in (output_dir / "results.jsonl").read_text().splitlines()
            ]

        with tempfile.TemporaryDirectory() as temporary:
            diagnostic_only_passed = measure_nfr_ci.write_outputs(
                Path(temporary),
                [rows["04"]],
                None,
                diagnostic_errors,
                "aarch64-darwin",
                "revision",
                ("04",),
                full_selection=False,
            )

        self.assertFalse(passed)
        self.assertFalse(diagnostic_only_passed)
        self.assertIn("| NFR-04 | Git off 8.4 ms; Git on 10.5 ms |", summary_text)
        self.assertIn("| NFR-05 | 33.0 ms |", summary_text)
        self.assertIn("| NFR-06 | 34.9 ms |", summary_text)
        self.assertNotIn("| NFR-06 | not measured |", summary_text)
        self.assertIn("Diagnostic failures:", summary_text)
        self.assertEqual(sum(record["record"] == "diagnostic-error" for record in result_records), len(diagnostic_errors))
        result_by_nfr = {record["nfr"]: record for record in result_records if record["record"] == "result"}
        self.assertEqual(result_by_nfr["NFR-05"]["status"], "FAIL")
        self.assertEqual(result_by_nfr["NFR-06"]["value"], 34.9)

    def test_invalid_group_summaries_cannot_pass(self) -> None:
        nfr05 = {
            "metric": "NFR-05",
            "threshold_ms": 16.0,
            "acceptance_statistic": "p99",
            "measured_samples": 100,
            "target_threshold_met": "false",
            "target": {"p99_ms": 10.0},
        }
        with self.assertRaisesRegex(ValueError, "must include a boolean threshold result"):
            measure_nfr_ci.result_from_04_06("05", nfr05)

        nfr04_git_off = {
            "record": "group-summary",
            "metric": "NFR-04",
            "threshold_ms": 60.0,
            "acceptance_statistic": "median",
            "measured_samples": 100,
            "target_threshold_met": True,
            "target": {"median_ms": 8.4},
        }
        nfr04_git_on = {
            **nfr04_git_off,
            "git_prompt_enabled": True,
            "target": {"median_ms": 10.5},
        }

        results, _, metric_errors, _ = measure_nfr_ci.results_from_04_06_summaries(
            [nfr04_git_off, nfr04_git_on]
        )

        self.assertNotIn("04", results)
        self.assertIn("04", metric_errors)
        self.assertIn("must be a boolean", metric_errors["04"])


if __name__ == "__main__":
    unittest.main()
