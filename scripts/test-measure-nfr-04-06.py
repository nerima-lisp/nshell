#!/usr/bin/env python3
"""Tests for NFR-04/NFR-06 measurement helpers."""

from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path


MEASURE_PATH = Path(__file__).with_name("measure-nfr-04-06.py")
SPEC = importlib.util.spec_from_file_location("measure_nfr_04_06", MEASURE_PATH)
assert SPEC is not None and SPEC.loader is not None
measurement = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(measurement)


class Nfr0406MeasurementTests(unittest.TestCase):
    def test_nfr06_counts_candidate_cells_not_prompt_suggestion_text(self) -> None:
        expected = [f"item-{index:05d}".encode() for index in range(28)]
        prompt_suggestion = b"cat item-\x1b[38;5;242m00000\x1b[0m"
        pager_rows = b"\r\x1b[2K\r\n" + b"\n".join(
            b"\xe2\x88\x99 " + candidate for candidate in expected
        )
        response = prompt_suggestion + pager_rows
        visible = measurement.visible_terminal_text(response)

        self.assertEqual(len(re.findall(rb"item-\d{5}", visible)), 29)
        self.assertEqual(measurement.nfr06_candidate_ids(visible), expected)

    def test_nfr05_sample_id_joins_sample_row_to_same_redraw_diagnostics(self) -> None:
        import io
        import json
        import tempfile
        from pathlib import Path
        from unittest.mock import patch

        sample_output = io.StringIO()
        with tempfile.TemporaryDirectory() as temp:
            diagnostic_output = Path(temp) / "nfr05-diagnostics.jsonl"
            call_count = 0

            def target_runner(sample_id: str) -> dict[str, object]:
                nonlocal call_count
                call_count += 1
                diagnostics = {
                    "record": "nfr05-render-diagnostic",
                    "schema_version": 2,
                    "sample_id": sample_id,
                    "gc_count": call_count,
                }
                return {
                    "sample_id": sample_id,
                    "latency_ms": float(call_count),
                    "keypress_realtime_ns": call_count * 100,
                    "redraw_complete_realtime_ns": call_count * 100 + 1,
                    "diagnostics": diagnostics,
                }

            with patch.object(
                measurement,
                "uptime_record",
                return_value={"load_average_1m": 0.0},
            ):
                measurement.run_target_group(
                    sample_output,
                    "NFR-05",
                    {"buffer_length": 1000},
                    samples=2,
                    warmups=1,
                    threshold_ms=16.0,
                    acceptance_statistic="p99",
                    target_runner=target_runner,
                    diagnostic_output_path=diagnostic_output,
                )

            sample_rows = [
                json.loads(line)
                for line in sample_output.getvalue().splitlines()
                if json.loads(line)["record"] == "sample"
            ]
            diagnostic_rows = [
                json.loads(line) for line in diagnostic_output.read_text().splitlines()
            ]

        self.assertEqual(len(sample_rows), 3)
        self.assertEqual(len(diagnostic_rows), 3)
        sample_ids = [row["sample_id"] for row in sample_rows]
        self.assertEqual(len(set(sample_ids)), 3)
        self.assertEqual(sample_ids, [row["sample_id"] for row in diagnostic_rows])
        for sample_row, diagnostic_row in zip(sample_rows, diagnostic_rows, strict=True):
            self.assertEqual(sample_row["target"]["sample_id"], diagnostic_row["sample_id"])
            self.assertEqual(
                sample_row["target"]["diagnostics"],
                diagnostic_row["diagnostics"],
            )
            self.assertEqual(sample_row["sample"], diagnostic_row["sample"])
            self.assertEqual(sample_row["warmup"], diagnostic_row["warmup"])

    def test_nfr05_default_sample_path_has_no_diagnostic_ids(self) -> None:
        import io
        import json
        from unittest.mock import patch

        sample_output = io.StringIO()

        with patch.object(
            measurement,
            "uptime_record",
            return_value={"load_average_1m": 0.0},
        ):
            measurement.run_target_group(
                sample_output,
                "NFR-05",
                {"buffer_length": 1000},
                samples=1,
                warmups=0,
                threshold_ms=16.0,
                acceptance_statistic="p99",
                target_runner=lambda: {"latency_ms": 2.0},
            )

        rows = [json.loads(line) for line in sample_output.getvalue().splitlines()]
        sample_row = next(row for row in rows if row["record"] == "sample")
        self.assertNotIn("sample_id", sample_row)
        self.assertEqual(sample_row["target"], {"latency_ms": 2.0})
        self.assertEqual(
            set(sample_row),
            {"record", "metric", "buffer_length", "sample", "warmup", "target"},
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
