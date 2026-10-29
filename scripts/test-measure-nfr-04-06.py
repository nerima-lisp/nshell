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


if __name__ == "__main__":
    unittest.main(verbosity=2)
