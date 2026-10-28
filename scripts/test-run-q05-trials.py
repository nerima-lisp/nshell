#!/usr/bin/env python3
"""Unit tests for Q05 trial recording and its required trial matrix."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("run-q05-trials.py")
SPEC = importlib.util.spec_from_file_location("run_q05_trials", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
q05 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(q05)


class Q05TrialTests(unittest.TestCase):
    def test_trial_matrix_has_three_baseline_and_thirty_delayed_fresh_processes(self) -> None:
        self.assertEqual(len(q05.CASES), 3)
        self.assertEqual(
            len(q05.CASES) * (q05.BASELINE_TRIALS + q05.DELAYED_TRIALS),
            33,
        )
        self.assertEqual(q05.BASELINE_TRIALS, 1)
        self.assertEqual(q05.DELAYED_TRIALS, 10)

    def test_passing_runner_result_records_duration_and_log(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log_dir = root / "trials"
            log_dir.mkdir()
            output = (
                "PASS Q05-nfs-git-prompt\n"
                "SCENARIO_SUMMARY selected=1 runs=1 pass=1 xfail=0 xpass=0 fail=0\n"
            )
            with (
                mock.patch.object(
                    q05, "_run", return_value=subprocess.CompletedProcess([], 0, output)
                ) as run,
                mock.patch.object(q05.time, "monotonic", side_effect=[10.0, 12.5]),
            ):
                result = q05._trial(
                    "baseline",
                    "prompt",
                    1,
                    "Q05-nfs-git-prompt",
                    "/mnt/q05/git",
                    root / "nshell",
                    root / "scenarios",
                    log_dir,
                )

            self.assertTrue(result["passed"])
            self.assertEqual(result["duration_seconds"], 2.5)
            self.assertEqual(result["exit_code"], 0)
            self.assertEqual(result["log"], "trials/baseline-prompt-trial-01.log")
            self.assertIn("--scenario-cwd", run.call_args.args[0])
            self.assertEqual((root / result["log"]).read_text(encoding="utf-8"), output)

    def test_trial_over_sixty_seconds_fails_even_when_scenario_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log_dir = root / "trials"
            log_dir.mkdir()
            output = "SCENARIO_SUMMARY selected=1 runs=1 pass=1 xfail=0 xpass=0 fail=0\n"
            with (
                mock.patch.object(
                    q05, "_run", return_value=subprocess.CompletedProcess([], 0, output)
                ),
                mock.patch.object(q05.time, "monotonic", side_effect=[10.0, 70.1]),
            ):
                result = q05._trial(
                    "delayed",
                    "glob",
                    1,
                    "Q05-nfs-glob-expansion",
                    "/mnt/q05/git",
                    root / "nshell",
                    root / "scenarios",
                    log_dir,
                )

        self.assertFalse(result["passed"])
        self.assertEqual(result["error"], "trial exceeded the 60-second cutoff")


if __name__ == "__main__":
    unittest.main()
