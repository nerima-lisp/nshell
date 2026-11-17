#!/usr/bin/env python3
"""Tests for workflow NFR selection parsing."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


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


class NfrSelectionTests(unittest.TestCase):
    def test_all_selects_every_nfr(self) -> None:
        self.assertEqual(nfr_selection.parse_nfr_selection("all"), ("03", "08", "09"))

    def test_comma_separated_selection_trims_whitespace(self) -> None:
        self.assertEqual(nfr_selection.parse_nfr_selection(" 03, 09 "), ("03", "09"))

    def test_invalid_selections_are_rejected(self) -> None:
        for value in ("", "03,", "3", "10", "03,03", "all,08", "01", "05", "07"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                nfr_selection.parse_nfr_selection(value)

    def test_workflow_outputs_mark_unselected_nfrs_false(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output_path = Path(temporary) / "outputs"
            output_path.touch()
            nfr_selection.write_github_outputs("03", output_path)
            outputs = dict(line.split("=", 1) for line in output_path.read_text().splitlines())

        self.assertEqual(outputs["selected"], "03")
        self.assertEqual(outputs["all"], "false")
        self.assertEqual(outputs["requires_binary"], "true")
        self.assertEqual(outputs["nfr_03"], "true")
        self.assertEqual(outputs["nfr_08"], "false")
        self.assertEqual(outputs["nfr_09"], "false")

    def test_nfr09_selection_skips_binary_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output_path = Path(temporary) / "outputs"
            output_path.touch()
            nfr_selection.write_github_outputs("09", output_path)
            outputs = dict(line.split("=", 1) for line in output_path.read_text().splitlines())

        self.assertEqual(outputs["all"], "false")
        self.assertEqual(outputs["requires_binary"], "false")
        self.assertEqual(outputs["nfr_03"], "false")
        self.assertEqual(outputs["nfr_09"], "true")

    def test_selected_summary_lists_only_selected_nfr_without_false_passes(self) -> None:
        result = measure_nfr_ci.error_result("03", "measurement unavailable")
        summary = measure_nfr_ci.build_summary(
            [result], "aarch64-darwin", "revision", ("03", "08"), full_selection=False
        )

        self.assertIn("Selected NFRs: NFR-03, NFR-08.", summary)
        self.assertIn("Unselected NFRs were not measured: NFR-09.", summary)
        self.assertIn("| NFR-03 | not measured |", summary)
        self.assertIn("**ERROR: measurement unavailable**", summary)
        self.assertNotIn("| NFR-08 |", summary)
        self.assertNotIn("**PASS**", summary)

    def test_all_summary_keeps_the_full_measurement_table_shape(self) -> None:
        summary = measure_nfr_ci.build_summary(
            [measure_nfr_ci.error_result("03", "unavailable")],
            "aarch64-darwin",
            "revision",
            nfr_selection.NFR_IDS,
            full_selection=True,
        )

        self.assertTrue(summary.startswith("# NFR-03, NFR-08 and NFR-09 performance results\n"))
        self.assertNotIn("Selected NFRs:", summary)
        self.assertEqual(summary.count("| NFR-"), 1)

    def test_nfr03_summary_is_checked_against_the_threshold(self) -> None:
        def summary(median_ms: float, **overrides: object) -> dict[str, object]:
            return {
                "record": "summary",
                "nfr": "03",
                "sample_count": measure_nfr_ci.NFR03_SAMPLES,
                "target_median_ms": median_ms,
                "control_median_ms": 1.0,
                "criterion_threshold_ms": 5000.0,
                **overrides,
            }

        self.assertEqual(measure_nfr_ci.result_from_03(summary(4000.0))["status"], "PASS")
        self.assertEqual(measure_nfr_ci.result_from_03(summary(6000.0))["status"], "FAIL")
        with self.assertRaisesRegex(ValueError, "threshold does not match"):
            measure_nfr_ci.result_from_03(summary(4000.0, criterion_threshold_ms=6000.0))
        with self.assertRaisesRegex(ValueError, "configured sample count"):
            measure_nfr_ci.result_from_03(summary(4000.0, sample_count=5))

        with tempfile.TemporaryDirectory() as temporary:
            output_dir = Path(temporary)
            passed = measure_nfr_ci.write_outputs(
                output_dir,
                [measure_nfr_ci.result_from_03(summary(6000.0))],
                "aarch64-darwin",
                "revision",
                ("03",),
                full_selection=False,
            )
            summary_text = (output_dir / "summary.md").read_text()
            records = [json.loads(line) for line in (output_dir / "results.jsonl").read_text().splitlines()]

        self.assertFalse(passed)
        self.assertIn("| NFR-03 | 6000.0 ms | ≤ 5000.0 ms | **FAIL** |", summary_text)
        self.assertEqual([record["record"] for record in records], ["metadata", "result"])


if __name__ == "__main__":
    unittest.main()
