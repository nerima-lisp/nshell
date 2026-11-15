#!/usr/bin/env python3
"""Exit-status tests of the shell entry points in scripts/perf.

compare.sh and noise.sh run with PYTHON pointing at a wrapper that answers the
perfharness.py call with a canned raw file, so no nshell is started.

Run: python3 -B scripts/perf/test_scripts.py
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from test_perfstats import BASE, raw, startup_metric  # noqa: E402

FAKE_PYTHON = """#!/bin/bash
if [[ ${2-} == */perfharness.py ]]; then
  while [[ $# -gt 0 ]]; do
    if [[ $1 == --out ]]; then cp "$CANNED_RAW" "$2"; fi
    shift
  done
  exit 0
fi
exec "%s" "$@"
""" % sys.executable


def run(script: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(script), *args], capture_output=True, text=True,
                          env={**os.environ, **(env or {})}, timeout=120)


class MissingValueTests(unittest.TestCase):
    def assert_usage(self, script: str, *args: str):
        result = run(HERE / script, *args)
        self.assertEqual(result.returncode, 2, f"{script} {args}: {result.stderr}")

    def test_compare_options_without_value(self):
        for option in ("--noise", "--out", "--base-src", "--cand-src", "--base-registry", "--cand-registry",
                       "--b3-blocks", "--harness-arg", "--note"):
            with self.subTest(option=option):
                self.assert_usage("compare.sh", option)
                self.assert_usage("compare.sh", option, "")

    def test_noise_options_without_value(self):
        for option in ("--out", "--src", "--harness-arg"):
            with self.subTest(option=option):
                self.assert_usage("noise.sh", option)
                self.assert_usage("noise.sh", option, "")

    def test_legacy_bench_bad_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assert_usage("legacy-bench.sh", "/nonexistent-tree", f"{directory}/out.jsonl")
            self.assert_usage("legacy-bench.sh", directory, "/nonexistent-dir/out.jsonl")
            self.assert_usage("legacy-bench.sh", directory)

    def test_b3_measure_bad_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assert_usage("b3-measure.sh", "/nonexistent-tree", f"{directory}/out.json")
            self.assert_usage("b3-measure.sh", directory, "/nonexistent-dir/out.json")
            self.assert_usage("b3-measure.sh", directory)


class OutcomeTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        python = self.directory / "python"
        python.write_text(FAKE_PYTHON, encoding="utf-8")
        python.chmod(0o755)
        self.canned = self.directory / "raw.json"
        self.env = {"PYTHON": str(python), "CANNED_RAW": str(self.canned)}

    def canned_raw(self, *metrics: dict) -> None:
        self.canned.write_text(json.dumps(raw(*metrics)), encoding="utf-8")

    def test_noise_run_with_unmeasured_gated_metric_is_inconclusive(self):
        guarded = startup_metric(BASE, list(BASE), name="startup.interactive_history_10k")
        guarded["guard_failures"] = ["A: history suggestion missing"]
        self.canned_raw(startup_metric(BASE, list(BASE)), guarded)
        out = self.directory / "noise"
        result = run(HERE / "noise.sh", "--out", str(out), "/usr/bin/true", env=self.env)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertTrue((out / "noise.json").exists())

    def test_complete_noise_run_succeeds(self):
        self.canned_raw(startup_metric(BASE, list(BASE)))
        out = self.directory / "noise"
        result = run(HERE / "noise.sh", "--out", str(out), "/usr/bin/true", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads((out / "noise.json").read_text())["complete"])

    def test_compare_with_noise_file_lacking_a_gated_metric_is_inconclusive(self):
        self.canned_raw(startup_metric(BASE, [value + 20 for value in BASE]))
        noise = self.directory / "noise.json"
        noise.write_text(json.dumps({"metrics": {}}), encoding="utf-8")
        result = run(HERE / "compare.sh", "--noise", str(noise), "--out", str(self.directory / "out"),
                     "/usr/bin/true", "/usr/bin/true", env=self.env)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)

    def test_requested_b3_without_measure_script_is_inconclusive(self):
        scripts = self.directory / "scripts"
        scripts.mkdir()
        for name in ("compare.sh", "perfstats.py"):
            shutil.copy2(HERE / name, scripts / name)
        self.canned_raw(startup_metric(BASE, list(BASE)))
        result = run(scripts / "compare.sh", "--base-src", str(self.directory), "--cand-src", str(self.directory),
                     "--out", str(self.directory / "out"), "/usr/bin/true", "/usr/bin/true", env=self.env)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
