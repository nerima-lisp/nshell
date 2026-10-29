#!/usr/bin/env python3
"""Run the declarative batch and tmux PTY scenario corpus."""

from __future__ import annotations

import argparse
import json
import os
import re
import select
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from pathlib import PureWindowsPath
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SCENARIO_DIR = ROOT / "t" / "scenarios"
EXPECTED_SCENARIOS_FILE = "expected-scenarios.json"
MAX_TIMEOUT_SECONDS = 60
MAX_INPUT_DELAY_SECONDS = 1.0
MAX_REPEAT = 10
MAX_OUTPUT_BYTES = 1_048_576
MAX_FILE_SET_FILES = 20_000
MAX_FILE_SET_CONTENT_BYTES = 1_024
ENVIRONMENT_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
TMUX_KEY = re.compile(r"[A-Za-z0-9+-]+\Z")
SHIFTED_KEY_TEXT = {
    "1": "!",
    "2": "@",
    "3": "#",
    "4": "$",
    "5": "%",
    "6": "^",
    "7": "&",
    "8": "*",
    "9": "(",
    "0": ")",
    "-": "_",
    "+": "*",
}
TMUX_KEY_ECHO_TEXT = {
    "Space": " ",
    "Tab": "\t",
    "Enter": "\r\n",
    "Escape": "\x1b",
    "BSpace": "\x7f",
    "BTab": "\x1b[Z",
    "Up": "\x1b[A",
    "Down": "\x1b[B",
    "Right": "\x1b[C",
    "Left": "\x1b[D",
    "Home": "\x1b[H",
    "End": "\x1b[F",
    "IC": "\x1b[2~",
    "Insert": "\x1b[2~",
    "DC": "\x1b[3~",
    "Delete": "\x1b[3~",
    "PPage": "\x1b[5~",
    "PageUp": "\x1b[5~",
    "PgUp": "\x1b[5~",
    "NPage": "\x1b[6~",
    "PageDown": "\x1b[6~",
    "PgDn": "\x1b[6~",
    "F1": "\x1bOP",
    "F2": "\x1bOQ",
    "F3": "\x1bOR",
    "F4": "\x1bOS",
    "F5": "\x1b[15~",
    "F6": "\x1b[17~",
    "F7": "\x1b[18~",
    "F8": "\x1b[19~",
    "F9": "\x1b[20~",
    "F10": "\x1b[21~",
    "F11": "\x1b[23~",
    "F12": "\x1b[24~",
}


class ScenarioError(Exception):
    """A scenario could not be prepared or executed."""


class ScenarioTimeout(ScenarioError):
    """A PTY wait did not finish before its timeout."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ScenarioError(message)


def _pane_exit_status(status: str, dead_signal: str, scenario_id: str) -> int:
    if status:
        try:
            return int(status)
        except ValueError as error:
            raise ScenarioError(f"{scenario_id}: tmux reported an invalid exit status") from error
    if dead_signal:
        try:
            signum = signal.Signals[f"SIG{dead_signal.upper()}"].value
        except KeyError as error:
            raise ScenarioError(f"{scenario_id}: tmux reported an invalid exit signal") from error
        return 128 + signum
    raise ScenarioError(f"{scenario_id}: tmux reported an invalid exit status")


def _relative_path(root: Path, value: Any, label: str) -> Path:
    _require(isinstance(value, str) and value != "", f"{label} must be a non-empty path")
    _require("\x00" not in value, f"{label} must not contain a NUL byte")
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise ScenarioError(f"{label} must be valid UTF-8") from error
    relative = Path(value)
    _require(not relative.is_absolute(), f"{label} must be relative: {value!r}")
    resolved_root = root.resolve()
    resolved = (resolved_root / relative).resolve()
    _require(
        resolved == resolved_root or resolved.is_relative_to(resolved_root),
        f"{label} escapes its scenario directory: {value!r}",
    )
    return resolved


def _read_only_directory_path(root: Path, value: Any, label: str) -> Path:
    _require(isinstance(value, str) and value != "", f"{label} must be a non-empty path")
    _require("\x00" not in value, f"{label} must not contain a NUL byte")
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise ScenarioError(f"{label} must be valid UTF-8") from error
    relative = Path(value)
    windows_path = PureWindowsPath(value)
    _require(
        not relative.is_absolute() and not windows_path.is_absolute() and not windows_path.drive,
        f"{label} must be relative: {value!r}",
    )
    _require(
        ".." not in relative.parts and ".." not in windows_path.parts,
        f"{label} must not contain '..': {value!r}",
    )
    try:
        return _relative_path(root, value, label)
    except (OSError, RuntimeError) as error:
        raise ScenarioError(f"{label} could not be resolved") from error


@contextmanager
def _read_only_directory_modes(scenario: dict[str, Any], root: Path) -> Iterator[None]:
    preconditions = scenario.get("preconditions", {})
    directories = preconditions.get("read_only_directories", [])
    opened: list[tuple[int, int, str]] = []
    seen: set[tuple[int, int]] = set()
    try:
        for value in directories:
            label = f"{scenario['id']}: read-only directory"
            path = _read_only_directory_path(root, value, label)
            flags = (
                os.O_RDONLY
                | getattr(os, "O_DIRECTORY", 0)
                | getattr(os, "O_NOFOLLOW", 0)
            )
            try:
                descriptor = os.open(path, flags)
            except OSError as error:
                raise ScenarioError(
                    f"{scenario['id']}: cannot open read-only directory {value!r}"
                ) from error
            try:
                details = os.fstat(descriptor)
            except OSError as error:
                os.close(descriptor)
                raise ScenarioError(
                    f"{scenario['id']}: cannot inspect read-only directory {value!r}"
                ) from error
            if not stat.S_ISDIR(details.st_mode):
                os.close(descriptor)
                raise ScenarioError(
                    f"{scenario['id']}: read-only path is not a directory: {value!r}"
                )
            identity = (details.st_dev, details.st_ino)
            if identity in seen:
                os.close(descriptor)
                continue
            seen.add(identity)
            opened.append((descriptor, stat.S_IMODE(details.st_mode), value))

        for descriptor, mode, value in opened:
            try:
                os.fchmod(descriptor, mode & ~0o222)
            except OSError as error:
                raise ScenarioError(
                    f"{scenario['id']}: cannot make read-only directory {value!r}"
                ) from error
        yield
    finally:
        restoration_errors = []
        for descriptor, mode, value in reversed(opened):
            try:
                os.fchmod(descriptor, mode)
            except OSError as error:
                restoration_errors.append((value, error))
            finally:
                try:
                    os.close(descriptor)
                except OSError as error:
                    restoration_errors.append((value, error))
        if restoration_errors:
            value, error = restoration_errors[0]
            raise ScenarioError(
                f"{scenario['id']}: cannot restore read-only directory {value!r}"
            ) from error


def _scenario_files(directory: Path) -> list[Path]:
    _require(directory.is_dir(), f"scenario directory does not exist: {directory}")
    manifest = (directory / EXPECTED_SCENARIOS_FILE).resolve()
    paths = sorted(
        path for path in directory.rglob("*.json")
        if path.is_file() and path.resolve() != manifest
    )
    _require(paths, f"scenario directory contains no JSON scenarios: {directory}")
    return paths


def _verify_expected_scenarios(directory: Path, scenarios_by_path: dict[Path, dict[str, Any]]) -> None:
    manifest_path = directory / EXPECTED_SCENARIOS_FILE
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ScenarioError(f"cannot read expected-scenarios manifest {manifest_path}: {error}") from error
    _require(isinstance(manifest, dict), f"{manifest_path} must contain a JSON object")
    _require(manifest.get("version") == 1, f"{manifest_path}: version must be 1")
    entries = manifest.get("scenarios")
    _require(isinstance(entries, list) and entries,
             f"{manifest_path}: scenarios must be a non-empty array")

    expected_by_path: dict[Path, dict[str, Any]] = {}
    expected_ids: set[str] = set()
    for entry in entries:
        _require(isinstance(entry, dict), f"{manifest_path}: each scenario entry must be an object")
        _require(set(entry) == {"id", "uc", "path"},
                 f"{manifest_path}: each entry must define exactly id, uc, and path")
        scenario_id = entry["id"]
        _require(isinstance(scenario_id, str) and scenario_id,
                 f"{manifest_path}: scenario id must be a non-empty string")
        _require(scenario_id not in expected_ids,
                 f"{manifest_path}: duplicate scenario id: {scenario_id}")
        expected_ids.add(scenario_id)
        uc_ids = entry["uc"]
        _require(isinstance(uc_ids, list) and uc_ids,
                 f"{manifest_path}: {scenario_id}: uc must be a non-empty array")
        _require(all(isinstance(uc, str) and uc for uc in uc_ids),
                 f"{manifest_path}: {scenario_id}: each uc must be a non-empty string")
        _require(len(set(uc_ids)) == len(uc_ids),
                 f"{manifest_path}: {scenario_id}: duplicate uc id")
        scenario_path = _relative_path(directory, entry["path"], f"{manifest_path}: scenario path")
        _require(scenario_path.suffix == ".json" and scenario_path.is_file(),
                 f"{manifest_path}: {scenario_id}: scenario file does not exist: {entry['path']!r}")
        _require(scenario_path not in expected_by_path,
                 f"{manifest_path}: duplicate scenario path: {entry['path']!r}")
        expected_by_path[scenario_path] = entry

    actual_paths = set(scenarios_by_path)
    expected_paths = set(expected_by_path)
    missing_paths = sorted(path.relative_to(directory).as_posix() for path in expected_paths - actual_paths)
    unexpected_paths = sorted(path.relative_to(directory).as_posix() for path in actual_paths - expected_paths)
    _require(
        not missing_paths and not unexpected_paths,
        "scenario file set does not match expected-scenarios manifest: "
        f"missing={missing_paths}, unexpected={unexpected_paths}",
    )
    _require(
        len(scenarios_by_path) == len(entries),
        f"scenario count was {len(scenarios_by_path)}, expected {len(entries)}",
    )
    actual_ids = {scenario["id"] for scenario in scenarios_by_path.values()}
    _require(actual_ids == expected_ids,
             f"scenario id set does not match manifest: expected={sorted(expected_ids)}, actual={sorted(actual_ids)}")
    for scenario_path, scenario in scenarios_by_path.items():
        expected = expected_by_path[scenario_path]
        _require(scenario["id"] == expected["id"],
                 f"{scenario_path}: id was {scenario['id']!r}, expected {expected['id']!r}")
        _require(set(scenario["uc"]) == set(expected["uc"]),
                 f"{scenario_path}: uc was {sorted(scenario['uc'])}, expected {sorted(expected['uc'])}")


def _load_scenarios(directory: Path, mode: str, selected_ids: set[str]) -> list[dict[str, Any]]:
    scenarios: list[dict[str, Any]] = []
    scenarios_by_path: dict[Path, dict[str, Any]] = {}
    ids: set[str] = set()
    for path in _scenario_files(directory):
        try:
            scenario = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ScenarioError(f"cannot read {path}: {error}") from error
        _require(isinstance(scenario, dict), f"{path} must contain a JSON object")
        scenario_id = scenario.get("id")
        _require(isinstance(scenario_id, str) and scenario_id, f"{path} has no non-empty id")
        _require(scenario_id not in ids, f"duplicate scenario id: {scenario_id}")
        ids.add(scenario_id)
        _validate_scenario(scenario, path)
        scenarios_by_path[path.resolve()] = scenario
        if mode != "all" and scenario["mode"] != mode:
            continue
        if selected_ids and scenario_id not in selected_ids:
            continue
        scenarios.append(scenario)

    missing_ids = selected_ids - ids
    _require(not missing_ids, f"unknown scenario id(s): {', '.join(sorted(missing_ids))}")
    if mode == "all" and not selected_ids:
        _verify_expected_scenarios(directory.resolve(), scenarios_by_path)
    _require(scenarios, "scenario selection is empty")
    return scenarios


def _validate_scenario(scenario: dict[str, Any], path: Path) -> None:
    scenario_id = scenario.get("id", path.name)
    _require(scenario.get("mode") in ("batch", "pty"), f"{scenario_id}: mode must be batch or pty")
    load_config = scenario.get("load_config", False)
    _require(isinstance(load_config, bool), f"{scenario_id}: load_config must be a boolean")
    _require(not load_config or scenario["mode"] == "pty",
             f"{scenario_id}: load_config is supported only for pty scenarios")
    private_mode = scenario.get("private_mode", False)
    _require(isinstance(private_mode, bool), f"{scenario_id}: private_mode must be a boolean")
    _require(not private_mode or scenario["mode"] == "pty",
             f"{scenario_id}: private_mode is supported only for pty scenarios")
    input_delay = scenario.get("input_delay_seconds", 0)
    _require(
        isinstance(input_delay, (int, float))
        and not isinstance(input_delay, bool)
        and 0 <= input_delay <= MAX_INPUT_DELAY_SECONDS,
        f"{scenario_id}: input_delay_seconds must be between 0 and {MAX_INPUT_DELAY_SECONDS}",
    )
    _require(input_delay == 0 or scenario["mode"] == "pty",
             f"{scenario_id}: input_delay_seconds is supported only for pty scenarios")
    if "wait_for_prompt" in scenario:
        _require(scenario["mode"] == "pty",
                 f"{scenario_id}: wait_for_prompt is supported only for pty scenarios")
        _require(isinstance(scenario["wait_for_prompt"], bool),
                 f"{scenario_id}: wait_for_prompt must be a boolean")
    _require(
        isinstance(scenario.get("uc"), list) and scenario["uc"],
        f"{scenario_id}: uc must be a non-empty array",
    )
    for uc in scenario["uc"]:
        _require(isinstance(uc, str) and uc, f"{scenario_id}: each uc must be a non-empty string")

    environment = scenario.get("environment", {})
    _require(isinstance(environment, dict), f"{scenario_id}: environment must be an object")
    _require(isinstance(environment.get("append_extra_path", True), bool),
             f"{scenario_id}: environment.append_extra_path must be a boolean")
    variables = environment.get("variables", {})
    _require(isinstance(variables, dict), f"{scenario_id}: environment.variables must be an object")
    for name, value in variables.items():
        _require(
            isinstance(name, str) and ENVIRONMENT_NAME.fullmatch(name),
            f"{scenario_id}: invalid environment variable name {name!r}",
        )
        _require(isinstance(value, str), f"{scenario_id}: environment variable {name} must be a string")
        _require(name not in ("HOME", "TMPDIR", "TMUX", "TMUX_PANE"),
                 f"{scenario_id}: set {name} through the scenario environment, not variables")
    _relative_path(Path("/scenario"), environment.get("home", "home"), f"{scenario_id}: home")
    _relative_path(Path("/scenario"), environment.get("cwd", "work"), f"{scenario_id}: cwd")
    terminal_size = environment.get("terminal_size", {"columns": 80, "rows": 24})
    _require(isinstance(terminal_size, dict), f"{scenario_id}: terminal_size must be an object")
    for dimension in ("columns", "rows"):
        value = terminal_size.get(dimension)
        _require(
            isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 512,
            f"{scenario_id}: terminal_size.{dimension} must be between 1 and 512",
        )

    preconditions = scenario.get("preconditions", {})
    _require(isinstance(preconditions, dict), f"{scenario_id}: preconditions must be an object")
    read_only_directories = preconditions.get("read_only_directories", [])
    _require(isinstance(read_only_directories, list),
             f"{scenario_id}: preconditions.read_only_directories must be an array")
    for directory in read_only_directories:
        _read_only_directory_path(
            Path("/scenario"), directory, f"{scenario_id}: read-only directory"
        )
    fixtures = preconditions.get("files", [])
    _require(isinstance(fixtures, list), f"{scenario_id}: preconditions.files must be an array")
    fixture_paths: set[Path] = set()
    for fixture in fixtures:
        _require(isinstance(fixture, dict), f"{scenario_id}: each precondition file must be an object")
        fixture_path = _relative_path(
            Path("/scenario"), fixture.get("path"), f"{scenario_id}: precondition file"
        )
        _require(fixture_path not in fixture_paths,
                 f"{scenario_id}: duplicate precondition file path: {fixture.get('path')!r}")
        fixture_paths.add(fixture_path)
        _require(isinstance(fixture.get("content", ""), str),
                 f"{scenario_id}: precondition file content must be a string")
        _require(isinstance(fixture.get("executable", False), bool),
                 f"{scenario_id}: precondition file executable must be a boolean")

    file_sets = preconditions.get("file_sets", [])
    _require(isinstance(file_sets, list), f"{scenario_id}: preconditions.file_sets must be an array")
    total_file_set_files = 0
    for file_set in file_sets:
        _require(isinstance(file_set, dict), f"{scenario_id}: each precondition file set must be an object")
        _require(set(file_set) <= {"directory", "prefix", "suffix", "count", "content"},
                 f"{scenario_id}: file-set fields must be directory, prefix, suffix, count, and content")
        directory = _relative_path(
            Path("/scenario"), file_set.get("directory"), f"{scenario_id}: file-set directory"
        )
        prefix = file_set.get("prefix")
        suffix = file_set.get("suffix", "")
        count = file_set.get("count")
        content = file_set.get("content", "")
        _require(isinstance(prefix, str) and prefix,
                 f"{scenario_id}: file-set prefix must be a non-empty string")
        _require(isinstance(suffix, str), f"{scenario_id}: file-set suffix must be a string")
        _require(
            all(separator not in component for component in (prefix, suffix)
                for separator in ("/", "\\", "\x00")),
            f"{scenario_id}: file-set prefix and suffix must be safe filename components",
        )
        _require(
            isinstance(count, int) and not isinstance(count, bool)
            and 1 <= count <= MAX_FILE_SET_FILES,
            f"{scenario_id}: file-set count must be between 1 and {MAX_FILE_SET_FILES}",
        )
        total_file_set_files += count
        _require(total_file_set_files <= MAX_FILE_SET_FILES,
                 f"{scenario_id}: file sets may create at most {MAX_FILE_SET_FILES} files")
        _require(isinstance(content, str), f"{scenario_id}: file-set content must be a string")
        try:
            content_bytes = content.encode("utf-8")
            prefix_bytes = prefix.encode("utf-8")
            suffix_bytes = suffix.encode("utf-8")
        except UnicodeEncodeError as error:
            raise ScenarioError(
                f"{scenario_id}: file-set names and content must be valid UTF-8"
            ) from error
        _require(len(content_bytes) <= MAX_FILE_SET_CONTENT_BYTES,
                 f"{scenario_id}: file-set content exceeds {MAX_FILE_SET_CONTENT_BYTES} bytes")
        _require(len(prefix_bytes) + 5 + len(suffix_bytes) <= 255,
                 f"{scenario_id}: generated filename exceeds 255 bytes")
        for index in range(count):
            filename = f"{prefix}{index:05d}{suffix}"
            file_path = directory / filename
            _require(file_path not in fixture_paths,
                     f"{scenario_id}: duplicate precondition file path: {file_path}")
            fixture_paths.add(file_path)
    for file_path in fixture_paths:
        _require(not any(parent in fixture_paths for parent in file_path.parents),
                 f"{scenario_id}: a precondition file path is also a directory")

    if scenario["mode"] == "batch":
        invocation = scenario.get("invocation")
        _require(isinstance(invocation, dict), f"{scenario_id}: invocation must be an object")
        kind = invocation.get("kind")
        _require(kind in ("command", "stdin", "script", "argv"),
                 f"{scenario_id}: invocation.kind must be command, stdin, script, or argv")
        if kind in ("command", "stdin", "script"):
            _require(isinstance(invocation.get("text"), str),
                     f"{scenario_id}: invocation.text must be a string")
        if kind == "script":
            _relative_path(Path("/scenario"), invocation.get("path"), f"{scenario_id}: script path")
        if kind == "argv":
            arguments = invocation.get("arguments")
            _require(isinstance(arguments, list) and all(isinstance(arg, str) for arg in arguments),
                     f"{scenario_id}: argv invocation.arguments must be an array of strings")
            _require("stdin" not in invocation or isinstance(invocation["stdin"], str),
                     f"{scenario_id}: argv invocation.stdin must be a string")
    else:
        arguments = scenario.get("arguments")
        _require(arguments is None or (isinstance(arguments, list)
                                      and all(isinstance(arg, str) for arg in arguments)),
                 f"{scenario_id}: pty arguments must be an array of strings")
        sessions = _pty_sessions(scenario)
        for session in sessions:
            _require(isinstance(session["prompt"], str) and session["prompt"],
                     f"{scenario_id}: PTY sessions must set a unique prompt")
            steps = session["steps"]
            _require(isinstance(steps, list) and steps,
                     f"{scenario_id}: pty steps must be a non-empty array")
            for step in steps:
                _require(isinstance(step, dict), f"{scenario_id}: each pty step must be an object")
                kind = step.get("type")
                _require(
                    kind in (
                        "keys", "paste", "key", "wait", "wait_input", "wait_screen",
                        "wait_exit", "resize",
                    ),
                    f"{scenario_id}: unsupported pty step type {kind!r}",
                )
                if "input_delay_seconds" in step:
                    step_input_delay = step["input_delay_seconds"]
                    _require(kind in ("keys", "paste", "key"),
                             f"{scenario_id}: step input_delay_seconds is supported only for input steps")
                    _require(
                        isinstance(step_input_delay, (int, float))
                        and not isinstance(step_input_delay, bool)
                        and 0 <= step_input_delay <= MAX_INPUT_DELAY_SECONDS,
                        f"{scenario_id}: step input_delay_seconds must be between 0 and {MAX_INPUT_DELAY_SECONDS}",
                    )
                if kind in ("keys", "paste"):
                    _require(isinstance(step.get("text"), str), f"{scenario_id}: {kind} requires text")
                if kind == "resize":
                    for dimension in ("columns", "rows"):
                        value = step.get(dimension)
                        _require(
                            isinstance(value, int) and not isinstance(value, bool)
                            and 1 <= value <= 512,
                            f"{scenario_id}: resize.{dimension} must be between 1 and 512",
                        )
                if kind == "key":
                    key = step.get("key")
                    _require(isinstance(key, str) and TMUX_KEY.fullmatch(key),
                             f"{scenario_id}: invalid tmux key {key!r}")
                if kind in ("wait", "wait_input"):
                    _require(isinstance(step.get("contains"), str) and step["contains"],
                             f"{scenario_id}: {kind} requires a non-empty contains string")
                if kind == "wait_screen":
                    contains = step.get("contains")
                    excludes = step.get("excludes", [])
                    _require(contains is None or isinstance(contains, str) and bool(contains),
                             f"{scenario_id}: wait_screen.contains must be a non-empty string")
                    _require(isinstance(excludes, list) and all(isinstance(item, str) for item in excludes),
                             f"{scenario_id}: wait_screen.excludes must be an array of strings")
                    _require(all(excludes),
                             f"{scenario_id}: wait_screen.excludes must contain non-empty strings")
                    _require(contains is not None or bool(excludes),
                             f"{scenario_id}: wait_screen requires contains or excludes")
                if kind in ("wait", "wait_input", "wait_screen", "wait_exit"):
                    timeout = step.get("timeout_seconds", 10)
                    _require(
                        isinstance(timeout, (int, float))
                        and not isinstance(timeout, bool)
                        and 0 < timeout <= MAX_TIMEOUT_SECONDS,
                        f"{scenario_id}: step timeout_seconds must be in (0, {MAX_TIMEOUT_SECONDS}]",
                    )
            _require(
                steps[-1]["type"] in ("wait", "wait_exit")
                and all(step["type"] != "wait_exit" for step in steps[:-1]),
                f"{scenario_id}: end pty steps with wait or wait_exit, and make wait_exit last",
            )

    expected_failure = scenario.get("expected_failure")
    if expected_failure is not None:
        _require(isinstance(expected_failure, dict), f"{scenario_id}: expected_failure must be an object")
        reason = expected_failure.get("reason")
        _require(isinstance(reason, str) and reason.strip(),
                 f"{scenario_id}: expected_failure.reason must be non-empty")
        platform = expected_failure.get("platform")
        _require(platform is None or platform in ("linux", "darwin"),
                 f"{scenario_id}: expected_failure.platform must be linux or darwin")
    _require(isinstance(scenario.get("expected"), dict), f"{scenario_id}: expected must be an object")
    timeout = scenario.get("timeout_seconds", 30)
    _require(
        isinstance(timeout, (int, float))
        and not isinstance(timeout, bool)
        and 0 < timeout <= MAX_TIMEOUT_SECONDS,
        f"{scenario_id}: timeout_seconds must be in (0, {MAX_TIMEOUT_SECONDS}]",
    )
    if scenario["mode"] == "pty":
        total_input_delay = sum(
            step.get("input_delay_seconds", input_delay)
            for session in _pty_sessions(scenario)
            for step in session["steps"]
            if step["type"] in ("keys", "paste", "key")
        )
        _require(
            total_input_delay < timeout,
            f"{scenario_id}: configured input delays must fit within timeout_seconds",
        )
    expected = scenario["expected"]
    _require("exit_code" in expected, f"{scenario_id}: expected.exit_code is required")
    if scenario["mode"] == "pty":
        for session in _pty_sessions(scenario):
            session_scenario = dict(scenario)
            session_scenario["steps"] = session["steps"]
            session_environment = dict(scenario["environment"])
            session_variables = dict(session_environment.get("variables", {}))
            session_variables["NSHELL_PROMPT"] = session["prompt"]
            session_environment["variables"] = session_variables
            session_scenario["environment"] = session_environment
            _validate_pty_match_sources(session_scenario)
    output_checks = {"stdout", "stderr"} if scenario["mode"] == "batch" else {"stream", "screen"}
    effects = expected.get("side_effects", {})
    _require(isinstance(effects, dict), f"{scenario_id}: side_effects must be an object")
    has_effect_check = bool(effects.get("files")) or effects.get("history") is not None
    has_output_check = any(expected.get(key) is not None for key in output_checks)
    _require(
        has_output_check or "exit_code" in expected or has_effect_check,
        f"{scenario_id}: expected must define an output, exit-code, or side-effect check",
    )
    if "exit_code" in expected:
        _require(isinstance(expected["exit_code"], int) and not isinstance(expected["exit_code"], bool),
                 f"{scenario_id}: expected.exit_code must be an integer")
        if scenario["mode"] == "pty":
            sessions = _pty_sessions(scenario)
            _require(
                any(session["steps"][-1]["type"] == "wait_exit" for session in sessions),
                f"{scenario_id}: PTY exit-code checks require at least one final wait_exit step",
            )
            if any(session["steps"][-1]["type"] == "wait" for session in sessions):
                screen_expectation = expected.get("screen")
                _require(
                    isinstance(screen_expectation, dict)
                    and any(screen_expectation.get(key) for key in ("contains", "excludes")),
                    f"{scenario_id}: live PTY sessions require an expected.screen assertion",
                )
def _pty_sessions(scenario: dict[str, Any]) -> list[dict[str, Any]]:
    sessions = scenario.get("sessions")
    if sessions is None:
        return [{
            "id": "default",
            "prompt": scenario.get("environment", {}).get("variables", {}).get("NSHELL_PROMPT"),
            "steps": scenario.get("steps"),
        }]

    _require("steps" not in scenario, f"{scenario['id']}: use either pty steps or sessions")
    _require(isinstance(sessions, list) and len(sessions) >= 2,
             f"{scenario['id']}: sessions must contain at least two PTY sessions")
    ids: set[str] = set()
    prompts: set[str] = set()
    for session in sessions:
        _require(isinstance(session, dict), f"{scenario['id']}: each session must be an object")
        session_id = session.get("id")
        _require(isinstance(session_id, str) and session_id,
                 f"{scenario['id']}: each session requires a non-empty id")
        _require(session_id not in ids, f"{scenario['id']}: duplicate session id {session_id!r}")
        ids.add(session_id)
        prompt = session.get("prompt")
        _require(isinstance(prompt, str) and prompt,
                 f"{scenario['id']}: each session requires a non-empty prompt")
        _require(prompt not in prompts, f"{scenario['id']}: PTY session prompts must be unique")
        prompts.add(prompt)
        _require(isinstance(session.get("steps"), list),
                 f"{scenario['id']}: each session requires a steps array")
    return sessions
def _validate_pty_match_sources(scenario: dict[str, Any]) -> None:
    scenario_id = scenario["id"]
    prompt = scenario["environment"].get("variables", {}).get("NSHELL_PROMPT", "")

    def reject_overlap(label: str, marker: str, sources: list[tuple[str, str]]) -> None:
        for source_name, source in sources:
            if marker and marker in source:
                raise ScenarioError(
                    f"{scenario_id}: PTY {label} marker {marker!r} can be satisfied by {source_name}; "
                    "use a marker unique to shell output"
                )

    def require_input_echo(label: str, marker: str, sources: list[tuple[str, str]]) -> None:
        if marker and not any(
            source_name == "input echo" and marker in source
            for source_name, source in sources
        ):
            raise ScenarioError(
                f"{scenario_id}: PTY {label} marker {marker!r} must match preceding typed input"
            )

    inputs: list[str] = []
    for step in scenario["steps"]:
        if step["type"] in ("wait", "wait_input", "wait_screen"):
            sources = [("input echo", text) for text in inputs]
            sources.append(("prompt redraw", prompt))
            marker = step.get("contains")
            if marker is not None:
                if step["type"] == "wait_input":
                    require_input_echo(step["type"], marker, sources)
                else:
                    reject_overlap(step["type"], marker, sources)
        if step["type"] in ("keys", "paste"):
            inputs.append(step["text"])
        elif step["type"] == "key":
            inputs.extend(_tmux_key_echo_sources(step["key"]))

    sources = [("input echo", text) for text in inputs]
    sources.append(("prompt redraw", prompt))
    expected = scenario["expected"]
    for output_name in ("stream", "screen"):
        check = expected.get(output_name)
        if not isinstance(check, dict):
            continue
        matches: list[str] = []
        equals = check.get("equals")
        if isinstance(equals, str):
            matches.append(equals)
        contains = check.get("contains", [])
        if isinstance(contains, list):
            matches.extend(value for value in contains if isinstance(value, str))
        ordered_contains = check.get("ordered_contains", [])
        _require(
            isinstance(ordered_contains, list)
            and all(isinstance(value, str) and value for value in ordered_contains),
            f"{scenario_id}: {output_name}.ordered_contains must be an array of non-empty strings",
        )
        matches.extend(ordered_contains)
        for marker in matches:
            reject_overlap(f"{output_name} expectation", marker, sources)


def _tmux_key_echo_sources(key: str) -> list[str]:
    modifiers = []
    base_key = key
    while "-" in base_key:
        modifier, remainder = base_key.split("-", 1)
        if modifier not in ("C", "M", "S"):
            break
        modifiers.append(modifier)
        base_key = remainder

    text = base_key if len(base_key) == 1 else TMUX_KEY_ECHO_TEXT.get(base_key)
    if text is None:
        return []

    if "S" in modifiers and len(text) == 1:
        text = text.upper() if text.isalpha() else SHIFTED_KEY_TEXT.get(text, text)
    if "C" in modifiers:
        if len(text) != 1:
            return []
        codepoint = ord(text.upper())
        if codepoint > 95:
            return []
        text = chr(codepoint & 0x1F)
    if "M" in modifiers:
        text = "\x1b" + text

    sources = [text]
    if text.startswith("\x1b"):
        sources.append("^[" + text[1:])
    if text == "\t":
        sources.append("^I")
    if text == "\x7f":
        sources.append("^?")
    if len(text) == 1 and 0 < ord(text) < 32:
        sources.append("^" + chr(ord(text) + 64))
    return sources


def _environment(scenario: dict[str, Any], root: Path) -> tuple[dict[str, str], Path, Path]:
    settings = scenario.get("environment", {})
    home = _relative_path(root, settings.get("home", "home"), f"{scenario['id']}: home")
    cwd = _relative_path(root, settings.get("cwd", "work"), f"{scenario['id']}: cwd")
    tmpdir = root / "tmp"
    for directory in (
        home,
        cwd,
        tmpdir,
        home / ".config",
        home / ".cache",
        home / ".local" / "share",
        home / ".local" / "state",
    ):
        directory.mkdir(parents=True, exist_ok=True)
    env = {
        "HOME": str(home),
        "PATH": "/usr/bin:/bin",
        "TERM": "xterm-256color",
        "LANG": "C",
        "LC_ALL": "C",
        "TMPDIR": str(tmpdir),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
        "XDG_STATE_HOME": str(home / ".local" / "state"),
    }
    env.update(settings.get("variables", {}))
    extra_path = os.environ.get("NSHELL_SCENARIO_EXTRA_PATH")
    if scenario["mode"] == "batch" and extra_path and settings.get("append_extra_path", True):
        env["PATH"] = os.pathsep.join((env["PATH"], extra_path))
    return env, home, cwd


def _write_preconditions(scenario: dict[str, Any], root: Path) -> None:
    for fixture in scenario.get("preconditions", {}).get("files", []):
        path = _relative_path(root, fixture["path"], f"{scenario['id']}: precondition file")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(fixture.get("content", ""), encoding="utf-8")
        if fixture.get("executable", False):
            path.chmod(0o755)
    for file_set in scenario.get("preconditions", {}).get("file_sets", []):
        directory = _relative_path(root, file_set["directory"], f"{scenario['id']}: file-set directory")
        directory.mkdir(parents=True, exist_ok=True)
        content = file_set.get("content", "")
        for index in range(file_set["count"]):
            filename = f"{file_set['prefix']}{index:05d}{file_set.get('suffix', '')}"
            path = _relative_path(directory, filename, f"{scenario['id']}: generated file")
            _require(path.parent == directory,
                     f"{scenario['id']}: generated file escaped its file-set directory")
            path.write_text(content, encoding="utf-8")



_SGR_SEQUENCE_RE = re.compile(r"\x1b\[([0-?]*)[ -/]*m")
_SGR_VISIBILITY_NEUTRAL_CODES = frozenset({
    0, 1, 2, 3, 4, 9, 21, 22, 23, 24, 25, 27, 28, 29,
    51, 52, 53, 55, 58, 59, 60, 61, 62, 63, 64, 65, 73, 74, 75,
})


def _sgr_codes(sequence: str) -> list[int] | None:
    match = _SGR_SEQUENCE_RE.fullmatch(sequence)
    if match is None:
        return None
    parameters = match.group(1).split(";") if match.group(1) else ["0"]
    codes: list[int] = []
    index = 0
    while index < len(parameters):
        parameter = parameters[index]
        head = parameter.split(":", 1)[0]
        if not head:
            code = 0
        elif head.isdecimal():
            code = int(head)
        else:
            return None
        codes.append(code)
        if code in {38, 48, 58} and ":" not in parameter and index + 1 < len(parameters):
            mode = parameters[index + 1]
            if mode == "5":
                index += 3
                continue
            if mode == "2":
                index += 5
                continue
        index += 1
    return codes


def _sgr_sequence_preserves_visibility(sequence: str) -> bool:
    codes = _sgr_codes(sequence)
    return codes is not None and all(
        code in _SGR_VISIBILITY_NEUTRAL_CODES
        or 30 <= code <= 49
        or 90 <= code <= 107
        for code in codes
    )


def _visibility_change_active_before(actual: str, position: int) -> bool:
    concealed = False
    blinking = False
    unknown = False
    for match in _SGR_SEQUENCE_RE.finditer(actual, 0, position):
        codes = _sgr_codes(match.group(0))
        if codes is None:
            unknown = True
            continue
        for code in codes:
            if code == 0:
                concealed = False
                blinking = False
                unknown = False
            elif code == 8:
                concealed = True
            elif code == 28:
                concealed = False
            elif code in {5, 6}:
                blinking = True
            elif code == 25:
                blinking = False
            elif (
                code not in _SGR_VISIBILITY_NEUTRAL_CODES
                and code not in {5, 6, 8}
                and not 30 <= code <= 49
                and not 90 <= code <= 107
            ):
                unknown = True
    return concealed or blinking or unknown


def _visible_screen_text(screen: str) -> str:
    visible: list[str] = []
    concealed = False
    position = 0
    while position < len(screen):
        sgr = _SGR_SEQUENCE_RE.match(screen, position)
        if sgr is not None:
            codes = _sgr_codes(sgr.group(0))
            if codes is not None:
                for code in codes:
                    if code == 0 or code == 28:
                        concealed = False
                    elif code == 8:
                        concealed = True
            position = sgr.end()
            continue
        if screen.startswith("\x1b[", position):
            end = position + 2
            while end < len(screen) and not ("@" <= screen[end] <= "~"):
                end += 1
            position = min(end + 1, len(screen))
            continue
        if screen[position] == "\x1b":
            position = min(position + 2, len(screen))
            continue
        character = screen[position]
        if character in "\r\n":
            visible.append(character)
        elif concealed:
            visible.append(" ")
        else:
            visible.append(character)
        position += 1
    return "".join(visible)

def _find_expected_text(
    actual: str,
    expected: str,
    start: int,
    allow_sgr_between_characters: bool,
) -> tuple[int, int] | None:
    position = start
    while True:
        index = actual.find(expected, position)
        if index < 0:
            break
        if not _visibility_change_active_before(actual, index):
            return index, index + len(expected)
        position = index + 1

    if not allow_sgr_between_characters or "\x1b[" in expected:
        return None

    sgr_gap = rf"(?:{_SGR_SEQUENCE_RE.pattern})*"
    pattern = re.compile(
        sgr_gap + sgr_gap.join(re.escape(character) for character in expected)
    )
    match = pattern.search(actual, start)
    while match is not None:
        matched_sgr = _SGR_SEQUENCE_RE.finditer(match.group(0))
        if (
            not _visibility_change_active_before(actual, match.start())
            and all(_sgr_sequence_preserves_visibility(sgr.group(0)) for sgr in matched_sgr)
        ):
            return match.span()
        match = pattern.search(actual, match.start() + 1)
    return None


def _assert_text(
    label: str,
    actual: str,
    expected: Any,
    failures: list[str],
    allow_sgr_between_characters: bool = False,
    visible_screen_snapshots: tuple[str, ...] = (),
) -> None:
    if expected is None:
        return
    _require(isinstance(expected, dict), f"{label} expectation must be an object")
    if "equals" in expected:
        _require(isinstance(expected["equals"], str), f"{label}.equals must be a string")
        if actual != expected["equals"]:
            failures.append(f"{label} did not equal the expected text")
    contains = expected.get("contains", [])
    excludes = expected.get("excludes", [])
    ordered_contains = expected.get("ordered_contains", [])
    _require(isinstance(contains, list) and all(isinstance(item, str) for item in contains),
             f"{label}.contains must be an array of strings")
    _require(isinstance(excludes, list) and all(isinstance(item, str) for item in excludes),
             f"{label}.excludes must be an array of strings")
    _require(isinstance(ordered_contains, list)
             and all(isinstance(item, str) for item in ordered_contains),
             f"{label}.ordered_contains must be an array of strings")
    _require(
        "equals" in expected or bool(contains) or bool(excludes) or bool(ordered_contains),
        f"{label} expectation must define a non-empty text check",
    )
    _require(all(item for item in contains + excludes + ordered_contains),
             f"{label} text checks must be non-empty")
    visible_screen_texts = tuple(
        _visible_screen_text(snapshot) for snapshot in visible_screen_snapshots
    )
    for item in contains:
        if (
            _find_expected_text(actual, item, 0, allow_sgr_between_characters) is None
            and not any(item in visible for visible in visible_screen_texts)
        ):
            failures.append(f"{label} did not contain {item!r}")
    position = 0
    for item in ordered_contains:
        match = _find_expected_text(actual, item, position, allow_sgr_between_characters)
        if match is None:
            visible_ordered_match = False
            for visible in visible_screen_texts:
                visible_position = 0
                for visible_item in ordered_contains:
                    visible_match = visible.find(visible_item, visible_position)
                    if visible_match < 0:
                        break
                    visible_position = visible_match + len(visible_item)
                else:
                    visible_ordered_match = True
                    break
            if not visible_ordered_match:
                failures.append(f"{label} did not contain {item!r} in the required order")
            break
        position = match[1]
    for item in excludes:
        if (
            _find_expected_text(actual, item, 0, allow_sgr_between_characters) is not None
            or any(item in visible for visible in visible_screen_texts)
        ):
            failures.append(f"{label} unexpectedly contained {item!r}")


def _assert_side_effects(expected: dict[str, Any], cwd: Path, home: Path,
                         failures: list[str], scenario_id: str) -> None:
    side_effects = expected.get("side_effects", {})
    _require(isinstance(side_effects, dict), f"{scenario_id}: side_effects must be an object")
    files = side_effects.get("files", [])
    _require(isinstance(files, list), f"{scenario_id}: side_effects.files must be an array")
    for effect in files:
        _require(isinstance(effect, dict), f"{scenario_id}: each file effect must be an object")
        path = _relative_path(cwd, effect.get("path"), f"{scenario_id}: side-effect file")
        exists = effect.get("exists", True)
        _require(isinstance(exists, bool), f"{scenario_id}: file exists must be boolean")
        if path.exists() != exists:
            failures.append(f"file {effect.get('path')!r} existence was {path.exists()}, expected {exists}")
            continue
        if not exists:
            continue
        _require(path.is_file(), f"{scenario_id}: expected side effect is not a regular file: {effect['path']}")
        content = path.read_text(encoding="utf-8", errors="replace")
        text_check = {
            key: effect[key] for key in ("equals", "contains", "excludes") if key in effect
        }
        if text_check:
            _assert_text(f"file {effect['path']!r}", content, text_check, failures)

    history = side_effects.get("history")
    if history is not None:
        _require(isinstance(history, dict), f"{scenario_id}: side_effects.history must be an object")
        path = _relative_path(home, history.get("path"), f"{scenario_id}: history path")
        exists = history.get("exists", True)
        _require(isinstance(exists, bool), f"{scenario_id}: history exists must be boolean")
        if path.exists() != exists:
            failures.append(f"history {history.get('path')!r} existence was {path.exists()}, expected {exists}")
        elif exists:
            _require(path.is_file(), f"{scenario_id}: expected history is not a regular file")
            content = path.read_text(encoding="utf-8", errors="replace")
            text_check = {
                key: history[key] for key in ("equals", "contains", "excludes") if key in history
            }
            if text_check:
                _assert_text(f"history {history['path']!r}", content, text_check, failures)


def _binary_args(scenario: dict[str, Any], cwd: Path) -> tuple[list[str], bytes]:
    invocation = scenario["invocation"]
    kind = invocation["kind"]
    if kind == "command":
        return ["--no-config", "--command", invocation["text"]], b""
    if kind == "stdin":
        return ["--no-config"], invocation["text"].encode("utf-8")
    if kind == "argv":
        return ["--no-config", *invocation["arguments"]], invocation.get("stdin", "").encode("utf-8")
    script = _relative_path(cwd, invocation["path"], f"{scenario['id']}: script path")
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text(invocation["text"], encoding="utf-8")
    return [str(script)], b""


def _pty_shell_command(binary: Path, env: dict[str, str], arguments: list[str]) -> str:
    command = ["/usr/bin/env", "-i"]
    command.extend(f"{name}={value}" for name, value in sorted(env.items()))
    command.extend([str(binary), *arguments])
    return "exec " + shlex.join(command)


def _pty_arguments(scenario: dict[str, Any]) -> list[str]:
    arguments = scenario.get("arguments", [])
    prefix = [] if scenario.get("load_config", False) else ["--no-config"]
    if scenario.get("private_mode", False):
        prefix.append("--private")
    return [*prefix, *arguments]


def _kill_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def _run_batch(scenario: dict[str, Any], binary: Path) -> tuple[str, str, int, list[str]]:
    with tempfile.TemporaryDirectory(prefix="nshell-scenario-") as temporary:
        root = Path(temporary)
        env, home, cwd = _environment(scenario, root)
        _write_preconditions(scenario, root)
        arguments, stdin = _binary_args(scenario, cwd)
        timeout = scenario.get("timeout_seconds", 30)
        with _read_only_directory_modes(scenario, root):
            try:
                process = subprocess.Popen(
                    [str(binary), *arguments],
                    cwd=cwd,
                    env=env,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    start_new_session=True,
                )
            except OSError as error:
                raise ScenarioError(f"{scenario['id']}: could not start nshell: {error}") from error
            try:
                stdout, stderr = process.communicate(stdin, timeout=timeout)
            except subprocess.TimeoutExpired as error:
                _kill_process_group(process)
                stdout, stderr = process.communicate()
                raise ScenarioError(
                    f"{scenario['id']}: batch process exceeded {timeout:g}s; "
                    f"stdout={(stdout or b'').decode('utf-8', errors='replace')[-2000:]!r}; "
                    f"stderr={(stderr or b'').decode('utf-8', errors='replace')[-2000:]!r}"
                ) from error
            stdout_text = stdout.decode("utf-8", errors="replace")
            stderr_text = stderr.decode("utf-8", errors="replace")
            failures = _check_expected(scenario, stdout_text, stderr_text, process.returncode, home, cwd)
            return stdout_text, stderr_text, process.returncode, failures


def _nshell_command(binary: Path, scenario: dict[str, Any]) -> list[str]:
    return [str(binary), *_pty_arguments(scenario)]


class TmuxSession:
    def __init__(self, scenario: dict[str, Any], binary: Path, root: Path,
                 env: dict[str, str], cwd: Path):
        self.scenario = scenario
        self.root = root
        self.env = os.environ.copy()
        self.env["TMUX_TMPDIR"] = str(root)
        self.socket = "ns-" + uuid.uuid4().hex[:10]
        self.channel = "exit-" + uuid.uuid4().hex[:12]
        self.pane = ""
        self.stream = bytearray()
        self.visible_screen_snapshots: list[str] = []
        self.pending_wait_start: int | None = None
        self.fifo_fd = -1
        self.server_started = False
        self.exit_waiter: subprocess.Popen[bytes] | None = None
        self.deadline_seconds = scenario.get("timeout_seconds", 45)
        self._validate_timeout(self.deadline_seconds, scenario["id"])
        self.deadline = time.monotonic() + self.deadline_seconds

        environment = scenario.get("environment", {})
        size = environment.get("terminal_size", {"columns": 80, "rows": 24})
        shell_command = _pty_shell_command(binary, env, _nshell_command(binary, scenario)[1:])

        try:
            self._tmux(["start-server", ";", "set-option", "-s", "exit-empty", "off"])
            self.server_started = True
            self._tmux(["set-option", "-g", "remain-on-exit", "on"])
            self._tmux(["set-hook", "-g", "pane-died", f"wait-for -S {self.channel}"])
            self.exit_waiter = subprocess.Popen(
                self._tmux_argv(["wait-for", self.channel]),
                env=self.env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.fifo_path = root / f"pane-output-{self.socket}"
            os.mkfifo(self.fifo_path, 0o600)
            self.fifo_fd = os.open(self.fifo_path, os.O_RDWR | os.O_NONBLOCK)
            result = self._tmux([
                "new-session", "-d", "-P", "-F", "#{pane_id}",
                "-s", "scenario", "-x", str(size["columns"]), "-y", str(size["rows"]),
                "-c", str(cwd), shell_command,
            ])
            self.pane = result.stdout.decode("utf-8", errors="replace").strip()
            _require(self.pane.startswith("%"), f"{scenario['id']}: tmux did not return a pane id")
            self._tmux(["pipe-pane", "-o", "-t", self.pane, f"cat > {shlex.quote(str(self.fifo_path))}"])

            if scenario.get("wait_for_prompt", True):
                prompt = env["NSHELL_PROMPT"]
                self.send_key("Enter")
                self.wait_for(prompt, self.take_wait_start(), 10)
        except BaseException as error:
            try:
                self.close()
            except ScenarioError as cleanup_error:
                raise error from cleanup_error
            raise

    @staticmethod
    def _validate_timeout(value: Any, scenario_id: str) -> None:
        _require(
            isinstance(value, (int, float))
            and not isinstance(value, bool)
            and 0 < value <= MAX_TIMEOUT_SECONDS,
            f"{scenario_id}: timeout_seconds must be in (0, {MAX_TIMEOUT_SECONDS}]",
        )

    def _tmux_argv(self, arguments: list[str]) -> list[str]:
        return ["tmux", "-f", "/dev/null", "-L", self.socket, *arguments]

    def _tmux(self, arguments: list[str], input_text: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
        try:
            result = subprocess.run(
                self._tmux_argv(arguments),
                input=input_text,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=self.env,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ScenarioError(f"{self.scenario['id']}: tmux command failed: {error}") from error
        if result.returncode != 0:
            message = result.stderr.decode("utf-8", errors="replace").strip()
            raise ScenarioError(f"{self.scenario['id']}: tmux command failed: {message}")
        return result

    def send_text(self, text: str) -> None:
        self.pending_wait_start = len(self.stream)
        self._tmux(["send-keys", "-l", "-t", self.pane, text])

    def send_key(self, key: str) -> None:
        self.pending_wait_start = len(self.stream)
        self._tmux(["send-keys", "-t", self.pane, key])

    def paste(self, text: str) -> None:
        buffer_name = "scenario-" + uuid.uuid4().hex[:10]
        self._tmux(["load-buffer", "-b", buffer_name, "-"], text.encode("utf-8"))
        try:
            self.pending_wait_start = len(self.stream)
            self._tmux(["paste-buffer", "-p", "-b", buffer_name, "-t", self.pane])
        finally:
            self._tmux(["delete-buffer", "-b", buffer_name])

    def resize(self, columns: int, rows: int) -> None:
        self.pending_wait_start = len(self.stream)
        self._tmux([
            "resize-window", "-t", self.pane,
            "-x", str(columns), "-y", str(rows),
        ])

    def take_wait_start(self) -> int:
        start = self.pending_wait_start
        self.pending_wait_start = None
        return len(self.stream) if start is None else start

    def _read(self, timeout: float) -> bytes:
        readable, _, _ = select.select([self.fifo_fd], [], [], timeout)
        if not readable:
            return b""
        remaining = MAX_OUTPUT_BYTES - len(self.stream)
        try:
            data = os.read(self.fifo_fd, min(65536, remaining + 1))
        except BlockingIOError:
            return b""
        if data:
            if len(data) > remaining:
                raise ScenarioError(f"{self.scenario['id']}: PTY output limit exceeded")
            self.stream.extend(data)
        return data

    def drain(self) -> None:
        while self._read(0):
            pass

    def _capture(self) -> str:
        try:
            result = self._tmux(["capture-pane", "-p", "-t", self.pane])
        except ScenarioError:
            return "<pane no longer available>"
        return result.stdout.decode("utf-8", errors="replace")

    def wait_for(self, text: str, start: int, timeout: float) -> int:
        self._validate_timeout(timeout, self.scenario["id"])
        needle = text.encode("utf-8")
        deadline = min(self.deadline, time.monotonic() + timeout)
        while True:
            position = bytes(self.stream).find(needle, start)
            if position >= 0:
                return position + len(needle)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                screen = self._capture()
                raise ScenarioTimeout(
                    f"{self.scenario['id']}: timed out waiting for {text!r}; "
                    f"current screen:\n{screen}"
                )
            self._read(remaining)

    def wait_for_screen(self, text: str | None, timeout: float,
                        excludes: list[str] | None = None) -> str | None:
        self._validate_timeout(timeout, self.scenario["id"])
        excludes = excludes or []
        condition = f"contains={text!r}, excludes={excludes!r}"
        deadline = min(self.deadline, time.monotonic() + timeout)
        while True:
            screen = self._capture()
            if (text is None or text in screen) and all(marker not in screen for marker in excludes):
                return None
            if self.exit_waiter is not None and self.exit_waiter.poll() is not None:
                self._read(0)
                screen = self._capture()
                return (
                    f"{self.scenario['id']}: pane exited before screen conditions ({condition}) were met; "
                    f"current screen:\n{screen}"
                )
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ScenarioTimeout(
                    f"{self.scenario['id']}: timed out waiting for screen conditions ({condition}); "
                    f"current screen:\n{screen}"
                )
            self._read(min(remaining, 0.1))

    def wait_for_input(self, text: str, timeout: float) -> str | None:
        """Wait until typed input is visible in the current PTY screen."""
        return self.wait_for_screen(text, timeout)

    def wait_after_input(self, delay: float) -> None:
        if delay <= 0:
            return
        remaining = self.deadline - time.monotonic()
        _require(
            delay < remaining,
            f"{self.scenario['id']}: input delay would exceed scenario deadline",
        )
        time.sleep(delay)
        _require(
            time.monotonic() < self.deadline,
            f"{self.scenario['id']}: input delay exceeded scenario deadline",
        )
        self.capture_screen()

    def wait_exit(self, timeout: float) -> int:
        _require(self.exit_waiter is not None, f"{self.scenario['id']}: tmux exit waiter is missing")
        deadline = min(self.deadline, time.monotonic() + timeout)
        while self.exit_waiter.poll() is None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                screen = self._capture()
                raise ScenarioTimeout(
                    f"{self.scenario['id']}: timed out waiting for nshell exit; current screen:\n{screen}"
                )
            self._read(min(remaining, 0.1))
        stdout, stderr = self.exit_waiter.communicate()
        _require(self.exit_waiter.returncode == 0,
                 f"{self.scenario['id']}: tmux exit wait failed: "
                 f"{stderr.decode('utf-8', errors='replace').strip()}")
        self.drain()
        result = self._tmux([
            "display-message", "-p", "-t", self.pane,
            "#{pane_dead_status} #{pane_dead_signal}",
        ])
        status, separator, dead_signal = result.stdout.decode("ascii").rstrip("\r\n").partition(" ")
        _require(bool(separator), f"{self.scenario['id']}: tmux reported an invalid exit status")
        return _pane_exit_status(status, dead_signal, self.scenario["id"])

    def capture_screen(self) -> str:
        return self._capture()

    def capture_styled_screen(self) -> str:
        try:
            result = self._tmux(["capture-pane", "-e", "-p", "-t", self.pane])
        except ScenarioError:
            screen = "<pane no longer available>"
        else:
            screen = result.stdout.decode("utf-8", errors="replace")
        self.visible_screen_snapshots.append(screen)
        return screen

    def close(self) -> None:
        if self.exit_waiter is not None and self.exit_waiter.poll() is None:
            self.exit_waiter.terminate()
            try:
                self.exit_waiter.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.exit_waiter.kill()
                self.exit_waiter.wait()
        cleanup_error = None
        if self.server_started:
            try:
                self._tmux(["kill-server"])
            except ScenarioError as error:
                cleanup_error = error
        if self.fifo_fd >= 0:
            os.close(self.fifo_fd)
            self.fifo_fd = -1
        if cleanup_error is not None:
            raise cleanup_error


def _run_pty(scenario: dict[str, Any], binary: Path) -> tuple[str, str, int, list[str]]:
    _require(shutil.which("tmux") is not None, f"{scenario['id']}: tmux is required for PTY scenarios")
    with tempfile.TemporaryDirectory(prefix="nshell-scenario-") as temporary:
        root = Path(temporary)
        env, home, cwd = _environment(scenario, root)
        _write_preconditions(scenario, root)
        with _read_only_directory_modes(scenario, root):
            sessions: list[tuple[TmuxSession, dict[str, Any]]] = []
            exit_codes: list[int] = []
            failures: list[str] = []
            try:
                for spec in _pty_sessions(scenario):
                    session_scenario = dict(scenario)
                    session_scenario["id"] = f"{scenario['id']}:{spec['id']}"
                    session_scenario["steps"] = spec["steps"]
                    session_environment = dict(scenario["environment"])
                    session_variables = dict(session_environment.get("variables", {}))
                    session_variables["NSHELL_PROMPT"] = spec["prompt"]
                    session_environment["variables"] = session_variables
                    session_scenario["environment"] = session_environment
                    session_env = env.copy()
                    session_env["NSHELL_PROMPT"] = spec["prompt"]
                    session = TmuxSession(session_scenario, binary, root, session_env, cwd)
                    sessions.append((session, spec))
                for session, _ in sessions:
                    session.deadline = time.monotonic() + session.deadline_seconds

                for session, spec in sessions:
                    for step in spec["steps"]:
                        kind = step["type"]
                        if kind == "keys":
                            session.send_text(step["text"])
                        elif kind == "paste":
                            session.paste(step["text"])
                        elif kind == "key":
                            session.send_key(step["key"])
                        elif kind == "resize":
                            session.resize(step["columns"], step["rows"])
                        elif kind == "wait":
                            session.wait_for(
                                step["contains"],
                                session.take_wait_start(),
                                step.get("timeout_seconds", 10),
                            )
                            session.capture_styled_screen()
                        elif kind in ("wait_screen", "wait_input"):
                            timeout = step.get("timeout_seconds", 10)
                            if kind == "wait_input":
                                failure = session.wait_for_input(step["contains"], timeout)
                            else:
                                failure = session.wait_for_screen(
                                    step.get("contains"), timeout, step.get("excludes", [])
                                )
                            if failure:
                                failures.append(failure)
                                exit_step = next(
                                    (candidate for candidate in reversed(spec["steps"])
                                     if candidate["type"] == "wait_exit"),
                                    None,
                                )
                                exit_codes.append(
                                    session.wait_exit(
                                        exit_step.get("timeout_seconds", 10) if exit_step else 10
                                    )
                                )
                                session.drain()
                                break
                            session.capture_styled_screen()
                        elif kind == "wait_exit":
                            exit_codes.append(session.wait_exit(step.get("timeout_seconds", 10)))
                            session.drain()
                        if kind in ("keys", "paste", "key"):
                            input_delay = step.get(
                                "input_delay_seconds", scenario.get("input_delay_seconds", 0)
                            )
                            session.wait_after_input(input_delay)
                            if input_delay > 0:
                                session.capture_styled_screen()
                total_output = sum(len(session.stream) for session, _ in sessions)
                _require(total_output <= MAX_OUTPUT_BYTES, f"{scenario['id']}: PTY output limit exceeded")
                stream = "\n".join(
                    bytes(session.stream).decode("utf-8", errors="replace") for session, _ in sessions
                )
                screen = "\n".join(session.capture_screen() for session, _ in sessions)
                for session, _ in sessions:
                    session.capture_styled_screen()
                visible_screen_snapshots = tuple(
                    snapshot
                    for session, _ in sessions
                    for snapshot in session.visible_screen_snapshots
                )
                exit_code = next((code for code in exit_codes if code != 0), exit_codes[-1] if exit_codes else -1)
                failures.extend(_check_expected(
                    scenario,
                    stream,
                    screen,
                    exit_code,
                    home,
                    cwd,
                    visible_screen_snapshots=visible_screen_snapshots,
                ))
            finally:
                for session, _ in reversed(sessions):
                    session.close()
            return stream, screen, exit_code, failures



def _check_expected(scenario: dict[str, Any], first: str, second: str, exit_code: int,
                    home: Path, cwd: Path,
                    visible_screen_snapshots: tuple[str, ...] = ()) -> list[str]:
    expected = scenario["expected"]
    failures: list[str] = []
    if scenario["mode"] == "batch":
        stdout, stderr = first, second
        _assert_text("stdout", stdout, expected.get("stdout"), failures)
        _assert_text("stderr", stderr, expected.get("stderr"), failures)
    else:
        stream, screen = first, second
        _assert_text(
            "PTY stream",
            stream,
            expected.get("stream"),
            failures,
            allow_sgr_between_characters=True,
            visible_screen_snapshots=visible_screen_snapshots,
        )
        _assert_text("PTY screen", screen, expected.get("screen"), failures)
    if "exit_code" in expected and exit_code != expected["exit_code"]:
        failures.append(f"exit code was {exit_code}, expected {expected['exit_code']}")
    _assert_side_effects(expected, cwd, home, failures, scenario["id"])
    return failures


def _run_once(scenario: dict[str, Any], binary: Path) -> tuple[str, str]:
    expected_failure = scenario.get("expected_failure")
    if expected_failure is not None and expected_failure.get("platform", sys.platform) != sys.platform:
        expected_failure = None
    try:
        _, _, _, failures = _run_batch(scenario, binary) if scenario["mode"] == "batch" else _run_pty(scenario, binary)
    except ScenarioTimeout as error:
        if expected_failure is None:
            raise
        return "XFAIL", f"{expected_failure['reason']} Failed: {error}"
    if expected_failure is not None:
        if failures:
            return "XFAIL", f"{expected_failure['reason']} Failed: {'; '.join(failures)}"
        return "XPASS", f"expected failure now satisfies all assertions: {expected_failure['reason']}"
    if failures:
        return "FAIL", "; ".join(failures)
    return "PASS", ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path, help="path to the nshell executable")
    parser.add_argument("--scenario-dir", type=Path, default=DEFAULT_SCENARIO_DIR)
    parser.add_argument("--mode", choices=("all", "batch", "pty"), default="all")
    parser.add_argument("--scenario-id", action="append", default=[])
    parser.add_argument("--repeat", type=int, default=1)
    arguments = parser.parse_args()

    if not 1 <= arguments.repeat <= MAX_REPEAT:
        parser.error(f"--repeat must be between 1 and {MAX_REPEAT}")
    binary = arguments.binary.resolve()
    if not binary.is_file() or binary.stat().st_size == 0 or not os.access(binary, os.X_OK):
        parser.error(f"--binary must be a non-empty executable file: {binary}")

    try:
        scenarios = _load_scenarios(arguments.scenario_dir.resolve(), arguments.mode, set(arguments.scenario_id))
        summary = {"PASS": 0, "XFAIL": 0, "XPASS": 0, "FAIL": 0}
        for scenario in scenarios:
            for iteration in range(1, arguments.repeat + 1):
                try:
                    status, detail = _run_once(scenario, binary)
                except ScenarioError as error:
                    status, detail = "FAIL", str(error)
                summary[status] += 1
                suffix = f" run={iteration}/{arguments.repeat}" if arguments.repeat > 1 else ""
                line = f"{status} {scenario['id']}{suffix}"
                if detail:
                    line += f": {detail}"
                print(line)
        total = sum(summary.values())
        print(
            "SCENARIO_SUMMARY "
            f"selected={len(scenarios)} runs={total} "
            f"pass={summary['PASS']} xfail={summary['XFAIL']} "
            f"xpass={summary['XPASS']} fail={summary['FAIL']}"
        )
        return int(summary["XPASS"] > 0 or summary["FAIL"] > 0)
    except ScenarioError as error:
        print(f"SCENARIO_ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
