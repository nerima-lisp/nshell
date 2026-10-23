#!/usr/bin/env python3
"""Tests for scenario selection and validation."""

from __future__ import annotations

import importlib.util
import json
import shlex
import tempfile
import unittest
from pathlib import Path
from typing import Any


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


class ScenarioRunnerTests(unittest.TestCase):
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

    def test_argv_batch_invocation_preserves_arguments_and_stdin(self) -> None:
        arguments = [
            "-ilc",
            "",
            "zero with spaces",
            "single' and \"double\" quotes",
            "line one\nline two",
            "--",
            "-leading",
        ]
        scenario = _batch_scenario("argv-batch")
        scenario["invocation"] = {
            "kind": "argv",
            "arguments": arguments,
            "stdin": "stdin line\n",
        }

        actual_arguments, actual_stdin = runner._binary_args(scenario, Path("/scenario/work"))

        self.assertEqual(actual_arguments, arguments)
        self.assertEqual(actual_stdin, b"stdin line\n")

    def test_command_invocation_uses_the_long_nshell_command_option(self) -> None:
        scenario = _batch_scenario("command-option")

        arguments, stdin = runner._binary_args(scenario, Path("/scenario/work"))

        self.assertEqual(arguments, ["--no-config", "--command", "echo OK"])
        self.assertEqual(stdin, b"")

    def test_pty_arguments_survive_tmux_shell_quoting(self) -> None:
        arguments = ["-c", "", "zero with spaces", "line one\nline two", "--", "-leading"]
        environment = {"PATH": "/usr/bin:/bin", "R04_VALUE": "space and $()"}
        shell_command = runner._pty_shell_command(Path("/tmp/nshell binary"), environment, arguments)

        self.assertTrue(shell_command.startswith("exec "))
        self.assertEqual(
            shlex.split(shell_command.removeprefix("exec ")),
            [
                "/usr/bin/env",
                "-i",
                "PATH=/usr/bin:/bin",
                "R04_VALUE=space and $()",
                "/tmp/nshell binary",
                *arguments,
            ],
        )

    def test_pty_arguments_default_to_no_config(self) -> None:
        scenario = _pty_scenario("pty-default-arguments", [{"type": "wait_exit"}], {"exit_code": 0})

        self.assertEqual(runner._pty_arguments(scenario), ["--no-config"])

    def test_pty_arguments_preserve_exact_arguments_and_config_choice(self) -> None:
        scenario = _pty_scenario("pty-arguments", [{"type": "wait_exit"}], {"exit_code": 0})
        arguments = ["-ilc", "env", "", "value with spaces", "--"]
        scenario["arguments"] = arguments

        self.assertEqual(runner._pty_arguments(scenario), ["--no-config", *arguments])

        scenario["load_config"] = True
        self.assertEqual(runner._pty_arguments(scenario), arguments)

    def test_argv_batch_validation_rejects_non_string_arguments(self) -> None:
        scenario = _batch_scenario("argv-invalid")
        scenario["invocation"] = {"kind": "argv", "arguments": ["-c", None]}

        with self.assertRaisesRegex(runner.ScenarioError, "array of strings"):
            runner._validate_scenario(scenario, Path("argv-invalid.json"))

    def test_pty_validation_rejects_non_string_arguments(self) -> None:
        scenario = _pty_scenario(
            "pty-argv-invalid",
            [{"type": "wait_exit"}],
            {"exit_code": 0},
        )
        scenario["arguments"] = ["-ilc", 1]

        with self.assertRaisesRegex(runner.ScenarioError, "pty arguments must be an array of strings"):
            runner._validate_scenario(scenario, Path("pty-argv-invalid.json"))

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
