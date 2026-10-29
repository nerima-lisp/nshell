#!/usr/bin/env python3
"""Tests for scenario selection and validation."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import stat
import subprocess
import sys
import shlex
import stat
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock
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


def _run_main_for_pty_scenario(
    scenario: dict[str, Any],
    timeout_at: str | None,
) -> tuple[int, str]:
    real_session = runner.TmuxSession

    class FakeSession:
        def __init__(self, session_scenario: dict[str, Any], *_args: Any):
            self.scenario = session_scenario
            self.stream = bytearray()
            self.visible_screen_snapshots: list[str] = []
            self.deadline_seconds = 45
            self.deadline = 0.0
            self.exit_waiter = mock.Mock()
            self.exit_waiter.poll.return_value = None

        def wait_for(self, text: str, start: int, timeout: float) -> int:
            if timeout_at == "wait":
                self.deadline = 0
                return real_session.wait_for(self, text, start, timeout)
            return 0

        def send_text(self, _text: str) -> None:
            pass

        def take_wait_start(self) -> int:
            return len(self.stream)

        def wait_after_input(self, _delay: float) -> None:
            pass

        def wait_for_screen(self, text: str | None, timeout: float,
                            excludes: list[str] | None = None) -> str | None:
            if timeout_at == "wait_screen":
                self.deadline = 0
                return real_session.wait_for_screen(self, text, timeout, excludes)
            return None

        def wait_for_input(self, text: str, timeout: float) -> str | None:
            if timeout_at == "wait_input":
                self.deadline = 0
                return real_session.wait_for_screen(self, text, timeout)
            return None

        def wait_exit(self, timeout: float) -> int:
            if timeout_at == "wait_exit":
                self.deadline = 0
                return real_session.wait_exit(self, timeout)
            return 0

        def _capture(self) -> str:
            return ""

        def drain(self) -> None:
            pass

        def capture_screen(self) -> str:
            return ""

        def capture_styled_screen(self) -> str:
            self.visible_screen_snapshots.append("")
            return ""

        def _capture(self) -> str:
            return ""

        @staticmethod
        def _validate_timeout(value: Any, scenario_id: str) -> None:
            real_session._validate_timeout(value, scenario_id)

        def close(self) -> None:
            pass

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        scenario_dir = root / "scenarios"
        _write_json(scenario_dir / "J99/test.json", scenario)
        binary = root / "nshell"
        binary.write_text("placeholder", encoding="utf-8")
        binary.chmod(0o755)
        output = io.StringIO()
        argv = [
            "run-scenarios.py", "--binary", str(binary), "--scenario-dir", str(scenario_dir),
            "--mode", "pty", "--scenario-id", scenario["id"],
        ]
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(runner, "TmuxSession", FakeSession),
            mock.patch.object(runner.shutil, "which", return_value="tmux"),
            contextlib.redirect_stdout(output),
        ):
            exit_code = runner.main()

    return exit_code, output.getvalue()


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
    def test_pty_stream_assertions_tolerate_sgr_and_preserve_style_checks(self) -> None:
        scenario = _pty_scenario(
            "colored-autosuggestion",
            [],
            {
                "stream": {
                    "contains": [
                        "I01_HISTORY_SUGGESTION",
                        "\x1b[38;5;242m",
                    ],
                    "ordered_contains": [
                        "I01_HISTORY_SUGGESTION",
                        "\x1b[0m",
                    ],
                }
            },
        )

        failures = runner._check_expected(
            scenario,
            "I01_HISTORY\x1b[38;5;242m_SUGGESTION\x1b[0m",
            "",
            0,
            Path("."),
            Path("."),
        )

        self.assertEqual([], failures)


    def test_pty_stream_assertions_reject_sgr_conceal(self) -> None:
        marker = "I01_HISTORY_SUGGESTION"
        scenario = _pty_scenario(
            "concealed-autosuggestion",
            [],
            {"stream": {"contains": [marker]}},
        )
        concealed_streams = (
            "I01_HISTORY\x1b[8m_SUGGESTION\x1b[0m",
            "I01_HISTORY\x1b[0;8m_SUGGESTION\x1b[0m",
            "\x1b[8mI01_HISTORY_SUGGESTION\x1b[0m",
        )

        for actual in concealed_streams:
            with self.subTest(actual=actual):
                failures = runner._check_expected(
                    scenario,
                    actual,
                    "",
                    0,
                    Path("."),
                    Path("."),
                    visible_screen_snapshots=(actual,),
                )
                self.assertTrue(any(f"did not contain {marker!r}" in failure for failure in failures))

        visible_after_reveal = runner._check_expected(
            scenario,
            f"\x1b[8m\x1b[28m{marker}\x1b[0m",
            "",
            0,
            Path("."),
            Path("."),
        )
        self.assertEqual([], visible_after_reveal)

        color_index_eight = runner._check_expected(
            scenario,
            "I01_HISTORY\x1b[38;5;8m_SUGGESTION\x1b[0m",
            "",
            0,
            Path("."),
            Path("."),
        )
        self.assertEqual([], color_index_eight)

    def test_pty_stream_assertions_use_visible_reverse_video_screen_snapshot(self) -> None:
        marker = "Verbose output"
        scenario = _pty_scenario(
            "reverse-video-completion-description",
            [],
            {"stream": {"contains": [marker]}},
        )
        screen = f"\x1b[7m{marker}\x1b[0m"

        failures = runner._check_expected(
            scenario,
            screen,
            "",
            0,
            Path("."),
            Path("."),
            visible_screen_snapshots=(screen,),
        )

        self.assertEqual([], failures)
        failures_without_screen_evidence = runner._check_expected(
            scenario,
            screen,
            "",
            0,
            Path("."),
            Path("."),
        )
        self.assertTrue(
            any(f"did not contain {marker!r}" in failure
                for failure in failures_without_screen_evidence)
        )
        self.assertNotIn(marker, runner._visible_screen_text(f"\x1b[8m{marker}\x1b[0m"))
        self.assertNotIn("AB", runner._visible_screen_text("A\x1b[8mhidden\x1b[0mB"))

    def test_pty_ordered_assertions_do_not_join_separate_screen_snapshots(self) -> None:
        scenario = _pty_scenario(
            "ordered-markers-in-separate-screens",
            [],
            {"stream": {"ordered_contains": ["FIRST", "SECOND"]}},
        )

        failures = runner._check_expected(
            scenario,
            "\x1b[7mSECOND\x1b[0m then \x1b[7mFIRST\x1b[0m\n"
            "\x1b[7mSECOND\x1b[0m then \x1b[7mFIRST\x1b[0m",
            "",
            0,
            Path("."),
            Path("."),
            visible_screen_snapshots=(
                "\x1b[7mSECOND then FIRST\x1b[0m",
                "\x1b[7mSECOND then FIRST\x1b[0m",
            ),
        )

        self.assertTrue(
            any("did not contain 'FIRST' in the required order" in failure
                for failure in failures)
        )

    def test_pty_text_assertions_reject_whitespace_only_markers(self) -> None:
        for key in ("contains", "excludes", "ordered_contains"):
            with self.subTest(key=key):
                scenario = _pty_scenario(
                    "whitespace-only-marker",
                    [],
                    {"stream": {key: [" "]}},
                )
                with self.assertRaisesRegex(
                    runner.ScenarioError,
                    "must contain non-whitespace text",
                ):
                    runner._check_expected(
                        scenario,
                        "",
                        "",
                        0,
                        Path("."),
                        Path("."),
                        visible_screen_snapshots=("\x1b[8msecret\x1b[0m",),
                    )

    def test_capture_styled_screen_does_not_record_error_sentinel_as_evidence(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.pane = "%1"
        session.visible_screen_snapshots = []

        with patch.object(session, "_tmux", side_effect=runner.ScenarioError("pane vanished")):
            screen = session.capture_styled_screen()

        self.assertEqual("<pane no longer available>", screen)
        self.assertEqual([], session.visible_screen_snapshots)

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

    def test_multiple_sessions_allow_live_screen_with_exit_status_session(self) -> None:
        scenario = _multi_pty_scenario("mixed-live-pty")
        scenario["sessions"][0]["steps"] = [
            {"type": "wait", "contains": "LIVE_PAGER"},
        ]
        scenario["expected"]["screen"] = {"contains": ["LIVE_PAGER"]}

        self._load_one(scenario, "mixed-live-pty.json")

    def test_live_pty_session_requires_screen_assertion(self) -> None:
        scenario = _multi_pty_scenario("live-pty-without-screen")
        scenario["sessions"][0]["steps"] = [
            {"type": "wait", "contains": "LIVE_PAGER"},
        ]

        with self.assertRaisesRegex(runner.ScenarioError, "expected.screen assertion"):
            self._load_one(scenario, "live-pty-without-screen.json")

    def test_pty_exit_code_rejects_all_live_sessions(self) -> None:
        scenario = _multi_pty_scenario("all-live-pty")
        scenario["expected"]["screen"] = {"contains": ["LIVE_PAGER"]}
        for session in scenario["sessions"]:
            session["steps"] = [{"type": "wait", "contains": "LIVE_PAGER"}]

        with self.assertRaisesRegex(runner.ScenarioError, "at least one final wait_exit step"):
            self._load_one(scenario, "all-live-pty.json")

    def test_pty_resize_dimensions_are_bounded_integers(self) -> None:
        scenario = _pty_scenario(
            "resize-dimensions",
            [{"type": "resize", "columns": 1, "rows": 512}, {"type": "wait_exit"}],
            {"exit_code": 0},
        )
        self._load_one(scenario, "resize-dimensions.json")

        for dimension, value in (("columns", 0), ("rows", 513), ("columns", True)):
            with self.subTest(dimension=dimension, value=value):
                scenario["steps"][0] = {"type": "resize", "columns": 1, "rows": 512}
                scenario["steps"][0][dimension] = value
                with self.assertRaisesRegex(runner.ScenarioError, f"resize.{dimension}"):
                    self._load_one(scenario, "resize-dimensions.json")
        scenario["steps"][0]["columns"] = 1
        scenario["steps"][0]["rows"] = 512

    def test_pty_resize_dispatch_preserves_exit_status(self) -> None:
        events: list[tuple[str, Any]] = []

        class FakeSession:
            def __init__(self, scenario: dict[str, Any], binary: Path, root: Path,
                         env: dict[str, str], cwd: Path):
                self.scenario = scenario
                self.stream = bytearray()
                self.visible_screen_snapshots: list[str] = []
                self.deadline_seconds = 45
                self.deadline = 0.0

            def resize(self, columns: int, rows: int) -> None:
                events.append(("resize", (columns, rows)))

            def send_text(self, text: str) -> None:
                events.append(("keys", text))

            def send_key(self, key: str) -> None:
                events.append(("key", key))

            def wait_after_input(self, delay: float) -> None:
                events.append(("delay", delay))

            def wait_for_screen(self, text: str | None, timeout: float,
                                excludes: list[str] | None = None) -> None:
                events.append(("wait_screen", (text, timeout, excludes or [])))

            def wait_for_input(self, text: str, timeout: float) -> None:
                events.append(("wait_input", (text, timeout)))

            def wait_exit(self, timeout: float) -> int:
                events.append(("wait_exit", timeout))
                return 23

            def drain(self) -> None:
                pass

            def capture_screen(self) -> str:
                return ""

            def capture_styled_screen(self) -> str:
                self.visible_screen_snapshots.append("")
                return ""

            def close(self) -> None:
                pass

        scenario = _pty_scenario(
            "resize-dispatch",
            [
                {"type": "keys", "text": "before"},
                {"type": "key", "key": "C-c", "input_delay_seconds": 0},
                {"type": "keys", "text": "after"},
                {"type": "wait_input", "contains": "after", "timeout_seconds": 6},
                {"type": "resize", "columns": 24, "rows": 20},
                {"type": "wait_screen", "contains": "VISIBLE_SCREEN", "excludes": ["STALE_SCREEN"],
                 "timeout_seconds": 6},
                {"type": "wait_exit", "timeout_seconds": 8},
            ],
            {"exit_code": 23},
        )
        scenario["input_delay_seconds"] = 0.5
        with patch.object(runner, "TmuxSession", FakeSession), \
                patch.object(runner.shutil, "which", return_value="tmux"):
            _, _, exit_code, failures = runner._run_pty(scenario, Path("/unused/nshell"))

        self.assertEqual(events, [
            ("keys", "before"),
            ("delay", 0.5),
            ("key", "C-c"),
            ("delay", 0),
            ("keys", "after"),
            ("delay", 0.5),
            ("wait_input", ("after", 6)),
            ("resize", (24, 20)),
            ("wait_screen", ("VISIBLE_SCREEN", 6, ["STALE_SCREEN"])),
            ("wait_exit", 8),
        ])
        self.assertEqual(exit_code, 23)
        self.assertEqual(failures, [])

    def test_tmux_resize_invokes_window_resize(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.pane = "%7"
        session.stream = bytearray()
        session.pending_wait_start = None

        with patch.object(session, "_tmux") as tmux:
            session.resize(90, 31)

        tmux.assert_called_once_with([
            "resize-window", "-t", "%7", "-x", "90", "-y", "31",
        ])

    def test_tmux_wait_for_screen_polls_until_marker_is_visible(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.deadline = 10.0
        session.scenario = {"id": "screen-wait"}
        session.exit_waiter = None

        with (
            patch.object(runner.time, "monotonic", side_effect=[1.0, 1.05]),
            patch.object(session, "_capture", side_effect=["initial screen", "VISIBLE_SCREEN"]) as capture,
            patch.object(session, "_read") as read,
        ):
            session.wait_for_screen("VISIBLE_SCREEN", 1)

        self.assertEqual(capture.call_count, 2)
        read.assert_called_once_with(0.1)

    def test_tmux_wait_for_input_polls_until_typed_input_is_visible(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.deadline = 10.0
        session.scenario = {"id": "input-wait"}
        session.exit_waiter = None

        with (
            patch.object(runner.time, "monotonic", side_effect=[1.0, 1.05]),
            patch.object(session, "_capture", side_effect=["initial screen", "TYPED_INPUT"]) as capture,
            patch.object(session, "_read") as read,
        ):
            session.wait_for_input("TYPED_INPUT", 1)

        self.assertEqual(capture.call_count, 2)
        read.assert_called_once_with(0.1)

    def test_pty_wait_uses_output_since_input_was_sent(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.stream = bytearray(b"startup")
        session.pending_wait_start = None
        session.pane = "%1"
        session.scenario = {"id": "wait-after-input"}
        session.deadline = runner.time.monotonic() + 1

        with patch.object(runner.TmuxSession, "_tmux"):
            session.send_key("C-c")
        session.stream.extend(b"\x1b[0 q")

        self.assertEqual(
            len(b"startup\x1b[0 q"),
            session.wait_for("\x1b[0 q", session.take_wait_start(), 1),
        )
        self.assertEqual(len(session.stream), session.take_wait_start())

    def test_tmux_wait_for_screen_polls_until_excluded_text_disappears(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.deadline = 10.0
        session.scenario = {"id": "screen-clears"}
        session.exit_waiter = None

        with (
            patch.object(runner.time, "monotonic", side_effect=[1.0, 1.05]),
            patch.object(session, "_capture", side_effect=["STALE_INPUT", "PROMPT> "]) as capture,
            patch.object(session, "_read") as read,
        ):
            session.wait_for_screen(None, 1, ["STALE_INPUT"])

        self.assertEqual(capture.call_count, 2)
        read.assert_called_once_with(0.1)

    def test_tmux_wait_for_screen_times_out_while_excluded_text_remains(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.deadline = 10.0
        session.scenario = {"id": "screen-stays-stale"}
        session.exit_waiter = None

        with (
            patch.object(runner.time, "monotonic", side_effect=[1.0, 1.3]),
            patch.object(session, "_capture", return_value="STALE_INPUT"),
            patch.object(session, "_read") as read,
        ):
            with self.assertRaisesRegex(runner.ScenarioTimeout, "current screen:\\nSTALE_INPUT"):
                session.wait_for_screen(None, 0.2, ["STALE_INPUT"])

        read.assert_not_called()

    def test_tmux_wait_for_screen_reports_pane_exit_before_marker(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.deadline = 10.0
        session.scenario = {"id": "screen-exit"}
        session.exit_waiter = mock.Mock()
        session.exit_waiter.poll.return_value = 1

        with (
            patch.object(runner.time, "monotonic", return_value=1.0),
            patch.object(session, "_capture", side_effect=["initial screen", "L07 fatal error"]) as capture,
            patch.object(session, "_read") as read,
        ):
            failure = session.wait_for_screen("EXPECTED_SCREEN", 5)

        self.assertIsNotNone(failure)
        self.assertIn("pane exited before", failure)
        self.assertIn("EXPECTED_SCREEN", failure)
        self.assertIn("L07 fatal error", failure)
        self.assertEqual(capture.call_count, 2)
        read.assert_called_once_with(0)

    def test_dead_pane_screen_wait_is_classified_as_expected_failure(self) -> None:
        events: list[tuple[str, Any]] = []

        class FakeSession:
            def __init__(self, scenario: dict[str, Any], binary: Path, root: Path,
                         env: dict[str, str], cwd: Path):
                self.scenario = scenario
                self.stream = bytearray()
                self.visible_screen_snapshots: list[str] = []
                self.deadline_seconds = 45
                self.deadline = 0.0

            def wait_for_screen(self, text: str | None, timeout: float,
                                excludes: list[str] | None = None) -> str:
                events.append(("wait_screen", (text, timeout)))
                return f"{self.scenario['id']}: pane exited before screen conditions were met"

            def wait_exit(self, timeout: float) -> int:
                events.append(("wait_exit", timeout))
                return 1

            def drain(self) -> None:
                pass

            def capture_screen(self) -> str:
                return "L07 fatal error"

            def capture_styled_screen(self) -> str:
                self.visible_screen_snapshots.append("")
                return ""

            def close(self) -> None:
                pass

        scenario = _pty_scenario(
            "expected-screen-failure",
            [
                {"type": "wait_screen", "contains": "STRUCTURAL_RESULT"},
                {"type": "keys", "text": "must not be sent"},
                {"type": "wait_exit", "timeout_seconds": 8},
            ],
            {"exit_code": 0},
        )
        scenario["expected_failure"] = {"reason": "WP-L07 has not implemented the scanner registry"}

        with patch.object(runner, "TmuxSession", FakeSession), \
                patch.object(runner.shutil, "which", return_value="tmux"):
            status, detail = runner._run_once(scenario, Path("/unused/nshell"))

        self.assertEqual(status, "XFAIL")
        self.assertIn("WP-L07", detail)
        self.assertEqual(events, [
            ("wait_screen", ("STRUCTURAL_RESULT", 10)),
            ("wait_exit", 8),
        ])

    def test_tmux_wait_exit_drains_output_while_waiting_for_pane_death(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.deadline = runner.time.monotonic() + 1
        session.scenario = {"id": "exit-wait"}
        session.pane = "%7"

        class WaitingProcess:
            returncode: int | None = None

            def poll(self) -> int | None:
                return self.returncode

            def communicate(self, *_args: Any, **_kwargs: Any) -> tuple[bytes, bytes]:
                self.returncode = 0
                return b"", b""

        waiter = WaitingProcess()
        session.exit_waiter = waiter
        reads: list[float] = []

        def read(timeout: float) -> bytes:
            reads.append(timeout)
            if timeout > 0:
                waiter.returncode = 0
                return b"Goodbye!"
            return b""

        with (
            patch.object(session, "_read", side_effect=read),
            patch.object(session, "_tmux", return_value=subprocess.CompletedProcess(
                [], 0, stdout=b"0 \n", stderr=b"")) as tmux,
        ):
            status = session.wait_exit(1)

        self.assertEqual(status, 0)
        self.assertEqual(len(reads), 2)
        self.assertGreater(reads[0], 0)
        self.assertEqual(reads[1], 0)
        tmux.assert_called_once_with([
            "display-message", "-p", "-t", "%7", "#{pane_dead_status} #{pane_dead_signal}",
        ])

    def test_multiple_sessions_start_before_any_steps_run_and_share_a_root(self) -> None:
        events: list[tuple[str, str, Path | None]] = []

        class FakeSession:
            def __init__(self, scenario: dict[str, Any], binary: Path, root: Path,
                         env: dict[str, str], cwd: Path):
                self.scenario = scenario
                session_name = scenario["id"].rsplit(":", 1)[-1].upper()
                self.stream = bytearray(f"{session_name}_SESSION_OUTPUT".encode())
                self.visible_screen_snapshots: list[str] = []
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

            def capture_styled_screen(self) -> str:
                self.visible_screen_snapshots.append("")
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

    def test_precondition_executable_fixture_is_written_executable(self) -> None:
        scenario = _batch_scenario("executable-fixture")
        scenario["preconditions"]["files"] = [
            {"path": "home/bin/env", "content": "#!/bin/sh\n", "executable": True}
        ]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "home/bin/env"
            runner._write_preconditions(scenario, Path(temporary))
            self.assertEqual(path.read_text(encoding="utf-8"), "#!/bin/sh\n")
            self.assertTrue(path.stat().st_mode & stat.S_IXUSR)

    def test_precondition_executable_must_be_boolean(self) -> None:
        scenario = _batch_scenario("invalid-executable-fixture")
        scenario["preconditions"]["files"] = [
            {"path": "home/bin/env", "content": "", "executable": "yes"}
        ]
        with self.assertRaisesRegex(runner.ScenarioError, "executable must be a boolean"):
            self._load_one(scenario, "invalid-executable-fixture.json")

    def _load_one(self, scenario: dict[str, Any], filename: str) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            _write_json(directory / filename, scenario)
            runner._load_scenarios(directory, scenario["mode"], {scenario["id"]})

    def test_pty_input_delay_is_bounded_by_delay_and_scenario_deadline(self) -> None:
        scenario = _pty_scenario(
            "paced-input",
            [{"type": "keys", "text": "echo PACED_INPUT"}, {"type": "wait_exit"}],
            {"exit_code": 0},
        )
        scenario["input_delay_seconds"] = 0.12
        self._load_one(scenario, "paced-input.json")

        scenario["input_delay_seconds"] = runner.MAX_INPUT_DELAY_SECONDS + 0.01
        with self.assertRaisesRegex(runner.ScenarioError, "input_delay_seconds"):
            self._load_one(scenario, "paced-input.json")

        scenario["input_delay_seconds"] = 0.6
        scenario["steps"] = [
            {"type": "keys", "text": "first", "input_delay_seconds": 0.8},
            {"type": "key", "key": "C-c", "input_delay_seconds": 0},
            {"type": "wait_exit"},
        ]
        scenario["timeout_seconds"] = 1.2
        self._load_one(scenario, "paced-input.json")

        scenario["steps"][0]["input_delay_seconds"] = runner.MAX_INPUT_DELAY_SECONDS + 0.01
        with self.assertRaisesRegex(runner.ScenarioError, "step input_delay_seconds"):
            self._load_one(scenario, "paced-input.json")

        scenario["steps"][0].pop("input_delay_seconds")

        scenario["steps"] = [
            {"type": "keys", "text": "first"},
            {"type": "keys", "text": "second"},
            {"type": "wait_exit"},
        ]
        scenario["input_delay_seconds"] = 0.6
        scenario["timeout_seconds"] = 1.2
        with self.assertRaisesRegex(runner.ScenarioError, "fit within timeout_seconds"):
            self._load_one(scenario, "paced-input.json")

    def test_pty_wait_input_requires_and_allows_matching_typed_input(self) -> None:
        scenario = _pty_scenario(
            "typed-input-wait",
            [
                {"type": "keys", "text": "suffix TYPED_INPUT"},
                {"type": "wait_input", "contains": "TYPED_INPUT", "timeout_seconds": 5},
                {"type": "wait_exit"},
            ],
            {"exit_code": 0},
        )
        self._load_one(scenario, "typed-input-wait.json")

        scenario["steps"][0]["text"] = "suffix OTHER_INPUT"
        with self.assertRaisesRegex(runner.ScenarioError, "must match preceding typed input"):
            self._load_one(scenario, "typed-input-wait.json")

    def test_pty_wait_input_does_not_allow_input_echo_as_output(self) -> None:
        scenario = _pty_scenario(
            "typed-input-is-not-output",
            [
                {"type": "keys", "text": "echo INPUT_OUTPUT_OVERLAP"},
                {"type": "wait_input", "contains": "INPUT_OUTPUT_OVERLAP"},
                {"type": "wait_exit"},
            ],
            {"stream": {"contains": ["INPUT_OUTPUT_OVERLAP"]}, "exit_code": 0},
        )

        with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
            self._load_one(scenario, "typed-input-is-not-output.json")

    def test_pty_input_delay_checks_remaining_deadline(self) -> None:
        session = runner.TmuxSession.__new__(runner.TmuxSession)
        session.deadline = 10.0
        session.scenario = {"id": "paced-input"}

        with (
            patch.object(runner.time, "monotonic", side_effect=[9.0, 10.0]),
            patch.object(runner.time, "sleep") as sleep,
            patch.object(runner.TmuxSession, "capture_screen") as capture_screen,
        ):
            with self.assertRaisesRegex(runner.ScenarioError, "input delay exceeded scenario deadline"):
                session.wait_after_input(0.5)

        sleep.assert_called_once_with(0.5)
        capture_screen.assert_not_called()

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

    def test_prompt_redraw_cannot_satisfy_pty_screen_wait(self) -> None:
        scenario = _pty_scenario(
            "screen-redraw-only",
            [
                {"type": "key", "key": "C-l"},
                {"type": "wait_screen", "contains": "SCREEN_PROMPT"},
                {"type": "wait_exit"},
            ],
            {"exit_code": 0},
            prompt="SCREEN_PROMPT> ",
        )
        with self.assertRaisesRegex(runner.ScenarioError, "prompt redraw"):
            self._load_one(scenario, "screen-redraw-only.json")

    def test_input_echo_cannot_satisfy_pty_screen_wait(self) -> None:
        scenario = _pty_scenario(
            "screen-input-echo-only",
            [
                {"type": "keys", "text": "SCREEN_INPUT_ONLY"},
                {"type": "wait_screen", "contains": "SCREEN_INPUT_ONLY"},
                {"type": "wait_exit"},
            ],
            {"exit_code": 0},
        )
        with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
            self._load_one(scenario, "screen-input-echo-only.json")

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

    def test_ordered_stream_markers_must_not_overlap_input_or_prompt(self) -> None:
        echo_scenario = _pty_scenario(
            "ordered-echo-marker",
            [{"type": "keys", "text": "echo ECHO_ONLY"}, {"type": "wait_exit"}],
            {"stream": {"ordered_contains": ["ECHO_ONLY"]}, "exit_code": 0},
        )
        with self.assertRaisesRegex(runner.ScenarioError, "input echo"):
            self._load_one(echo_scenario, "ordered-echo-marker.json")

        prompt_scenario = _pty_scenario(
            "ordered-prompt-marker",
            [{"type": "wait_exit"}],
            {"stream": {"ordered_contains": ["TEST_PROMPT"]}, "exit_code": 0},
        )
        with self.assertRaisesRegex(runner.ScenarioError, "prompt redraw"):
            self._load_one(prompt_scenario, "ordered-prompt-marker.json")

    def test_ordered_stream_markers_are_checked_in_order(self) -> None:
        failures: list[str] = []
        runner._assert_text(
            "stream", "A before B before C",
            {"ordered_contains": ["A", "B", "C"]}, failures,
        )
        self.assertEqual(failures, [])

        runner._assert_text(
            "stream", "A before C before B",
            {"ordered_contains": ["A", "B", "C"]}, failures,
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("required order", failures[0])

    def test_ordered_stream_markers_must_be_nonempty_strings(self) -> None:
        scenario = _pty_scenario(
            "ordered-marker-invalid",
            [{"type": "wait_exit"}],
            {"stream": {"ordered_contains": ["A", 2]}, "exit_code": 0},
        )
        with self.assertRaisesRegex(runner.ScenarioError, "ordered_contains"):
            self._load_one(scenario, "ordered-marker-invalid.json")

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

    def test_expected_failure_rejects_unknown_platform(self) -> None:
        scenario = _batch_scenario("expected-failure-unknown-platform")
        scenario["expected_failure"] = {
            "reason": "known issue",
            "platform": "freebsd",
        }

        with self.assertRaisesRegex(runner.ScenarioError, "expected_failure.platform"):
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

    def test_argv_batch_invocation_disables_config_and_preserves_arguments(self) -> None:
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

        self.assertEqual(actual_arguments, ["--no-config", *arguments])
        self.assertEqual(actual_stdin, b"stdin line\n")

    def test_argv_batch_invocation_cannot_opt_in_to_config(self) -> None:
        scenario = _batch_scenario("argv-config-opt-in")
        scenario["invocation"] = {"kind": "argv", "arguments": ["--version"]}
        scenario["load_config"] = True

        with self.assertRaisesRegex(runner.ScenarioError, "load_config is supported only for pty"):
            runner._validate_scenario(scenario, Path("argv-config-opt-in.json"))

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

    def test_wait_for_prompt_is_boolean_and_pty_only(self) -> None:
        pty = _pty_scenario("pty-no-startup-prompt", [{"type": "wait_exit"}], {"exit_code": 0})
        pty["wait_for_prompt"] = False
        runner._validate_scenario(pty, Path("pty-no-startup-prompt.json"))

        pty["wait_for_prompt"] = "no"
        with self.assertRaisesRegex(runner.ScenarioError, "wait_for_prompt must be a boolean"):
            runner._validate_scenario(pty, Path("pty-no-startup-prompt.json"))

        batch = _batch_scenario("batch-no-startup-prompt")
        batch["wait_for_prompt"] = False
        with self.assertRaisesRegex(runner.ScenarioError, "wait_for_prompt is supported only for pty"):
            runner._validate_scenario(batch, Path("batch-no-startup-prompt.json"))

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

    def test_file_set_fixture_validation_rejects_unsafe_or_unbounded_values(self) -> None:
        valid = _batch_scenario("file-set-valid")
        valid["preconditions"]["file_sets"] = [
            {"directory": "work", "prefix": "entry_", "suffix": ".txt", "count": 3}
        ]
        runner._validate_scenario(valid, Path("file-set-valid.json"))

        invalid_sets = [
            ({"directory": "../outside", "prefix": "entry", "count": 1}, "escapes"),
            ({"directory": "work\ud800", "prefix": "entry", "count": 1}, "valid UTF-8"),
            ({"directory": "work", "prefix": "../entry", "count": 1}, "filename components"),
            ({"directory": "work", "prefix": "entry", "count": True}, "count"),
            ({"directory": "work", "prefix": "entry", "count": 0}, "count"),
            ({"directory": "work", "prefix": "entry", "count": runner.MAX_FILE_SET_FILES + 1}, "count"),
            ({"directory": "work", "prefix": "entry\ud800", "count": 1}, "valid UTF-8"),
            ({"directory": "work", "prefix": "entry", "suffix": "\ud800", "count": 1},
             "valid UTF-8"),
            ({"directory": "work", "prefix": "x" * 10_000, "count": 1}, "filename exceeds"),
            ({"directory": "work", "prefix": "日" * 100, "count": 1}, "filename exceeds"),
            ({"directory": "work", "prefix": "entry", "count": 1, "content": "x" * 10_000},
             "content exceeds"),
            ({"directory": "work", "prefix": "entry", "count": 1, "content": "日" * 400},
             "content exceeds"),
            ({"directory": "work", "prefix": "entry", "count": 1, "content": "\ud800"},
             "valid UTF-8"),
            ({"directory": "work", "prefix": "entry", "count": 1, "extra": "field"}, "fields"),
        ]
        for file_set, message in invalid_sets:
            with self.subTest(file_set=file_set):
                scenario = _batch_scenario("file-set-invalid")
                scenario["preconditions"]["file_sets"] = [file_set]
                with self.assertRaisesRegex(runner.ScenarioError, message):
                    runner._validate_scenario(scenario, Path("file-set-invalid.json"))

        scenario = _batch_scenario("file-set-total-limit")
        scenario["preconditions"]["file_sets"] = [
            {"directory": "first", "prefix": "entry", "count": runner.MAX_FILE_SET_FILES},
            {"directory": "second", "prefix": "entry", "count": 1},
        ]
        with self.assertRaisesRegex(runner.ScenarioError, "at most"):
            runner._validate_scenario(scenario, Path("file-set-total-limit.json"))

    def test_file_set_fixture_writer_creates_exact_bounded_files(self) -> None:
        scenario = _batch_scenario("file-set-write")
        scenario["preconditions"]["file_sets"] = [
            {
                "directory": "work/generated",
                "prefix": "entry_",
                "suffix": ".txt",
                "count": 3,
                "content": "fixture",
            }
        ]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runner._write_preconditions(scenario, root)
            files = sorted((root / "work" / "generated").iterdir())
            names = [path.name for path in files]
            contents = [path.read_text(encoding="utf-8") for path in files]

        self.assertEqual([f"entry_{index:05d}.txt" for index in range(3)],
                         names)
        self.assertEqual(["fixture"] * 3, contents)

    def test_file_set_fixture_writer_rejects_symlink_escape(self) -> None:
        scenario = _batch_scenario("file-set-symlink-escape")
        scenario["preconditions"]["file_sets"] = [
            {"directory": "escape", "prefix": "entry", "count": 1}
        ]
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as outside:
            root = Path(temporary)
            (root / "escape").symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(runner.ScenarioError, "escapes"):
                runner._write_preconditions(scenario, root)

    def test_read_only_directory_validation_rejects_unsafe_paths(self) -> None:
        unsafe_values = [
            ("/outside", "must be relative"),
            ("../outside", "must not contain '..'"),
            ("home/../outside", "must not contain '..'"),
            ("home\\..\\outside", "must not contain '..'"),
            ("C:\\outside", "must be relative"),
        ]
        for value, message in unsafe_values:
            with self.subTest(value=value):
                scenario = _batch_scenario("read-only-directory-invalid")
                scenario["preconditions"]["read_only_directories"] = [value]
                with self.assertRaisesRegex(runner.ScenarioError, message):
                    runner._validate_scenario(scenario, Path("read-only-directory-invalid.json"))

        scenario = _batch_scenario("read-only-directory-invalid-shape")
        scenario["preconditions"]["read_only_directories"] = "home"
        with self.assertRaisesRegex(runner.ScenarioError, "must be an array"):
            runner._validate_scenario(scenario, Path("read-only-directory-invalid-shape.json"))

    def test_read_only_directory_rejects_symlink_escape(self) -> None:
        scenario = _batch_scenario("read-only-directory-symlink-escape")
        scenario["preconditions"]["read_only_directories"] = ["escape"]
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as outside:
            root = Path(temporary)
            outside_directory = Path(outside) / "outside"
            outside_directory.mkdir()
            original_mode = stat.S_IMODE(outside_directory.stat().st_mode)
            (root / "escape").symlink_to(outside_directory, target_is_directory=True)

            with self.assertRaisesRegex(runner.ScenarioError, "escapes"):
                with runner._read_only_directory_modes(scenario, root):
                    self.fail("a symlink escape was accepted")

            self.assertEqual(stat.S_IMODE(outside_directory.stat().st_mode), original_mode)

    def test_read_only_directory_modes_restore_after_failure(self) -> None:
        scenario = _batch_scenario("read-only-directory-restores-after-failure")
        scenario["preconditions"]["read_only_directories"] = ["home"]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            home.mkdir()
            home.chmod(0o751)

            with self.assertRaisesRegex(RuntimeError, "simulated scenario failure"):
                with runner._read_only_directory_modes(scenario, root):
                    self.assertEqual(stat.S_IMODE(home.stat().st_mode), 0o551)
                    raise RuntimeError("simulated scenario failure")

            self.assertEqual(stat.S_IMODE(home.stat().st_mode), 0o751)

    def test_batch_timeout_restores_read_only_mode_before_temporary_cleanup(self) -> None:
        scenario = _batch_scenario("read-only-directory-timeout")
        scenario["preconditions"]["read_only_directories"] = ["home"]

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "scenario"
            root.mkdir()
            home = root / "home"
            home.mkdir()
            home.chmod(0o751)

            class RecordingTemporaryDirectory:
                mode_at_cleanup: int | None = None

                def __enter__(self) -> Path:
                    return root

                def __exit__(self, *_args: Any) -> bool:
                    self.mode_at_cleanup = stat.S_IMODE(home.stat().st_mode)
                    return False

            class TimeoutProcess:
                returncode = 0
                pid = 123

                def __init__(self) -> None:
                    self.attempts = 0

                def communicate(self, *_args: Any, **_kwargs: Any) -> tuple[bytes, bytes]:
                    self.attempts += 1
                    if self.attempts == 1:
                        raise subprocess.TimeoutExpired("nshell", timeout=1)
                    return b"", b""

                def poll(self) -> int:
                    return self.returncode

            temporary_directory = RecordingTemporaryDirectory()
            read_only_mode_at_launch: list[int] = []

            def start_process(*_args: Any, **_kwargs: Any) -> TimeoutProcess:
                read_only_mode_at_launch.append(stat.S_IMODE(home.stat().st_mode))
                return TimeoutProcess()

            with patch.object(runner.tempfile, "TemporaryDirectory", return_value=temporary_directory):
                with patch.object(runner.subprocess, "Popen", side_effect=start_process):
                    with self.assertRaisesRegex(runner.ScenarioError, "exceeded"):
                        runner._run_batch(scenario, Path("/unused/nshell"))

            self.assertEqual(read_only_mode_at_launch, [0o551])
            self.assertEqual(temporary_directory.mode_at_cleanup, 0o751)

    @staticmethod
    def _fake_process(stdout: bytes = b"OK\n", stderr: bytes = b"") -> Any:
        class FakeProcess:
            returncode = 0
            pid = 123

            def communicate(self, *_args: Any, **_kwargs: Any) -> tuple[bytes, bytes]:
                return stdout, stderr

        return FakeProcess()

    def test_process_timeout_stays_fail_with_expected_failure_marker(self) -> None:
        scenario = _batch_scenario("timeout-stays-fail")
        scenario["expected_failure"] = {"reason": "process timed out"}
        scenario["timeout_seconds"] = 1

        class TimeoutProcess:
            returncode = 0
            pid = 123
            calls = 0

            def communicate(self, *_args: Any, **_kwargs: Any) -> tuple[bytes, bytes]:
                self.calls += 1
                if self.calls == 1:
                    raise subprocess.TimeoutExpired("nshell", 1)
                return b"", b""

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scenario_dir = root / "scenarios"
            _write_json(scenario_dir / "J12/timeout.json", scenario)
            binary = root / "nshell"
            binary.write_text("placeholder", encoding="utf-8")
            binary.chmod(0o755)
            output = io.StringIO()
            with mock.patch.object(sys, "argv", [
                    "run-scenarios.py", "--binary", str(binary),
                    "--scenario-dir", str(scenario_dir), "--mode", "batch",
                ]), \
                    mock.patch.object(runner.subprocess, "Popen", return_value=TimeoutProcess()), \
                    mock.patch.object(runner, "_kill_process_group"), \
                    contextlib.redirect_stdout(output):
                exit_code = runner.main()

        self.assertEqual(1, exit_code)
        self.assertIn("FAIL timeout-stays-fail", output.getvalue())
        self.assertNotIn("XFAIL timeout-stays-fail", output.getvalue())

    def test_pty_wait_timeouts_are_xfail_with_expected_failure_marker(self) -> None:
        for kind in ("wait", "wait_input", "wait_screen", "wait_exit"):
            with self.subTest(kind=kind):
                step = {"type": kind}
                if kind in ("wait", "wait_input", "wait_screen"):
                    step["contains"] = "READY"
                steps = [step] if kind == "wait_exit" else [step, {"type": "wait_exit"}]
                if kind == "wait_input":
                    steps.insert(0, {"type": "keys", "text": "READY"})
                scenario = _pty_scenario(
                    f"pty-{kind}-timeout-xfail", steps, {"exit_code": 0}
                )
                scenario["expected_failure"] = {"reason": "known PTY issue"}

                exit_code, output = _run_main_for_pty_scenario(scenario, kind)

                self.assertEqual(0, exit_code)
                self.assertIn(f"XFAIL pty-{kind}-timeout-xfail: known PTY issue Failed:", output)
                self.assertIn("timed out waiting", output)

    def test_pty_wait_timeout_without_expected_failure_stays_fail(self) -> None:
        scenario = _pty_scenario(
            "pty-wait-exit-timeout-fail", [{"type": "wait_exit"}], {"exit_code": 0}
        )

        exit_code, output = _run_main_for_pty_scenario(scenario, "wait_exit")

        self.assertEqual(1, exit_code)
        self.assertIn("FAIL pty-wait-exit-timeout-fail:", output)
        self.assertIn("timed out waiting for nshell exit", output)
        self.assertNotIn("XFAIL pty-wait-exit-timeout-fail", output)

    def test_pty_expected_failure_that_passes_stays_xpass(self) -> None:
        scenario = _pty_scenario(
            "pty-timeout-xpass", [{"type": "wait_exit"}], {"exit_code": 0}
        )
        scenario["expected_failure"] = {"reason": "known PTY issue"}

        exit_code, output = _run_main_for_pty_scenario(scenario, None)

        self.assertEqual(1, exit_code)
        self.assertIn("XPASS pty-timeout-xpass: expected failure now satisfies all assertions:", output)

    def test_platform_expected_failure_only_applies_on_selected_platform(self) -> None:
        scenario = _batch_scenario("linux-only-expected-failure")
        scenario["expected_failure"] = {"reason": "known issue", "platform": "linux"}
        failed_run = ("", "", 1, ["expected output was missing"])
        passed_run = ("", "", 0, [])

        with mock.patch.object(runner, "_run_batch", return_value=failed_run):
            with mock.patch.object(runner.sys, "platform", "linux"):
                self.assertEqual(("XFAIL", "known issue Failed: expected output was missing"),
                                 runner._run_once(scenario, Path("/unused/nshell")))
            with mock.patch.object(runner.sys, "platform", "darwin"):
                self.assertEqual(("FAIL", "expected output was missing"),
                                 runner._run_once(scenario, Path("/unused/nshell")))

        with mock.patch.object(runner, "_run_batch", return_value=passed_run):
            with mock.patch.object(runner.sys, "platform", "linux"):
                self.assertEqual(("XPASS", "expected failure now satisfies all assertions: known issue"),
                                 runner._run_once(scenario, Path("/unused/nshell")))
            with mock.patch.object(runner.sys, "platform", "darwin"):
                self.assertEqual(("PASS", ""), runner._run_once(scenario, Path("/unused/nshell")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
