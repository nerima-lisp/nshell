#!/usr/bin/env python3
"""Tests of how perfharness.py records metrics it cannot measure.

A fake nshell (a bash script that prints the prompt and a frame end) stands in
for the binary, so no nshell build is needed. Needs a PTY.

Run: python3 -B scripts/perf/test_perfharness.py
"""

from __future__ import annotations

import argparse
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import perfharness  # noqa: E402
import perfstats  # noqa: E402

FAKE_NSHELL = r"""#!/bin/bash
case "${1-}" in
  --json) %(json)s ;;
  -c|--command) exit 0 ;;
esac
printf '%%s\033[0 q' "$NSHELL_PROMPT"
while IFS= read -r -n1 _; do printf 'NSHELL_P07_RECORD_\033[0 q'; done
"""
JSON_USAGE_ERROR = "printf 'Usage: nshell [OPTIONS]\\n' >&2; exit 1"
JSON_GARBLED = "printf 'not json\\n'; exit 0"
JSON_SLOW = "sleep 5; exit 0"
JSON_OK = "printf '{\"ok\":true}\\n'; exit 0"


def fake_binary(directory: Path, json_action: str, name: str = "nshell") -> Path:
    path = directory / name
    path.write_text(FAKE_NSHELL % {"json": json_action}, encoding="utf-8")
    path.chmod(0o755)
    return path


def harness_args(binary: Path) -> argparse.Namespace:
    # Startup only: one warm-up and one measured block.
    return argparse.Namespace(a=str(binary), b=str(binary), startup_blocks=1, key_blocks=0, path_key_blocks=0,
                              keys=2, warmup_keys=0, tab_blocks=0, tab_samples=1, prompt_blocks=0,
                              prompt_samples=1)


def judged_rows(raw: dict) -> dict:
    report = perfstats.build_report(raw, None, None, [], None)
    return {row["metric"]: row for row in report["rows"] if row["stat"] == "median"}


class ColdAndJsonTests(unittest.TestCase):
    def test_cold_setup_failure_and_garbled_json_are_inconclusive(self):
        # The fake is not a Nix wrapper, so the cold launcher cannot be built;
        # its --json prints non-JSON. Neither proves the feature is absent.
        with tempfile.TemporaryDirectory() as directory:
            raw = perfharness.run(harness_args(fake_binary(Path(directory), JSON_GARBLED)))
        self.assertNotIn("fatal_error", raw)
        rows = judged_rows(raw)
        cold = rows["startup.interactive_cold"]
        self.assertEqual(cold["verdict"], "inconclusive", cold)
        self.assertIn("exec -a", cold["reason"])
        json_row = rows["startup.json_command_true"]
        self.assertEqual(json_row["verdict"], "inconclusive", json_row)
        self.assertIn("JSON", json_row["reason"])
        self.assertEqual(rows["startup.command_true"]["groups"], {"A": 2, "B": 2})

    def test_json_usage_error_is_unsupported_with_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = perfharness.run(harness_args(fake_binary(Path(directory), JSON_USAGE_ERROR)))
        json_row = judged_rows(raw)["startup.json_command_true"]
        self.assertEqual(json_row["verdict"], "n/a", json_row)
        self.assertIn("usage error", json_row["reason"])


class JsonProbeTests(unittest.TestCase):
    def probe(self, action: str, timeout: float = perfharness.COMMAND_TIMEOUT):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "work").mkdir()
            return perfharness.json_support(fake_binary(root, action), {"work": root / "work"}, root, timeout)

    def test_supported(self):
        self.assertIsNone(self.probe(JSON_OK))

    def test_usage_error_is_unsupported(self):
        self.assertIn("usage error", self.probe(JSON_USAGE_ERROR))

    def test_garbled_output_is_a_measurement_failure(self):
        with self.assertRaises(perfharness.HarnessError):
            self.probe(JSON_GARBLED)

    def test_timeout_is_a_measurement_failure(self):
        with self.assertRaises(perfharness.HarnessError):
            self.probe(JSON_SLOW, timeout=0.5)

    def test_other_nonzero_exit_is_a_measurement_failure(self):
        with self.assertRaises(perfharness.HarnessError):
            self.probe("printf 'boom\\n' >&2; exit 1")


if __name__ == "__main__":
    unittest.main(verbosity=1)
