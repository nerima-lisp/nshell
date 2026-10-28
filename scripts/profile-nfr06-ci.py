#!/usr/bin/env python3
"""Profile interactive NFR-06 Tab completion with gated sb-sprof."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEASURE_SCRIPT = ROOT / "scripts/measure-nfr-04-06.py"
CONTROLLER_TEMPLATE = ROOT / "scripts/profile-nfr06-controller.lisp"
OUT = Path(os.environ["NFR06_PROFILE_OUTPUT"]).resolve()
FIXTURE = Path(os.environ["NFR06_PROFILE_FIXTURE"]).resolve()
BINARY = Path(os.environ["NFR06_PROFILE_BINARY"]).resolve()
SAMPLE_INTERVAL = 0.00005
ALLOC_INTERVAL = 65536
MAX_SAMPLES = 100000
REQUEST_TIMEOUT = 60.0


def profile_sbcl_home(binary: Path) -> Path:
    def store_executable(text: str, suffix: str) -> Path | None:
        for token in text.split():
            candidate = token.strip('"')
            if candidate.startswith("/nix/store/") and candidate.endswith(suffix):
                return Path(candidate)
        return None

    with binary.open("rb") as stream:
        is_script = stream.read(2) == b"#!"
    executable = None
    if is_script:
        wrapper_text = binary.read_text(encoding="utf-8", errors="replace")
        runtime_wrapper = store_executable(wrapper_text, "/bin/.nshell-wrapped")
        if runtime_wrapper is not None:
            runtime_text = runtime_wrapper.read_text(encoding="utf-8", errors="replace")
            executable = store_executable(runtime_text, "/bin/sbcl")
            if executable is None:
                raise RuntimeError(f"could not resolve the SBCL executable from {runtime_wrapper}")
        else:
            executable = store_executable(wrapper_text, "/bin/sbcl")
    if executable is None:
        executable_text = shutil.which("sbcl")
        if executable_text is None:
            raise RuntimeError("could not find the SBCL executable on PATH")
        executable = Path(executable_text).resolve()
    home = executable.parent.parent / "lib" / "sbcl"
    if not (home / "contrib" / "sb-sprof.fasl").is_file():
        raise RuntimeError(f"sb-sprof contrib not found under SBCL_HOME: {home}")
    return home


def measurement_module():
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(MEASURE_SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("measure_nfr_04_06_profile", MEASURE_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import measurement helper: {MEASURE_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_request(control: Path, name: str, text: str = "") -> None:
    path = control / name
    temporary = control / f".{name}.{uuid.uuid4().hex}.tmp"
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def ensure_fixture() -> None:
    FIXTURE.mkdir(parents=True, exist_ok=True)
    existing = list(FIXTURE.iterdir())
    if not existing:
        for index in range(20_000):
            (FIXTURE / f"item-{index:05d}").touch()
        existing = list(FIXTURE.iterdir())
    if len(existing) != 20_000 or any(
        not path.is_file() or not re.fullmatch(r"item-\d{5}", path.name)
        for path in existing
    ):
        raise RuntimeError(f"profile fixture must contain exactly 20,000 item files: {FIXTURE}")


def wait_for_text(path: Path, timeout: float = REQUEST_TIMEOUT) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file():
            text = path.read_text(encoding="utf-8").strip()
            if text:
                return text
        time.sleep(0.002)
    raise TimeoutError(f"timed out waiting for non-empty {path}")


def wait_for_matching_text(path: Path, expected: str, timeout: float = REQUEST_TIMEOUT) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file():
            text = path.read_text(encoding="utf-8").strip()
            if expected in text:
                return text
        time.sleep(0.001)
    raise TimeoutError(f"timed out waiting for {path} containing {expected!r}")


def wait_for_output_since(session, start: int, predicate, timeout: float, phase: str, iteration: int) -> int:
    deadline = time.monotonic() + timeout
    while True:
        output = bytes(session.data[start:])
        if predicate(output):
            return time.monotonic_ns()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(
                f"operation {iteration}: timed out waiting for {phase}; "
                f"tail={output[-800:]!r}"
            )
        session._read_once(min(0.1, remaining))


def remaining_seconds(deadline: float, iteration: int, phase: str) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError(f"operation {iteration}: timed out waiting for {phase}")
    return remaining


def install_incremental_cursor_query_handler(session, module) -> None:
    query = module.CPR_QUERY
    response = module.CPR_RESPONSE
    scanned_bytes = 0

    def respond_to_new_queries() -> None:
        nonlocal scanned_bytes
        overlap_start = max(0, scanned_bytes - len(query) + 1)
        previous_overlap = scanned_bytes - overlap_start
        new_data = bytes(session.data[overlap_start:])
        offset = 0
        while True:
            found = new_data.find(query, offset)
            if found < 0:
                break
            if found + len(query) > previous_overlap:
                os.write(session.master, response)
                session.responses_sent += 1
            offset = found + len(query)
        scanned_bytes = len(session.data)

    session._respond_to_cursor_queries = respond_to_new_queries


def write_progress(
    run_dir: Path,
    mode: str,
    iteration: int,
    iterations: int,
    completed: int,
    phase: str,
    status: str = "running",
) -> None:
    progress = {
        "status": status,
        "mode": mode,
        "iteration": iteration,
        "iterations_requested": iterations,
        "iterations_completed": completed,
        "waiting_for": phase,
    }
    path = run_dir / "progress.json"
    temporary = run_dir / f".progress.{uuid.uuid4().hex}.tmp"
    temporary.write_text(json.dumps(progress, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)
    print(
        f"NFR-06 profile {mode}: iteration {iteration}/{iterations}, "
        f"completed={completed}, phase={phase}, status={status}",
        flush=True,
    )


def profile_sample_count(graph: Path) -> int | None:
    if not graph.is_file():
        return None
    match = re.search(r"Number of samples:\s*(\d+)", graph.read_text(encoding="utf-8", errors="replace"))
    return int(match.group(1)) if match else None


def read_profile_sample_diagnostics(path: Path) -> dict[str, int] | None:
    if not path.is_file():
        return None
    expected = {
        "sb_sprof_stop_counter",
        "raw_vector_trace_count",
        "map_traces_count",
        "samples_vector_length",
    }
    counts: dict[str, int] = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    if lines and not lines[-1]:
        lines.pop()
    for line in lines:
        key, separator, value = line.partition("=")
        if not separator or key in counts:
            raise RuntimeError(f"invalid profile sample diagnostic row: {line!r}")
        try:
            count = int(value)
        except ValueError as error:
            raise RuntimeError(f"invalid profile sample diagnostic value: {line!r}") from error
        if count < 0:
            raise RuntimeError(f"negative profile sample diagnostic value: {line!r}")
        counts[key] = count
    if set(counts) != expected:
        raise RuntimeError(
            f"profile sample diagnostic fields {sorted(counts)} do not match {sorted(expected)}"
        )
    return counts


def validate_profile_sample_counts(
    graph_count: int, diagnostics: dict[str, int], thread_count_total: int
) -> None:
    # SBCL snapshots this counter at stop time, before later traversals of the
    # materialized samples. Its stop path allows an undelivered SIGPROF, so
    # retain this value as a diagnostic and validate the materialized views.
    counts = {
        "graph_header": graph_count,
        "raw_vector": diagnostics["raw_vector_trace_count"],
        "map_traces": diagnostics["map_traces_count"],
        "thread_counts_csv": thread_count_total,
    }
    if graph_count > 0 and diagnostics["samples_vector_length"] == 0:
        raise RuntimeError("profile sample vector is empty despite a non-empty sample count")
    if len(set(counts.values())) != 1:
        details = " ".join(f"{name}={count}" for name, count in counts.items())
        raise RuntimeError(f"profile materialized sample counts disagree: {details}")


def controller_source(
    command: str,
    control: Path,
    graph: Path,
    target_graph: Path,
    target_flat: Path,
    flat: Path,
    metrics: Path,
    iterations: int,
    mode: str,
    render_timeout_seconds: float,
) -> str:
    profile_options = (
        f":mode :cpu :sample-interval {SAMPLE_INTERVAL} :max-samples {MAX_SAMPLES}"
        if mode == "cpu"
        else f":mode :alloc :alloc-interval {ALLOC_INTERVAL} :max-samples {MAX_SAMPLES}"
    )
    source = CONTROLLER_TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "__COMMAND__": json.dumps(command),
        "__CONTROL__": json.dumps(str(control)),
        "__GRAPH__": json.dumps(str(graph)),
        "__TARGET_GRAPH__": json.dumps(str(target_graph)),
        "__TARGET_FLAT__": json.dumps(str(target_flat)),
        "__FLAT__": json.dumps(str(flat)),
        "__METRICS__": json.dumps(str(metrics)),
        "__ITERATIONS__": str(iterations),
        "__MODE__": ":cpu" if mode == "cpu" else ":alloc",
        "__PROFILE_OPTIONS__": profile_options,
        "__RENDER_TIMEOUT_SECONDS__": repr(render_timeout_seconds),
    }
    for old, new in replacements.items():
        source = source.replace(old, new)
    return source


def graceful_exit(session, timeout: float = 10.0) -> int:
    if os.write(session.master, b"\x04") != 1:
        raise RuntimeError("PTY did not accept Ctrl-D")
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            child, status = os.waitpid(session.pid, os.WNOHANG)
        except InterruptedError:
            continue
        if child == session.pid:
            session._close_master()
            return os.waitstatus_to_exitcode(status)
        try:
            session._read_once(min(0.1, deadline - time.monotonic()))
        except (TimeoutError, OSError):
            continue
        except RuntimeError as error:
            # The child may exit between the preceding WNOHANG check and this PTY read.
            if not any(
                message in str(error)
                for message in ("PTY child closed its output", "PTY child exited;")
            ):
                raise
    raise TimeoutError(f"nshell PID {session.pid} did not exit after Ctrl-D")


def controller_error(control: Path) -> str | None:
    path = control / "controller.error"
    if path.is_file():
        return path.read_text(encoding="utf-8").strip()
    return None


def wait_for_controller_ready(session, control: Path, start: int,
                              predicate, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        error = controller_error(control)
        if error:
            raise RuntimeError(f"profile controller failed: {error}")
        if predicate(bytes(session.data[start:])):
            return
        session._read_once(min(0.1, max(0.0, deadline - time.monotonic())))
    error = controller_error(control)
    if error:
        raise RuntimeError(f"profile controller failed: {error}")
    raise TimeoutError("profile controller readiness timed out")


def wait_for_tab_page(
    session,
    module,
    start: int,
    expected_first: bytes,
    expected_last: bytes,
    timeout: float,
    iteration: int,
) -> dict[str, object]:
    expected_initial_page = [
        f"item-{index:05d}".encode()
        for index in range(module.NFR06_VISIBLE_CANDIDATE_COUNT)
    ]

    def initial_page_visible(data: bytes) -> bool:
        visible = module.visible_terminal_text(data)
        return (
            module.COMPLETION_PAGER_FOOTER in visible
            and b"1/20000" in visible
            and re.findall(rb"item-\d{5}", visible) == expected_initial_page
        )

    page_asserted_ns = wait_for_output_since(
        session,
        start,
        initial_page_visible,
        timeout,
        "initial Tab completion page",
        iteration,
    )
    response = bytes(session.data[start:])
    visible = module.visible_terminal_text(response)
    visible_candidates = re.findall(rb"item-\d{5}", visible)
    if visible_candidates != expected_initial_page:
        raise RuntimeError(
            "Tab profiler did not render the expected initial candidate page: "
            f"visible_count={len(visible_candidates)} "
            f"expected_count={len(expected_initial_page)}"
        )
    return {
        "first_candidate_visible": expected_first.decode("utf-8"),
        "last_candidate_hidden": expected_last not in visible_candidates,
        "visible_candidate_count": len(visible_candidates),
        "pager_total_visible": b"1/20000" in visible,
        "pager_footer_visible": module.COMPLETION_PAGER_FOOTER in visible,
        "response_bytes": len(response),
        "page_asserted_ns": page_asserted_ns,
    }


def start_profile(control: Path, timeout: float = REQUEST_TIMEOUT) -> str:
    write_request(control, "start.req")
    ack = wait_for_text(control / "start.ack", timeout)
    if "controller-is-main=NIL" not in ack or "profile-threads=all" not in ack:
        raise RuntimeError(f"profile start did not run off-thread for all threads: {ack}")
    if "main-sampling=off" not in ack or "worker-sampling=off" not in ack:
        raise RuntimeError(f"profile sampling was not gated off before target windows: {ack}")
    return ack


def arm_window(control: Path, index: int, timeout: float = REQUEST_TIMEOUT) -> str:
    write_request(control, "window-start.req", str(index))
    ack = wait_for_matching_text(control / "window-start.ack", f"index={index}", timeout)
    if "controller-is-main=NIL" not in ack:
        raise RuntimeError(f"sampling gate was not opened by controller thread: {ack}")
    return ack


def finish_window(control: Path, index: int, timeout: float = REQUEST_TIMEOUT) -> str:
    ack = wait_for_matching_text(control / "window-stop.ack", f"index={index}", timeout)
    if "controller-is-main=NIL" not in ack:
        raise RuntimeError(f"sampling gate was not closed by controller thread: {ack}")
    return ack


def stop_profile(control: Path, timeout: float = REQUEST_TIMEOUT) -> str:
    write_request(control, "stop.req")
    ack = wait_for_text(control / "stop.ack", timeout)
    if "controller-is-main=NIL" not in ack:
        raise RuntimeError(f"profile stop did not run on controller thread: {ack}")
    return ack


def run_exit_smoke(module, run_id: str) -> int:
    run_dir = OUT / f"exit-smoke-{run_id}"
    run_dir.mkdir(parents=True, exist_ok=False)
    marker_text = f"NSHELL_NFR06_EXIT_{uuid.uuid4().hex.upper()}_PROMPT"
    marker = marker_text.encode()
    session = module.PtySession(
        [str(BINARY), "--no-config"],
        FIXTURE,
        {
            **module.child_environment(run_dir / "home", marker_text),
            "SBCL_HOME": str(profile_sbcl_home(BINARY)),
        },
    )
    closed = False
    try:
        session.wait_for_marker(marker, timeout_seconds=30)
        session.wait_for_output(
            lambda data: module.prompt_render_complete(data, marker), timeout_seconds=20
        )
        status = graceful_exit(session)
        closed = True
        result = {
            "status": "success" if status == 0 else "error",
            "driver_pid": os.getpid(),
            "nshell_pid": session.pid,
            "nshell_exit_status": status,
            "transcript": str(run_dir / "transcript.bin"),
        }
        (run_dir / "transcript.bin").write_bytes(bytes(session.data))
        (run_dir / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0 if status == 0 else 1
    except Exception as error:
        result = {
            "status": "error",
            "driver_pid": os.getpid(),
            "nshell_pid": session.pid,
            "failure": f"{type(error).__name__}: {error}",
            "transcript": str(run_dir / "transcript.bin"),
        }
        (run_dir / "transcript.bin").write_bytes(bytes(session.data))
        (run_dir / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 1
    finally:
        if not closed:
            session.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--mode", choices=("cpu", "alloc"), default="cpu")
    parser.add_argument("--exit-smoke", action="store_true")
    parser.add_argument("--run-id", default=f"{time.strftime('%Y%m%dT%H%M%S')}-{uuid.uuid4().hex[:8]}")
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    ensure_fixture()
    if args.exit_smoke:
        return run_exit_smoke(measurement_module(), args.run_id)
    if args.iterations < 1 or args.iterations > 100:
        parser.error("--iterations must be between 1 and 100")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.run_id):
        parser.error("--run-id contains unsupported characters")

    run_dir = OUT / f"gate-{args.mode}-{args.iterations}-{args.run_id}"
    run_dir.mkdir(parents=True, exist_ok=False)
    control = run_dir / "control"
    control.mkdir()
    module = measurement_module()
    marker_text = f"NSHELL_NFR06_GATE_{uuid.uuid4().hex.upper()}_PROMPT"
    marker = marker_text.encode()
    command = "cat item-"
    graph = run_dir / f"{args.mode}.graph.txt"
    target_graph = run_dir / f"{args.mode}.target.graph.txt"
    target_flat = run_dir / f"{args.mode}.target.flat.txt"
    flat = run_dir / f"{args.mode}.flat.txt"
    metrics = run_dir / "operations.csv"
    controller = run_dir / "controller.lisp"
    controller.write_text(
        controller_source(
            command,
            control,
            graph,
            target_graph,
            target_flat,
            flat,
            metrics,
            args.iterations,
            args.mode,
            args.timeout,
        ),
        encoding="utf-8",
    )
    home = run_dir / "home"
    env = module.child_environment(home, marker_text)
    sbcl_home = profile_sbcl_home(BINARY)
    env["SBCL_HOME"] = str(sbcl_home)
    env["NSHELL_READER"] = "sexp"
    expected_output = module.completion_reference_output(
        BINARY, FIXTURE, "item-", OUT / "homes" / f"gate-ref-{args.run_id}"
    )
    expected = expected_output.splitlines()
    expected_set = set(expected)
    expected_hash = hashlib.sha256(expected_output).hexdigest()
    session = module.PtySession(
        [str(BINARY), "--no-config"],
        FIXTURE,
        env,
        terminal_size=module.NFR06_TERMINAL_SIZE,
    )
    install_incremental_cursor_query_handler(session, module)
    session_closed = False
    profile_started = False
    profile_stopped = False
    records: list[dict[str, object]] = []
    active_iteration = 0
    wait_phase = "initial prompt"
    result: dict[str, object] = {
        "status": "error",
        "mode": args.mode,
        "iterations_requested": args.iterations,
        "sbcl_home": str(sbcl_home),
        "driver_pid": os.getpid(),
        "nshell_pid": session.pid,
        "controller": str(controller),
        "control_dir": str(control),
        "sample_count_diagnostics": str(control / "sample-counts.txt"),
        "thread_counts_csv": str(control / "thread-counts.csv"),
        "transcript": str(run_dir / "transcript.bin"),
        "graph": str(graph),
        "target_graph": str(target_graph),
        "target_flat": str(target_flat),
        "flat": str(flat),
        "metrics": str(metrics),
        "sample_interval_seconds": SAMPLE_INTERVAL if args.mode == "cpu" else None,
        "alloc_interval_bytes": ALLOC_INTERVAL if args.mode == "alloc" else None,
        "reference_rows": len(expected),
        "reference_unique": len(expected_set),
        "reference_sha256": expected_hash,
    }
    try:
        if len(expected) != 20_000 or len(expected_set) != 20_000:
            raise RuntimeError(f"reference output shape invalid: rows={len(expected)} unique={len(expected_set)}")
        session.wait_for_marker(marker, timeout_seconds=30)
        session.wait_for_output(
            lambda data: module.prompt_render_complete(data, marker), timeout_seconds=20
        )
        load_form = f"(load {json.dumps(str(controller))})".encode()
        load_paste = module.BRACKETED_PASTE_START + load_form + module.BRACKETED_PASTE_END
        load_start = len(session.data)
        if os.write(session.master, load_paste) != len(load_paste):
            raise RuntimeError("controller load paste was incomplete")
        session.wait_for_output(
            lambda data: load_form in module.strip_terminal_sequences(data[load_start:]),
            timeout_seconds=20,
        )
        load_response_start = len(session.data)
        if os.write(session.master, b"\r") != 1:
            raise RuntimeError("controller load Enter write was incomplete")
        wait_for_controller_ready(
            session, control, load_response_start,
            lambda data: b"NFR06_V2_READY" in data, 30,
        )
        if not module.prompt_render_complete(bytes(session.data[load_response_start:]), marker):
            session.wait_for_output(
                lambda data: module.prompt_render_complete(data[load_response_start:], marker),
                timeout_seconds=20,
            )
        init_ack = wait_for_text(control / "init.ready")
        controller_ready = wait_for_text(control / "controller.ready")
        if "controller-is-main=NIL" not in controller_ready:
            raise RuntimeError(f"controller is not a distinct thread: {controller_ready}")
        expected_first = Path(os.fsdecode(expected[0])).name.encode()
        expected_last = Path(os.fsdecode(expected[-1])).name.encode()
        paste = module.BRACKETED_PASTE_START + command.encode() + module.BRACKETED_PASTE_END
        wait_phase = "command echo"
        input_start = len(session.data)
        if os.write(session.master, paste) != len(paste):
            raise RuntimeError("command paste was incomplete")
        wait_for_output_since(
            session,
            input_start,
            lambda data: command.encode() in module.strip_terminal_sequences(data),
            20,
            wait_phase,
            0,
        )
        session.pump_for(0.02)
        start_ack = start_profile(control, args.timeout)
        profile_started = True

        for index in range(args.iterations):
            active_iteration = index + 1
            iteration_deadline = time.monotonic() + args.timeout
            if index > 0:
                wait_phase = "pager dismissal"
                write_progress(
                    run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
                )
                dismissal_start = len(session.data)
                if os.write(session.master, b"\x1b") != 1:
                    raise RuntimeError(
                        f"operation {active_iteration}: Escape write was incomplete"
                    )
                wait_for_output_since(
                    session,
                    dismissal_start,
                    lambda data: (
                        command.encode() in module.strip_terminal_sequences(data)
                        and module.COMPLETION_PAGER_FOOTER
                        not in module.visible_terminal_text(data)
                    ),
                    remaining_seconds(iteration_deadline, active_iteration, wait_phase),
                    wait_phase,
                    active_iteration,
                )
                session.pump_for(0.02)

            arm_request_ns = time.monotonic_ns()
            wait_phase = "controller window start"
            write_progress(
                run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
            )
            arm_ack = arm_window(
                control,
                index,
                remaining_seconds(iteration_deadline, active_iteration, wait_phase),
            )
            arm_ack_ns = time.monotonic_ns()
            response_start = len(session.data)
            tab_started_ns = time.monotonic_ns()
            if os.write(session.master, b"\t") != 1:
                raise RuntimeError(f"operation {active_iteration}: Tab write was incomplete")
            tab_written_ns = time.monotonic_ns()
            wait_phase = "initial candidate page"
            write_progress(
                run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
            )
            output_assertions = wait_for_tab_page(
                session,
                module,
                response_start,
                expected_first,
                expected_last,
                remaining_seconds(iteration_deadline, active_iteration, wait_phase),
                active_iteration,
            )
            wait_phase = "controller window stop"
            write_progress(
                run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
            )
            window_ack = finish_window(
                control,
                index,
                remaining_seconds(iteration_deadline, active_iteration, wait_phase),
            )
            window_ack_ns = time.monotonic_ns()
            records.append(
                {
                    "iteration": index + 1,
                    "trigger": "Tab",
                    "input_writes": 1,
                    "input_bytes": 1,
                    "arm_request_ns": arm_request_ns,
                    "arm_ack_ns": arm_ack_ns,
                    "tab_write_start_ns": tab_started_ns,
                    "tab_write_complete_ns": tab_written_ns,
                    "arm_ack_to_tab_ms": (tab_started_ns - arm_ack_ns) / 1_000_000,
                    "tab_to_initial_page_ms": (
                        output_assertions["page_asserted_ns"] - tab_started_ns
                    )
                    / 1_000_000,
                    "controller_window_start": arm_ack,
                    "controller_window_stop": window_ack,
                    "output_assertions": {
                        key: value
                        for key, value in output_assertions.items()
                        if key != "page_asserted_ns"
                    },
                    "latency_ms": (
                        output_assertions["page_asserted_ns"] - tab_started_ns
                    )
                    / 1_000_000,
                }
            )
            wait_phase = "iteration complete"
            write_progress(
                run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
            )

        active_iteration = 0
        wait_phase = "profile report generation"
        write_progress(run_dir, args.mode, 0, args.iterations, len(records), wait_phase)
        stop_ack = stop_profile(control)
        profile_stopped = True
        target_ack = wait_for_text(control / "target-samples.ack")
        target_ack_match = re.search(r"(?:^|\s)target-samples=(\d+)(?:\s|$)", target_ack)
        if target_ack_match is None:
            raise RuntimeError(f"profile target-sample acknowledgement is invalid: {target_ack}")
        target_ack_samples = int(target_ack_match.group(1))
        graph_text = graph.read_text(encoding="utf-8", errors="replace")
        sample_match = re.search(r"Number of samples:\s*(\d+)", graph_text)
        if sample_match is None:
            raise RuntimeError("profile graph has no sample count")
        sample_count = int(sample_match.group(1))
        sample_diagnostics = read_profile_sample_diagnostics(
            control / "sample-counts.txt"
        )
        if sample_diagnostics is None:
            raise RuntimeError("profile did not write raw sample count diagnostics")
        result["profile_sample_counts"] = {
            **sample_diagnostics,
            "graph_header_count": sample_count,
            "stop_counter_minus_graph_header": (
                sample_diagnostics["sb_sprof_stop_counter"] - sample_count
            ),
        }
        if sample_count < 2_000:
            raise RuntimeError(f"{args.mode} profile sample count {sample_count} is below 2,000")
        if sample_count >= MAX_SAMPLES:
            raise RuntimeError(f"{args.mode} profile reached the {MAX_SAMPLES} sample cap")
        thread_counts = control / "thread-counts.csv"
        if not thread_counts.is_file():
            raise RuntimeError("profile did not write thread sample counts")
        thread_rows = list(csv.DictReader(thread_counts.open(encoding="utf-8")))
        if not thread_rows:
            raise RuntimeError("profile thread counts are empty")
        thread_records = [
            {
                "thread_id": int(row["thread_id"]),
                "thread": row["thread"],
                "role": row["role"],
                "samples": int(row["samples"]),
            }
            for row in thread_rows
        ]
        thread_count_total = sum(row["samples"] for row in thread_records)
        result["profile_sample_counts"]["thread_counts_csv_total"] = thread_count_total
        validate_profile_sample_counts(sample_count, sample_diagnostics, thread_count_total)
        controller_samples = sum(row["samples"] for row in thread_records if row["role"] == "controller")
        if controller_samples != 0:
            raise RuntimeError(f"controller received {controller_samples} samples: {thread_records}")
        main_samples = sum(row["samples"] for row in thread_records if row["role"] == "main")
        worker_samples = sum(
            row["samples"] for row in thread_records if row["role"] == "pipeline-worker"
        )
        target_thread_samples = main_samples + worker_samples
        result["profile_sample_counts"]["target_thread_count"] = target_thread_samples
        if target_ack_samples != target_thread_samples:
            raise RuntimeError(
                f"target acknowledgement samples {target_ack_samples} "
                f"do not match thread counts {target_thread_samples}"
            )
        if target_thread_samples <= 0:
            raise RuntimeError(f"no completion-thread samples in profile: {thread_records}")
        if args.mode == "cpu" and target_thread_samples < 2_000:
            raise RuntimeError(
                f"CPU completion-thread sample count {target_thread_samples} is below 2,000"
            )
        target_graph_text = target_graph.read_text(encoding="utf-8", errors="replace")
        target_sample_match = re.search(r"Number of samples:\s*(\d+)", target_graph_text)
        if target_sample_match is None or int(target_sample_match.group(1)) != target_thread_samples:
            raise RuntimeError(
                f"target graph samples {target_sample_match.group(1) if target_sample_match else None} "
                f"do not match thread counts {target_thread_samples}"
            )
        target_flat_text = target_flat.read_text(encoding="utf-8", errors="replace")
        target_flat_sample_match = re.search(r"Number of samples:\s*(\d+)", target_flat_text)
        if target_flat_sample_match is None or int(target_flat_sample_match.group(1)) != target_thread_samples:
            raise RuntimeError(
                f"target flat samples "
                f"{target_flat_sample_match.group(1) if target_flat_sample_match else None} "
                f"do not match thread counts {target_thread_samples}"
            )
        metric_lines = [
            line for line in metrics.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")
        ]
        metrics_rows = list(csv.DictReader(metric_lines))
        if len(metrics_rows) != args.iterations:
            raise RuntimeError(f"per-operation accounting rows={len(metrics_rows)} expected={args.iterations}")
        if any(int(row["bytes_cons"]) < 0 or int(row["gc_run_delta_ticks"]) < 0 for row in metrics_rows):
            raise RuntimeError("per-operation consing or GC delta was negative")
        write_request(control, "shutdown.req")
        controller_stopped = wait_for_text(control / "controller.stopped")
        if "controller-is-main=NIL" not in controller_stopped:
            raise RuntimeError(f"controller did not stop off-main: {controller_stopped}")
        clear_input_start = len(session.data)
        if os.write(session.master, b"\x03") != 1:
            raise RuntimeError("Ctrl-C input-clear write was incomplete")
        session.wait_for_output(
            lambda data: module.prompt_render_complete(data, marker),
            timeout_seconds=20,
        )
        if command.encode() in module.visible_terminal_text(
            bytes(session.data[clear_input_start:])
        ):
            raise RuntimeError("input command remained visible after Ctrl-C")
        exit_status = graceful_exit(session)
        session_closed = True
        if exit_status != 0:
            raise RuntimeError(f"nshell exit status was {exit_status}")
        result.update({
            "status": "success",
            "iterations_validated": len(records),
            "iterations_completed": len(records),
            "operation_records": records,
            "profile_start_ack": start_ack,
            "profile_stop_ack": stop_ack,
            "profile_samples": sample_count,
            "profile_sample_counts": result["profile_sample_counts"],
            "thread_counts": thread_records,
            "pipeline_worker_samples": worker_samples,
            "completion_thread_samples": target_thread_samples,
            "target_thread_ack": target_ack,
            "nshell_exit_status": exit_status,
            "controller_ready": controller_ready,
            "controller_stopped": controller_stopped,
            "profile_boundary": "controller samples the main and pipeline worker threads from target Tab input-event entry through render-prompt-cont completion, including pager rendering and finish-output; PTY assertions verify the first page",
            "cache_policy": "one fresh nshell process; the complete -C reference preflight warms filesystem cache outside the measured session; rulebase-cache presence is recorded before and after each measured Tab",
        })
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except Exception as error:
        result.update({
            "status": "error",
            "failure": f"{type(error).__name__}: {error}",
            "iterations_validated": len(records),
            "iterations_completed": len(records),
            "waiting_at": {"iteration": active_iteration, "phase": wait_phase},
        })
        if profile_started and not profile_stopped:
            if not (control / "controller.error").is_file() and not (control / "stop.req").is_file():
                write_request(control, "stop.req")
            report_deadline = time.monotonic() + max(60.0, args.timeout)
            while not graph.is_file() and time.monotonic() < report_deadline:
                time.sleep(0.05)
            controller_error_path = control / "controller.error"
            if controller_error_path.is_file():
                result["controller_failure"] = controller_error_path.read_text(encoding="utf-8").strip()
        try:
            partial_diagnostics = read_profile_sample_diagnostics(
                control / "sample-counts.txt"
            )
        except RuntimeError as diagnostic_error:
            result["profile_sample_diagnostics_failure"] = str(diagnostic_error)
        else:
            if partial_diagnostics is not None:
                existing_diagnostics = result.setdefault("profile_sample_counts", {})
                if isinstance(existing_diagnostics, dict):
                    existing_diagnostics.update(partial_diagnostics)
        result["partial_profile_samples"] = profile_sample_count(graph)
        write_progress(
            run_dir,
            args.mode,
            active_iteration,
            args.iterations,
            len(records),
            wait_phase,
            status="error",
        )
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1
    finally:
        (run_dir / "transcript.bin").write_bytes(bytes(session.data))
        (run_dir / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if not session_closed:
            session.close()


if __name__ == "__main__":
    raise SystemExit(main())
