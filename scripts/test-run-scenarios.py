#!/usr/bin/env python3
"""Tests for scenario selection and validation."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch


RUNNER_PATH = Path(__file__).with_name("run-scenarios.py")
SPEC = importlib.util.spec_from_file_location("run_scenarios", RUNNER_PATH)
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def _batch_scenario(scenario_id: str, uc: str = "C01") -> dict[str, Any]:
    return {
        "id": scenario_id,
        "uc": [uc],
        "mode": "batch",
        "environment": {"home": "home", "cwd": "work"},
        "preconditions": {"files": []},
        "invocation": {"kind": "command", "text": "echo OK"},
        "expected": {"stdout": {"contains": ["OK"]}, "exit_code": 0},
    }


def _pty_scenario(
    scenario_id: str,
    steps: list[dict[str, Any]],
    expected: dict[str, Any],
    prompt: str = "TEST_PROMPT> ",
) -> dict[str, Any]:
    return {
        "id": scenario_id,
        "uc": ["C01"],
        "mode": "pty",
        "environment": {
            "home": "home",
            "cwd": "work",
            "variables": {"NSHELL_PROMPT": prompt},
        },
        "preconditions": {"files": []},
        "steps": steps,
        "expected": expected,
    }


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def _multi_pty_scenario(scenario_id: str = "shared-pty") -> dict[str, Any]:
    scenario = _pty_scenario(
        scenario_id,
        [],
        {"stream": {"contains": ["FIRST_SESSION_OUTPUT", "SECOND_SESSION_OUTPUT"]}, "exit_code": 0},
    )
    scenario.pop("steps")
    scenario["environment"]["variables"].pop("NSHELL_PROMPT")
    scenario["sessions"] = [
        {"id": "first", "prompt": "FIRST_PROMPT> ", "steps": [{"type": "wait_exit"}]},
        {"id": "second", "prompt": "SECOND_PROMPT> ", "steps": [{"type": "wait_exit"}]},
    ]
    return scenario


class ScenarioRunnerTests(unittest.TestCase):
    def test_batch_environment_appends_extra_path_after_scenario_path(self) -> None:
        scenario = _batch_scenario("batch-extra-path")
        scenario["environment"]["variables"] = {"PATH": "bin:/usr/bin:/bin"}

        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(runner.os.environ, {"NSHELL_SCENARIO_EXTRA_PATH": "/nix/tools/bin"}):
                env, _, _ = runner._environment(scenario, Path(temporary))

        self.assertEqual(env["PATH"], f"bin:/usr/bin:/bin{runner.os.pathsep}/nix/tools/bin")

    def test_batch_environment_can_disable_extra_path(self) -> None:
        scenario = _batch_scenario("batch-explicit-path")
        scenario["environment"]["variables"] = {"PATH": "bin:/usr/bin:/bin"}
        scenario["environment"]["append_extra_path"] = False

        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(runner.os.environ, {"NSHELL_SCENARIO_EXTRA_PATH": "/nix/tools/bin"}):
                env, _, _ = runner._environment(scenario, Path(temporary))

        self.assertEqual(env["PATH"], "bin:/usr/bin:/bin")

    def test_pty_environment_does_not_append_extra_path(self) -> None:
        scenario = _pty_scenario(
            "pty-extra-path",
            [{"type": "wait_exit"}],
            {"exit_code": 0},
        )
        scenario["environment"]["variables"]["PATH"] = "/usr/bin:/bin"

        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(runner.os.environ, {"NSHELL_SCENARIO_EXTRA_PATH": "/nix/tools/bin"}):
                env, _, _ = runner._environment(scenario, Path(temporary))

        self.assertEqual(env["PATH"], "/usr/bin:/bin")

    def test_load_config_controls_no_config_argument(self) -> None:
        binary = Path("/nix/store/nshell/bin/nshell")
        cases = [
            ({"load_config": True}, [str(binary)]),
            ({"load_config": False}, [str(binary), "--no-config"]),
            ({}, [str(binary), "--no-config"]),
        ]

        for scenario, expected in cases:
            with self.subTest(scenario=scenario):
                self.assertEqual(runner._nshell_command(binary, scenario), expected)

    def test_private_mode_adds_private_argument(self) -> None:
        binary = Path("/nix/store/nshell/bin/nshell")
        scenario = _pty_scenario("private", [{"type": "wait_exit"}], {"exit_code": 0})
        scenario["private_mode"] = True

        self.assertEqual(
            runner._nshell_command(binary, scenario),
            [str(binary), "--no-config", "--private"],
        )

    def test_multiple_sessions_validate_without_a_root_prompt(self) -> None:
        scenario = _multi_pty_scenario()

        self._load_one(scenario, "multi-pty.json")

    def test_multiple_sessions_start_before_any_steps_run_and_share_a_root(self) -> None:
        events: list[tuple[str, str, Path | None]] = []

        class FakeSession:
            def __init__(self, scenario: dict[str, Any], binary: Path, root: Path,
                         env: dict[str, str], cwd: Path):
                self.scenario = scenario
                session_name = scenario["id"].rsplit(":", 1)[-1].upper()
                self.stream = bytearray(f"{session_name}_SESSION_OUTPUT".encode())
                self.deadline_seconds = 45
                self.deadline = 0.0
                events.append(("start", scenario["id"], root))

            def wait_exit(self, timeout: float) -> int:
                events.append(("step", self.scenario["id"], None))
                return 0

            def drain(self) -> None:
                pass

            def capture_screen(self) -> str:
                return ""

            def close(self) -> None:
                events.append(("close", self.scenario["id"], None))

        scenario = _multi_pty_scenario()
        with patch.object(runner, "TmuxSession", FakeSession), patch.object(runner.shutil, "which", return_value="tmux"):
            stream, _, exit_code, failures = runner._run_pty(scenario, Path("/unused/nshell"))

        self.assertIn("FIRST_SESSION_OUTPUT", stream)
        self.assertIn("SECOND_SESSION_OUTPUT", stream)
        self.assertEqual(exit_code, 0)
        self.assertEqual(failures, [])
        starts = [event for event in events if event[0] == "start"]
        steps = [event for event in events if event[0] == "step"]
        self.assertEqual(len(starts), 2)
        self.assertEqual(len(steps), 2)
        self.assertLess(max(events.index(event) for event in starts), min(events.index(event) for event in steps))
        self.assertEqual(starts[0][2], starts[1][2])

    def test_multiple_sessions_reject_duplicate_prompts(self) -> None:
        scenario = _multi_pty_scenario()
        scenario["sessions"][1]["prompt"] = scenario["sessions"][0]["prompt"]

        with self.assertRaisesRegex(runner.ScenarioError, "prompts must be unique"):
            self._load_one(scenario, "duplicate-prompts.json")

    def test_tmux_exit_status_preserves_numeric_status_and_normalizes_signal(self) -> None:
        self.assertEqual(runner._pane_exit_status("23", "", "exit-status"), 23)
        self.assertEqual(runner._pane_exit_status("", "hup", "signal-exit"), 129)
        self.assertEqual(runner._pane_exit_status("", "term", "term-exit"), 143)

    def test_tmux_exit_status_rejects_missing_or_unknown_exit_information(self) -> None:
        for status, dead_signal, message in [
            ("", "", "invalid exit status"),
            ("", "unknown", "invalid exit signal"),
            ("invalid", "", "invalid exit status"),
        ]:
            with self.subTest(status=status, dead_signal=dead_signal):
                with self.assertRaisesRegex(runner.ScenarioError, message):
                    runner._pane_exit_status(status, dead_signal, "bad-exit")
    def _load_one(self, scenario: dict[str, Any], filename: str) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            _write_json(directory / filename, scenario)
            runner._load_scenarios(directory, scenario["mode"], {scenario["id"]})

    def test_t3_echo_only_input_is_rejected(self) -> None:
        scenario = _pty_scenario(
            "echo-only",
            [
                {"type": "keys", "text": "echo ECHO_ONLY_MARKER"},
                {"type": "wait", "contains": "ECHO_ONLY_MARKER"},
                {"type": "wait_exit"},
            ],
            {"stream": {"contains": ["ECHO_ONLY_MARKER"]}, "exit_code": 0},
        )
        with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
            self._load_one(scenario, "echo-only.json")

    def test_prompt_redraw_cannot_satisfy_pty_wait(self) -> None:
        scenario = _pty_scenario(
            "redraw-only",
            [
                {"type": "key", "key": "C-l"},
                {"type": "wait", "contains": "REDRAW_ONLY_PROMPT"},
                {"type": "wait_exit"},
            ],
            {"stream": {"contains": ["REDRAW_ONLY_PROMPT"]}, "exit_code": 0},
            prompt="REDRAW_ONLY_PROMPT> ",
        )
        with self.assertRaisesRegex(runner.ScenarioError, "prompt redraw"):
            self._load_one(scenario, "redraw-only.json")

    def test_printable_key_echo_cannot_satisfy_pty_wait(self) -> None:
        scenario = _pty_scenario(
            "printable-key-echo",
            [
                {"type": "key", "key": "z"},
                {"type": "wait", "contains": "z"},
                {"type": "wait_exit"},
            ],
            {"exit_code": 0},
        )
        with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
            self._load_one(scenario, "printable-key-echo.json")

    def test_space_key_echo_cannot_satisfy_pty_wait(self) -> None:
        scenario = _pty_scenario(
            "space-key-echo",
            [
                {"type": "key", "key": "Space"},
                {"type": "wait", "contains": " "},
                {"type": "wait_exit"},
            ],
            {"exit_code": 0},
            prompt="PROMPT>",
        )
        with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
            self._load_one(scenario, "space-key-echo.json")

    def test_space_key_echo_cannot_satisfy_positive_stream_expectation(self) -> None:
        scenario = _pty_scenario(
            "space-key-expectation",
            [{"type": "key", "key": "Space"}, {"type": "wait_exit"}],
            {"stream": {"contains": [" "]}, "exit_code": 0},
            prompt="PROMPT>",
        )
        with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
            self._load_one(scenario, "space-key-expectation.json")

    def test_tmux_key_echo_cannot_satisfy_pty_wait(self) -> None:
        cases = [
            ("Tab", "\t"),
            ("Enter", "\n"),
            ("BTab", "Z"),
            ("Up", "A"),
            ("F1", "P"),
            ("S-a", "A"),
            ("M-a", "a"),
        ]
        for key, marker in cases:
            with self.subTest(key=key):
                scenario = _pty_scenario(
                    f"{key}-echo",
                    [
                        {"type": "key", "key": key},
                        {"type": "wait", "contains": marker},
                        {"type": "wait_exit"},
                    ],
                    {"exit_code": 0},
                    prompt="PROMPT>",
                )
                with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
                    self._load_one(scenario, f"{key}-echo.json")

    def test_tmux_key_echo_cannot_satisfy_positive_stream_expectation(self) -> None:
        cases = [
            ("Tab", "\t"),
            ("Enter", "\n"),
            ("BTab", "Z"),
            ("Up", "A"),
            ("F1", "P"),
            ("S-a", "A"),
            ("M-a", "a"),
        ]
        for key, marker in cases:
            with self.subTest(key=key):
                scenario = _pty_scenario(
                    f"{key}-expectation",
                    [{"type": "key", "key": key}, {"type": "wait_exit"}],
                    {"stream": {"contains": [marker]}, "exit_code": 0},
                    prompt="PROMPT>",
                )
                with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
                    self._load_one(scenario, f"{key}-expectation.json")

    def test_prompt_redraw_cannot_satisfy_positive_stream_expectation(self) -> None:
        scenario = _pty_scenario(
            "redraw-only-expectation",
            [{"type": "key", "key": "C-l"}, {"type": "wait_exit"}],
            {"stream": {"contains": ["TEST_PROMPT"]}, "exit_code": 0},
        )
        with self.assertRaisesRegex(runner.ScenarioError, "prompt redraw"):
            self._load_one(scenario, "redraw-only-expectation.json")

    def test_shell_output_only_marker_is_allowed(self) -> None:
        scenario = _pty_scenario(
            "shell-output-marker",
            [
                {"type": "keys", "text": "cat answer.txt"},
                {"type": "key", "key": "Enter"},
                {"type": "wait", "contains": "SHELL_OUTPUT_MARKER"},
                {"type": "wait_exit"},
            ],
            {"stream": {"contains": ["SHELL_OUTPUT_MARKER"]}, "exit_code": 0},
        )
        runner._validate_scenario(scenario, Path("shell-output-marker.json"))

    def test_exit_code_is_required_for_batch_and_pty(self) -> None:
        batch = _batch_scenario("batch-missing-exit-code")
        batch["expected"].pop("exit_code")
        scenarios = [
            batch,
            _pty_scenario(
                "pty-missing-exit-code",
                [{"type": "wait_exit"}],
                {"stream": {"contains": ["OUTPUT"]}},
            ),
        ]
        for scenario in scenarios:
            with self.subTest(mode=scenario["mode"]):
                with self.assertRaisesRegex(runner.ScenarioError, "expected.exit_code is required"):
                    self._load_one(scenario, f"{scenario['id']}.json")

    def test_full_selection_matches_manifest_paths_ids_and_uc_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            scenarios = [
                ("C01/first.json", _batch_scenario("C01-first")),
                ("C02/second.json", _batch_scenario("C02-second", "C02")),
            ]
            entries = []
            for relative_path, scenario in scenarios:
                _write_json(directory / relative_path, scenario)
                entries.append({
                    "id": scenario["id"],
                    "uc": scenario["uc"],
                    "path": relative_path,
                })
            _write_json(
                directory / runner.EXPECTED_SCENARIOS_FILE,
                {"version": 1, "scenarios": entries},
            )

            selected = runner._load_scenarios(directory, "all", set())

        self.assertEqual({scenario["id"] for scenario in selected}, {"C01-first", "C02-second"})

    def test_repository_full_corpus_matches_manifest(self) -> None:
        scenarios = runner._load_scenarios(runner.DEFAULT_SCENARIO_DIR, "all", set())

        self.assertTrue(scenarios)

    def test_full_selection_rejects_scenario_id_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            scenario = _batch_scenario("C01-renamed")
            _write_json(directory / "C01/first.json", scenario)
            _write_json(
                directory / runner.EXPECTED_SCENARIOS_FILE,
                {
                    "version": 1,
                    "scenarios": [{"id": "C01-first", "uc": ["C01"], "path": "C01/first.json"}],
                },
            )

            with self.assertRaisesRegex(runner.ScenarioError, "scenario id set"):
                runner._load_scenarios(directory, "all", set())

    def test_full_selection_rejects_scenario_file_set_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            first = _batch_scenario("C01-first")
            second = _batch_scenario("C01-second")
            _write_json(directory / "C01/first.json", first)
            _write_json(directory / "C01/second.json", second)
            _write_json(
                directory / runner.EXPECTED_SCENARIOS_FILE,
                {"version": 1, "scenarios": [{"id": first["id"], "uc": first["uc"], "path": "C01/first.json"}]},
            )

            with self.assertRaisesRegex(runner.ScenarioError, "scenario file set"):
                runner._load_scenarios(directory, "all", set())

    def test_full_selection_rejects_uc_mapping_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            scenario = _batch_scenario("C02-second", "C02")
            _write_json(directory / "C02/second.json", scenario)
            _write_json(
                directory / runner.EXPECTED_SCENARIOS_FILE,
                {
                    "version": 1,
                    "scenarios": [{"id": scenario["id"], "uc": ["C01"], "path": "C02/second.json"}],
                },
            )

            with self.assertRaisesRegex(runner.ScenarioError, "uc was"):
                runner._load_scenarios(directory, "all", set())

    def test_filtered_selection_does_not_require_full_corpus_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            batch = _batch_scenario("batch-only")
            pty = _pty_scenario(
                "pty-only",
                [{"type": "wait_exit"}],
                {"stream": {"contains": ["OUTPUT"]}, "exit_code": 0},
            )
            _write_json(directory / "C01/batch.json", batch)
            _write_json(directory / "C01/pty.json", pty)

            batch_only = runner._load_scenarios(directory, "batch", set())
            id_only = runner._load_scenarios(directory, "all", {"pty-only"})

        self.assertEqual([scenario["id"] for scenario in batch_only], ["batch-only"])
        self.assertEqual([scenario["id"] for scenario in id_only], ["pty-only"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
