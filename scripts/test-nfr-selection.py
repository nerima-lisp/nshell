#!/usr/bin/env python3
"""Tests for workflow NFR selection parsing."""

from __future__ import annotations

import importlib.util
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
            [result], None, "aarch64-darwin", "revision", ("05",), full_selection=False
        )

        self.assertIn("Selected NFRs: NFR-05.", summary)
        self.assertIn("Unselected NFRs were not measured:", summary)
        self.assertIn("| NFR-05 | not measured |", summary)
        self.assertIn("**ERROR: measurement unavailable**", summary)
        self.assertNotIn("| NFR-04 |", summary)
        self.assertNotIn("**PASS**", summary)

    def test_all_summary_keeps_the_full_measurement_table_shape(self) -> None:
        results = [measure_nfr_ci.error_result(nfr, "unavailable") for nfr in nfr_selection.NFR_IDS[:7]]
        summary = measure_nfr_ci.build_summary(
            results,
            None,
            "aarch64-darwin",
            "revision",
            nfr_selection.NFR_IDS,
            full_selection=True,
        )

        self.assertTrue(summary.startswith("# NFR-01 to NFR-07 performance results\n"))
        self.assertNotIn("Selected NFRs:", summary)
        self.assertEqual(summary.count("| NFR-"), 7)


if __name__ == "__main__":
    unittest.main()
