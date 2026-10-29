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
    def test_nfr05_diagnostic_join_requires_matching_ids_for_all_samples(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sample_path = root / "samples.jsonl"
            diagnostic_path = root / "diagnostics.jsonl"
            sample_ids = [f"sample-{index}" for index in range(102)]
            sample_path.write_text(
                "".join(
                    json.dumps(
                        {"record": "sample", "metric": "NFR-05", "sample_id": sample_id}
                    )
                    + "\n"
                    for sample_id in sample_ids
                ),
                encoding="utf-8",
            )
            diagnostic_path.write_text(
                "".join(
                    json.dumps(
                        {
                            "record": "nfr05-sample-diagnostic",
                            "sample_id": sample_id,
                        }
                    )
                    + "\n"
                    for sample_id in sample_ids
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                measure_nfr_ci.validate_nfr05_diagnostic_join(sample_path, diagnostic_path),
                102,
            )

            diagnostic_path.write_text(
                diagnostic_path.read_text(encoding="utf-8").replace("sample-101", "mismatch"),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "do not join one-to-one"):
                measure_nfr_ci.validate_nfr05_diagnostic_join(sample_path, diagnostic_path)

    def test_nfr05_diagnostics_flag_requires_exact_nfr05_selection(self) -> None:
        arguments = [
            "measure-nfr-ci.py",
            "--binary",
            "/bin/sh",
            "--output-dir",
            "/tmp/nfr05-output",
            "--nfrs",
            "05",
            "--nfr05-diagnostics",
        ]
        with patch.object(sys, "argv", arguments):
            parsed = measure_nfr_ci.parse_args()
        self.assertTrue(parsed.nfr05_diagnostics)

        with patch.object(sys, "argv", [*arguments[:-2], "all", "--nfr05-diagnostics"]):
            with self.assertRaises(SystemExit):
                measure_nfr_ci.parse_args()

    def test_ci_measurement_passes_diagnostics_and_joins_the_same_redraw_ids(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output_dir = Path(temporary) / "output"
            logs_dir = output_dir / "logs"
            output_dir.mkdir()
            logs_dir.mkdir()
            sample_ids = [f"sample-{index}" for index in range(102)]
            captured: dict[str, list[str]] = {}

            def fake_run_command(label, command, log_path):
                captured["command"] = command
                output_path = Path(command[command.index("--output") + 1])
                diagnostic_path = Path(
                    command[command.index("--nfr05-diagnostics-output") + 1]
                )
                output_records = [
                    {
                        "record": "sample",
                        "metric": "NFR-05",
                        "sample_id": sample_id,
                    }
                    for sample_id in sample_ids
                ]
                output_records.append(
                    {
                        "record": "group-summary",
                        "metric": "NFR-05",
                        "threshold_ms": measure_nfr_ci.NFR_THRESHOLDS["05"]["limit"],
                        "acceptance_statistic": "p99",
                        "measured_samples": measure_nfr_ci.NFR04_06_SAMPLES,
                        "target_threshold_met": True,
                        "target": {"median_ms": 8.0, "p99_ms": 12.0},
                    }
                )
                output_path.write_text(
                    "".join(json.dumps(row) + "\n" for row in output_records),
                    encoding="utf-8",
                )
                diagnostic_path.write_text(
                    "".join(
                        json.dumps(
                            {
                                "record": "nfr05-sample-diagnostic",
                                "sample_id": sample_id,
                            }
                        )
                        + "\n"
                        for sample_id in sample_ids
                    ),
                    encoding="utf-8",
                )
                return 0, None

            with patch.object(measure_nfr_ci, "run_command", side_effect=fake_run_command):
                result, diagnostic = measure_nfr_ci.measure_nfr_04_06(
                    "05",
                    Path("/bin/sh"),
                    output_dir,
                    logs_dir,
                    nfr05_diagnostics=True,
                )

        self.assertIsNone(diagnostic)
        self.assertEqual(
            captured["command"][captured["command"].index("--nfr05-diagnostics-output") + 1],
            str(output_dir / "nfr-05-sample-diagnostics.jsonl"),
        )
        self.assertEqual(
            result["details"]["per_event_diagnostics"]["joined_samples_including_warmups"],
            102,
        )

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
