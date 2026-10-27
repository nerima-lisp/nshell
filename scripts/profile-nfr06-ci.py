#!/usr/bin/env python3
"""Measure repeated interactive NFR-06 completion commands with gated sb-sprof."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEASURE_SCRIPT = ROOT / "scripts/measure-nfr-04-06.py"
OUT = Path(os.environ["NFR06_PROFILE_OUTPUT"]).resolve()
FIXTURE = Path(os.environ["NFR06_PROFILE_FIXTURE"]).resolve()
BINARY = Path(os.environ["NFR06_PROFILE_BINARY"]).resolve()
SAMPLE_INTERVAL = 0.00005
ALLOC_INTERVAL = 65536
MAX_SAMPLES = 100000
REQUEST_TIMEOUT = 60.0


def profile_sbcl_home(binary: Path) -> Path:
    wrapped_binary = binary.resolve().parent / ".nshell-wrapped"
    if not wrapped_binary.is_file():
        raise RuntimeError(f"nshell wrapper does not exist: {wrapped_binary}")
    match = re.search(
        r'exec -a "\$0" "([^"\n]+/bin/sbcl)"\s+--noinform --core ',
        wrapped_binary.read_text(encoding="utf-8"),
    )
    if match is None:
        raise RuntimeError(f"could not find the SBCL executable in {wrapped_binary}")
    executable = Path(match.group(1)).resolve()
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
            return path.read_text(encoding="utf-8").strip()
        time.sleep(0.002)
    raise TimeoutError(f"timed out waiting for {path}")


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
    counts = {
        "sb_sprof_stop_counter": diagnostics["sb_sprof_stop_counter"],
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
    source = r'''(cl:pushnew
  (cl:symbol-function
   (cl:find-symbol "MODULE-PROVIDE-CONTRIB" :sb-impl))
  sb-ext:*module-provider-functions*)
(cl:require :sb-sprof)
(cl:defparameter nshell.user::*nfr06-v2-command* __COMMAND__)
(cl:defparameter nshell.user::*nfr06-v2-control-dir* __CONTROL__)
(cl:defparameter nshell.user::*nfr06-v2-graph-path* __GRAPH__)
(cl:progn
  (cl:defparameter nshell.user::*nfr06-v2-target-graph-path* __TARGET_GRAPH__)
  (cl:defparameter nshell.user::*nfr06-v2-target-flat-path* __TARGET_FLAT__))
(cl:defparameter nshell.user::*nfr06-v2-flat-path* __FLAT__)
(cl:defparameter nshell.user::*nfr06-v2-metrics-path* __METRICS__)
(cl:defparameter nshell.user::*nfr06-v2-iterations* __ITERATIONS__)
(cl:defparameter nshell.user::*nfr06-v2-mode* __MODE__)
(cl:defparameter nshell.user::*nfr06-v2-main-thread* (sb-thread:main-thread))
(cl:defparameter nshell.user::*nfr06-v2-controller-thread* nil)
(cl:defparameter nshell.user::*nfr06-v2-window-threads* nil)
(cl:defparameter nshell.user::*nfr06-v2-profiled-workers* nil)
(cl:defparameter nshell.user::*nfr06-v2-thread-ids* (cl:make-hash-table :test 'cl:eq))
(cl:defparameter nshell.user::*nfr06-v2-next-thread-id* 0)
(cl:defparameter nshell.user::*nfr06-v2-render-done* (sb-thread:make-semaphore :name "nfr06 render done"))
(cl:defparameter nshell.user::*nfr06-v2-profile-active* nil)
(cl:defparameter nshell.user::*nfr06-v2-window-open* nil)
(cl:defparameter nshell.user::*nfr06-v2-window-index* nil)
(cl:defparameter nshell.user::*nfr06-v2-enter-count* 0)
(cl:defparameter nshell.user::*nfr06-v2-target-count* 0)
(cl:defparameter nshell.user::*nfr06-v2-enter-sequence* nil)
(cl:defparameter nshell.user::*nfr06-v2-target-sequence* nil)
(cl:defparameter nshell.user::*nfr06-v2-measurements* nil)

(cl:defun nshell.user::nfr06-v2-path (name)
  (cl:concatenate 'cl:string nshell.user::*nfr06-v2-control-dir* "/" name))

(cl:defun nshell.user::nfr06-v2-write-file (name text)
  (cl:with-open-file (stream (nshell.user::nfr06-v2-path name)
                             :direction :output :if-exists :supersede
                             :if-does-not-exist :create)
    (cl:write-line text stream)))

(cl:defun nshell.user::nfr06-v2-read-file (name)
  (cl:with-open-file (stream (nshell.user::nfr06-v2-path name) :direction :input)
    (cl:read-line stream nil "")))

(cl:defun nshell.user::nfr06-v2-worker-thread-p (thread)
  (cl:let ((name (sb-thread:thread-name thread))
           (prefix "nshell pipeline stage "))
    (cl:and (cl:stringp name)
            (cl:>= (cl:length name) (cl:length prefix))
            (cl:string= prefix name :end2 (cl:length prefix)))))

(cl:defun nshell.user::nfr06-v2-await-sampling-enabled (thread index)
  (cl:loop repeat 2000
           until (cl:= (sb-thread::%symbol-value-in-thread
                        'sb-thread::*sprof-enable* thread)
                       1)
           do (cl:sleep 0.001)
           finally (cl:when (cl:/= (sb-thread::%symbol-value-in-thread
                                    'sb-thread::*sprof-enable* thread)
                                   1)
                     (cl:error "thread ~A did not enable sampling at index ~D"
                               (sb-thread:thread-name thread) index))))

(cl:defun nshell.user::nfr06-v2-start-window-thread (thread index)
  (cl:unless (cl:member thread nshell.user::*nfr06-v2-window-threads* :test #'cl:eq)
    (sb-sprof:start-sampling thread)
    (nshell.user::nfr06-v2-await-sampling-enabled thread index)
    (cl:push thread nshell.user::*nfr06-v2-window-threads*)
    (cl:when (nshell.user::nfr06-v2-worker-thread-p thread)
      (cl:pushnew thread nshell.user::*nfr06-v2-profiled-workers* :test #'cl:eq)))
  thread)

(cl:defun nshell.user::nfr06-v2-discover-workers (index)
  (cl:dolist (thread (sb-thread:list-all-threads))
    (cl:when (cl:and (sb-thread:thread-alive-p thread)
                     (nshell.user::nfr06-v2-worker-thread-p thread))
      (nshell.user::nfr06-v2-start-window-thread thread index))))

(cl:defun nshell.user::nfr06-v2-stop-window-threads ()
  (cl:dolist (thread nshell.user::*nfr06-v2-window-threads*)
    (sb-sprof:stop-sampling thread))
  (cl:setf nshell.user::*nfr06-v2-window-threads* cl:nil))

(cl:defun nshell.user::nfr06-v2-thread-id (thread)
  (cl:or (cl:gethash thread nshell.user::*nfr06-v2-thread-ids*)
         (cl:setf (cl:gethash thread nshell.user::*nfr06-v2-thread-ids*)
                  (cl:incf nshell.user::*nfr06-v2-next-thread-id*))))

(cl:defun nshell.user::nfr06-v2-filter-samples (samples predicate)
  (cl:let ((selected cl:nil)
           (total-length 0)
           (trace-count 0))
    (sb-sprof:map-traces
     (cl:lambda (thread trace)
       (cl:when (cl:funcall predicate thread)
         (cl:destructuring-bind (source start end) trace
           (cl:push (cl:list thread source start end) selected)
           (cl:incf total-length (- end start))
           (cl:incf trace-count))))
     samples)
    (cl:let ((filtered (cl:copy-structure samples))
             (vector (cl:make-array total-length))
             (sampled-threads
               (cl:remove-if-not
                (cl:lambda (entry) (cl:funcall predicate (cl:first entry)))
                (sb-sprof::samples-sampled-threads samples)))
             (index 0))
      (cl:dolist (entry (cl:nreverse selected))
        (cl:destructuring-bind (thread source start end) entry
          (cl:let ((new-end (+ index (- end start))))
            (cl:setf (cl:aref vector index) (cl:cons 'sb-sprof::trace-start new-end)
                     (cl:aref vector (cl:1+ index)) thread)
            (cl:replace vector source :start1 (+ index 2) :start2 (+ start 2) :end2 end)
            (cl:setf index new-end))))
      (cl:setf (sb-sprof::samples-vector filtered) vector
               (sb-sprof::samples-trace-count filtered) trace-count
               (sb-sprof::samples-unique-trace-count filtered) trace-count
               (sb-sprof::samples-sampled-threads filtered) sampled-threads)
      filtered)))

(cl:defun nshell.user::nfr06-v2-vector-trace-count (samples)
  (cl:let* ((vector (sb-sprof::samples-vector samples))
            (vector-length (cl:length vector))
            (index 0)
            (count 0))
    (cl:loop while (cl:< index vector-length)
             do (cl:let ((marker (cl:aref vector index)))
                  (cl:unless (cl:and (cl:consp marker)
                                     (cl:eq (cl:car marker) 'sb-sprof::trace-start)
                                     (cl:integerp (cl:cdr marker))
                                     (cl:< index (cl:cdr marker))
                                     (cl:<= (cl:cdr marker) vector-length))
                    (cl:error "invalid raw sample trace marker at index ~D" index))
                  (cl:incf count)
                  (cl:setf index (cl:cdr marker))))
    count))

(cl:defun nshell.user::nfr06-v2-write-thread-counts ()
  (cl:let* ((counts (cl:make-hash-table :test 'cl:eq))
            (threads (cl:remove-duplicates
                      (cl:append (cl:list nshell.user::*nfr06-v2-main-thread*
                                           nshell.user::*nfr06-v2-controller-thread*)
                                 nshell.user::*nfr06-v2-profiled-workers*)
                      :test #'cl:eq))
            (samples (cl:symbol-value (cl:find-symbol "*SAMPLES*" :sb-sprof)))
            (vector (sb-sprof::samples-vector samples))
            (raw-vector-count
              (nshell.user::nfr06-v2-vector-trace-count samples))
            (map-trace-count 0))
    (sb-sprof:map-traces
     (cl:lambda (thread trace)
       (cl:declare (cl:ignore trace))
       (cl:pushnew thread threads :test #'cl:eq)
       (cl:incf map-trace-count)
       (cl:incf (cl:gethash thread counts 0)))
     samples)
    (cl:with-open-file (stream (cl:concatenate 'cl:string
                                                nshell.user::*nfr06-v2-control-dir*
                                                "/thread-counts.csv")
                               :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
      (cl:write-line "thread_id,thread,role,samples" stream)
      (cl:dolist (thread threads)
        (cl:format stream "~D,~A,~A,~D~%"
                   (nshell.user::nfr06-v2-thread-id thread)
                   (sb-thread:thread-name thread)
                   (cl:cond ((cl:eq thread nshell.user::*nfr06-v2-main-thread*) "main")
                            ((cl:eq thread nshell.user::*nfr06-v2-controller-thread*) "controller")
                            ((nshell.user::nfr06-v2-worker-thread-p thread) "pipeline-worker")
                            (cl:t "other"))
                   (cl:gethash thread counts 0))))
    (nshell.user::nfr06-v2-write-file
     "sample-counts.txt"
     (cl:format cl:nil
                "sb_sprof_stop_counter=~D~%raw_vector_trace_count=~D~%map_traces_count=~D~%samples_vector_length=~D~%"
                (sb-sprof::samples-trace-count samples)
                raw-vector-count
                map-trace-count
                (cl:length vector)))))

(cl:defun nshell.user::nfr06-v2-write-metrics ()
  (cl:unless (cl:and (cl:= nshell.user::*nfr06-v2-enter-count*
                            nshell.user::*nfr06-v2-iterations*)
                     (cl:= nshell.user::*nfr06-v2-target-count*
                            nshell.user::*nfr06-v2-iterations*)
                     (cl:= (cl:length nshell.user::*nfr06-v2-measurements*)
                            nshell.user::*nfr06-v2-iterations*))
    (cl:error "profile operation counts mismatch: Enter=~D target=~D metrics=~D expected=~D"
              nshell.user::*nfr06-v2-enter-count*
              nshell.user::*nfr06-v2-target-count*
              (cl:length nshell.user::*nfr06-v2-measurements*)
              nshell.user::*nfr06-v2-iterations*))
  (cl:with-open-file (stream nshell.user::*nfr06-v2-metrics-path*
                             :direction :output :if-exists :supersede
                             :if-does-not-exist :create)
    (cl:format stream "# input_enter_count=~D~%# target_call_count=~D~%# input_enter_sequence=~{~D~^,~}~%# target_call_sequence=~{~D~^,~}~%"
                nshell.user::*nfr06-v2-enter-count*
                nshell.user::*nfr06-v2-target-count*
                (cl:nreverse nshell.user::*nfr06-v2-enter-sequence*)
                (cl:nreverse nshell.user::*nfr06-v2-target-sequence*))
    (cl:write-line "iteration,bytes_cons,gc_run_delta_ticks,cache_before,cache_after" stream)
    (cl:dolist (row (cl:nreverse nshell.user::*nfr06-v2-measurements*))
      (cl:format stream "~D,~D,~D,~D,~D~%"
                 (cl:first row) (cl:second row) (cl:third row)
                 (cl:fourth row) (cl:fifth row)))))

(cl:defun nshell.user::nfr06-v2-start-profile ()
  (sb-ext:gc :full cl:t)
  (sb-sprof:reset)
  (sb-sprof:start-profiling __PROFILE_OPTIONS__ :threads :all)
  (cl:setf nshell.user::*nfr06-v2-profile-active* cl:t)
  (cl:dolist (thread (sb-thread:list-all-threads))
    (sb-sprof:stop-sampling thread))
  (nshell.user::nfr06-v2-write-file
   "start.ack"
   (cl:format cl:nil "started mode=~A profile-threads=all controller-thread=~A controller-is-main=~A target-thread=~A main-sampling=off worker-sampling=off"
              nshell.user::*nfr06-v2-mode*
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
               (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*))))

(cl:defun nshell.user::nfr06-v2-target-window (index)
  (cl:when nshell.user::*nfr06-v2-window-open*
    (cl:error "target window already open"))
  (cl:setf nshell.user::*nfr06-v2-window-index* index
           nshell.user::*nfr06-v2-window-open* cl:t
           nshell.user::*nfr06-v2-window-threads* cl:nil)
  (nshell.user::nfr06-v2-start-window-thread nshell.user::*nfr06-v2-main-thread* index)
  (nshell.user::nfr06-v2-discover-workers index)
  (cl:let ((sample-start-ticks (cl:get-internal-real-time)))
  (nshell.user::nfr06-v2-write-file
   "window-start.ack"
   (cl:format cl:nil "started index=~D sample-start-ticks=~D sampled-thread-count=~D sampled-workers=~{~A~^|~} controller-thread=~A controller-is-main=~A target-thread=~A"
              index
              sample-start-ticks
              (cl:length nshell.user::*nfr06-v2-window-threads*)
              (cl:mapcar #'sb-thread:thread-name
                         (cl:remove-if-not #'nshell.user::nfr06-v2-worker-thread-p
                                           nshell.user::*nfr06-v2-window-threads*))
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
              (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*)))
  (cl:let ((rendered
             (cl:let ((deadline (+ (cl:get-internal-real-time)
                                   (cl:floor (* __RENDER_TIMEOUT_SECONDS__ cl:internal-time-units-per-second)))))
               (cl:loop while (cl:< (cl:get-internal-real-time) deadline)
                        do (cl:when (sb-thread:wait-on-semaphore
                                     nshell.user::*nfr06-v2-render-done* :timeout 0.002)
                             (cl:return cl:t))
                           (nshell.user::nfr06-v2-discover-workers index)))))
  (cl:unless rendered
    (nshell.user::nfr06-v2-stop-window-threads)
    (cl:setf nshell.user::*nfr06-v2-window-open* cl:nil)
    (cl:error "completion render semaphore timed out at index ~D" index))
  (cl:let ((render-done-ticks (cl:get-internal-real-time))
           (window-thread-snapshot (cl:copy-list nshell.user::*nfr06-v2-window-threads*)))
  (nshell.user::nfr06-v2-stop-window-threads)
  (cl:setf nshell.user::*nfr06-v2-window-open* cl:nil)
  (cl:let ((sample-stop-ticks (cl:get-internal-real-time)))
  (nshell.user::nfr06-v2-write-file
   "window-stop.ack"
   (cl:format cl:nil "stopped index=~D sample-start-ticks=~D render-done-ticks=~D sample-stop-ticks=~D ticks-per-second=~D sampled-workers=~{~A~^|~} controller-thread=~A controller-is-main=~A target-thread=~A"
              index
              sample-start-ticks
              render-done-ticks
              sample-stop-ticks
              cl:internal-time-units-per-second
              (cl:mapcar #'sb-thread:thread-name
                         (cl:remove-if-not #'nshell.user::nfr06-v2-worker-thread-p
                                           window-thread-snapshot))
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
               (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*))))))))

(cl:defun nshell.user::nfr06-v2-stop-profile ()
  (cl:when nshell.user::*nfr06-v2-window-open*
    (cl:error "cannot stop profile while target window is open"))
  (sb-sprof:stop-profiling)
  (cl:let ((samples (cl:symbol-value (cl:find-symbol "*SAMPLES*" :sb-sprof))))
    (cl:unless (cl:plusp (cl:length (sb-sprof::samples-vector samples)))
      (cl:multiple-value-bind (vector unique-trace-count sampled-threads)
          (sb-sprof::convert-raw-data)
        (cl:setf (sb-sprof::samples-vector samples) vector
                 (sb-sprof::samples-unique-trace-count samples) unique-trace-count
                 (sb-sprof::samples-sampled-threads samples) sampled-threads)))
    (cl:let* ((raw-vector-count
                (nshell.user::nfr06-v2-vector-trace-count samples))
              (report-samples (cl:copy-structure samples)))
      (cl:setf (sb-sprof::samples-trace-count report-samples) raw-vector-count)
      (nshell.user::nfr06-v2-write-thread-counts)
      (cl:let ((call-graph
                 (sb-sprof::make-call-graph-1 report-samples most-positive-fixnum)))
        (cl:with-open-file (stream nshell.user::*nfr06-v2-graph-path*
                                   :direction :output :if-exists :supersede
                                   :if-does-not-exist :create)
          (sb-sprof:report :type :graph :call-graph call-graph :stream stream
                           :min-percent 0 :show-progress cl:nil))
        (cl:with-open-file (stream nshell.user::*nfr06-v2-flat-path*
                                   :direction :output :if-exists :supersede
                                   :if-does-not-exist :create)
          (sb-sprof:report :type :flat :call-graph call-graph :stream stream
                           :min-percent 0 :show-progress cl:nil)))))
  (cl:let* ((samples (cl:symbol-value (cl:find-symbol "*SAMPLES*" :sb-sprof)))
          (target-samples
            (nshell.user::nfr06-v2-filter-samples
             samples
             (cl:lambda (thread)
               (cl:or (cl:eq thread nshell.user::*nfr06-v2-main-thread*)
                      (nshell.user::nfr06-v2-worker-thread-p thread)))))
          (target-count (sb-sprof::samples-trace-count target-samples)))
  (cl:when (cl:plusp target-count)
    (cl:let ((target-graph
               (sb-sprof::make-call-graph-1 target-samples most-positive-fixnum)))
      (cl:progn
  (cl:with-open-file
      (stream nshell.user::*nfr06-v2-target-graph-path*
              :direction :output :if-exists :supersede :if-does-not-exist :create)
    (sb-sprof:report :type :graph :call-graph target-graph :stream stream
                     :min-percent 0 :show-progress cl:nil))
  (cl:with-open-file
      (stream nshell.user::*nfr06-v2-target-flat-path*
              :direction :output :if-exists :supersede :if-does-not-exist :create)
    (sb-sprof:report :type :flat :call-graph target-graph :stream stream
                     :min-percent 0 :show-progress cl:nil)))))
  (nshell.user::nfr06-v2-write-file
   "target-samples.ack"
   (cl:format cl:nil "target-samples=~D target-workers=~{~A~^|~}"
              target-count
              (cl:mapcar #'sb-thread:thread-name
                         (cl:remove-if-not #'nshell.user::nfr06-v2-worker-thread-p
                                           nshell.user::*nfr06-v2-profiled-workers*)))))
  (nshell.user::nfr06-v2-write-metrics)
  (cl:setf nshell.user::*nfr06-v2-profile-active* cl:nil)
  (nshell.user::nfr06-v2-write-file
   "stop.ack"
   (cl:format cl:nil "stopped controller-thread=~A controller-is-main=~A target-count=~D"
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
              nshell.user::*nfr06-v2-target-count*)))

(cl:defun nshell.user::nfr06-v2-controller ()
  (cl:handler-case
      (cl:progn
        (nshell.user::nfr06-v2-write-file
         "controller.ready"
         (cl:format cl:nil "ready controller-thread=~A controller-is-main=~A target-thread=~A"
                    (sb-thread:thread-name sb-thread:*current-thread*)
                    (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
                    (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*)))
        (cl:loop
          (cl:when (cl:probe-file (nshell.user::nfr06-v2-path "start.req"))
            (cl:delete-file (nshell.user::nfr06-v2-path "start.req"))
            (nshell.user::nfr06-v2-start-profile))
          (cl:when (cl:and nshell.user::*nfr06-v2-profile-active*
                           (cl:probe-file (nshell.user::nfr06-v2-path "window-start.req")))
            (cl:let ((index (cl:parse-integer
                             (nshell.user::nfr06-v2-read-file "window-start.req"))))
              (cl:delete-file (nshell.user::nfr06-v2-path "window-start.req"))
              (nshell.user::nfr06-v2-target-window index)))
          (cl:when (cl:and nshell.user::*nfr06-v2-profile-active*
                           (cl:probe-file (nshell.user::nfr06-v2-path "stop.req")))
            (cl:delete-file (nshell.user::nfr06-v2-path "stop.req"))
            (nshell.user::nfr06-v2-stop-profile))
          (cl:when (cl:probe-file (nshell.user::nfr06-v2-path "shutdown.req"))
            (cl:delete-file (nshell.user::nfr06-v2-path "shutdown.req"))
            (cl:return))
          (cl:sleep 0.002))
        (nshell.user::nfr06-v2-write-file
         "controller.stopped"
         (cl:format cl:nil "stopped controller-thread=~A controller-is-main=~A"
                    (sb-thread:thread-name sb-thread:*current-thread*)
                    (cl:eq sb-thread:*current-thread* (sb-thread:main-thread)))))
    (cl:error (condition)
      (cl:when nshell.user::*nfr06-v2-profile-active*
        (cl:ignore-errors
          (nshell.user::nfr06-v2-stop-window-threads)
          (cl:setf nshell.user::*nfr06-v2-window-open* cl:nil)
          (nshell.user::nfr06-v2-stop-profile)))
      (nshell.user::nfr06-v2-write-file
       "controller.error"
       (cl:format cl:nil "type=~A condition=~A" (cl:type-of condition) condition)))))



(cl:setf nshell.user::*nfr06-v2-controller-thread*
         (sb-thread:make-thread #'nshell.user::nfr06-v2-controller
                                :name "nfr06-v2-controller"))

(cl:let* ((package (cl:find-package "NSHELL.PRESENTATION"))
          (input-symbol (cl:find-symbol "%PROCESS-INPUT-EVENT" package))
          (input-original (cl:symbol-function input-symbol))
          (complete-symbol (cl:find-symbol "%EXECUTE-COMPLETE-COMMAND" package))
          (complete-original (cl:symbol-function complete-symbol)))
  (cl:setf (cl:symbol-function input-symbol)
           (cl:lambda (event)
             (cl:when (cl:and (cl:eq :enter (nshell.domain.input:key-event-type event))
                              (cl:string= (nshell.presentation::input-state-buffer
                                           nshell.presentation::*input-state*)
                                          nshell.user::*nfr06-v2-command*))
               (cl:incf nshell.user::*nfr06-v2-enter-count*)
               (cl:push nshell.user::*nfr06-v2-enter-count*
                        nshell.user::*nfr06-v2-enter-sequence*))
             (cl:funcall input-original event)))
  (cl:setf (cl:symbol-function complete-symbol)
           (cl:lambda (ast text &optional evaluator)
             (cl:if (cl:string= text nshell.user::*nfr06-v2-command*)
                    (cl:let* ((index (cl:incf nshell.user::*nfr06-v2-target-count*))
                              (bytes-before (sb-ext:get-bytes-consed))
                              (gc-before sb-ext:*gc-run-time*)
                              (cache-before
                                (cl:not (cl:null
                                  (nshell.domain.completion::rule-knowledge-base-%rulebase-cache
                                   nshell.presentation::*kb*))))
                              (continuation
                                (cl:funcall complete-original ast text evaluator)))
                      (cl:push index nshell.user::*nfr06-v2-target-sequence*)
                      (cl:unless (cl:and nshell.user::*nfr06-v2-window-open*
                                         (cl:= nshell.user::*nfr06-v2-window-index*
                                               (cl:1- index)))
                        (cl:error "target completion outside its controller window: index=~D window=~S"
                                  index nshell.user::*nfr06-v2-window-index*))
                      (cl:lambda ()
                        (cl:multiple-value-prog1
                            (cl:funcall continuation)
                          (cl:let* ((bytes-cons (- (sb-ext:get-bytes-consed) bytes-before))
                                    (gc-delta (- sb-ext:*gc-run-time* gc-before))
                                    (cache-after
                                      (cl:not (cl:null
                                        (nshell.domain.completion::rule-knowledge-base-%rulebase-cache
                                         nshell.presentation::*kb*)))))
                            (cl:push (cl:list index bytes-cons gc-delta
                                              (cl:if cache-before 1 0)
                                              (cl:if cache-after 1 0))
                                     nshell.user::*nfr06-v2-measurements*)
                            (sb-thread:signal-semaphore nshell.user::*nfr06-v2-render-done*)))))
                    (cl:funcall complete-original ast text evaluator)))))

(nshell.user::nfr06-v2-write-file "init.ready" "completion wrapper installed")
(cl:format cl:*standard-output* "NFR06_V2_READY~%")
(cl:finish-output cl:*standard-output*)
'''
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


def wait_for_validated_render(session, module, control: Path, start: int, marker: bytes,
                              expected_output: bytes, expected: list[bytes], expected_set: set[bytes],
                              expected_hash: str, timeout: float) -> dict[str, object]:
    # Match the NFR harness while draining the PTY; validate candidate order after the prompt returns.
    render_timing = session.wait_for_completion_render(
        start, marker, timeout_seconds=timeout
    )
    prompt_asserted_ns = int(render_timing["prompt_render_complete_ns"])
    error = controller_error(control)
    if error:
        raise RuntimeError(f"profile controller failed: {error}")

    response = bytes(session.data[start:])
    rows = [
        line
        for raw_line in response.splitlines()
        if (line := module.visible_terminal_text(raw_line).rstrip(b"\r")) in expected_set
    ]
    if len(rows) != len(expected) or rows != expected or set(rows) != expected_set:
        raise RuntimeError(
            f"candidate parity mismatch rows={len(rows)} unique={len(set(rows))} "
            f"expected={len(expected)}"
        )
    starts = [m.start() for m in re.finditer(rb"\x1b\]133;C\x1b\\", response)]
    ends = [m.start() for m in re.finditer(rb"\x1b\]133;D;0\x1b\\", response)]
    if len(starts) != 1 or len(ends) != 1:
        raise RuntimeError(f"expected one OSC 133 C/D frame, got C={len(starts)} D;0={len(ends)}")
    output_hash = hashlib.sha256(b"\n".join(rows) + b"\n").hexdigest()
    if output_hash != expected_hash:
        raise RuntimeError(f"candidate output hash mismatch: {output_hash}")
    if not module.prompt_render_complete(response, marker):
        raise RuntimeError("completion prompt or cursor restoration assertion failed")
    if response.rfind(marker) <= response.rfind(b"\x1b]133;D;0\x1b\\"):
        raise RuntimeError("completion prompt marker preceded command-frame completion")
    return {
        "osc133_c": len(starts),
        "osc133_d0": len(ends),
        "candidate_count": len(rows),
        "candidate_unique": len(set(rows)),
        "output_sha256": output_hash,
        "prompt_render_complete": True,
        "cursor_restore": True,
        "response_bytes": len(response),
        "first_command_frame_seen_ns": None,
        "first_command_end_seen_ns": None,
        "prompt_asserted_ns": prompt_asserted_ns,
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
    command = module.completion_command(BINARY, FIXTURE, "item-")[-1]
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
    session = module.PtySession([str(BINARY), "--no-config"], FIXTURE, env)
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
        start_ack = start_profile(control, args.timeout)
        profile_started = True

        paste = module.BRACKETED_PASTE_START + command.encode() + module.BRACKETED_PASTE_END
        for index in range(args.iterations):
            active_iteration = index + 1
            iteration_deadline = time.monotonic() + args.timeout
            wait_phase = "command echo"
            write_progress(
                run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
            )
            input_start = len(session.data)
            if os.write(session.master, paste) != len(paste):
                raise RuntimeError(f"operation {active_iteration}: command paste was incomplete")
            wait_for_output_since(
                session,
                input_start,
                lambda data: command.encode() in module.strip_terminal_sequences(data),
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
            enter_started = time.monotonic_ns()
            if os.write(session.master, b"\r") != 1:
                raise RuntimeError(f"operation {active_iteration}: Enter write was incomplete")
            enter_written_ns = time.monotonic_ns()
            wait_phase = "completion render and output validation"
            write_progress(
                run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
            )
            output_assertions = wait_for_validated_render(
                session, module, control, response_start, marker, expected_output,
                expected,
                expected_set,
                expected_hash,
                remaining_seconds(iteration_deadline, active_iteration, wait_phase),
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
            records.append({
                "iteration": index + 1,
                "enter_writes": 1,
                "enter_bytes": 1,
                "arm_request_ns": arm_request_ns,
                "arm_ack_ns": arm_ack_ns,
                "enter_write_start_ns": enter_started,
                "enter_write_complete_ns": enter_written_ns,
                "arm_ack_to_enter_ms": (enter_started - arm_ack_ns) / 1_000_000,
                "enter_to_first_osc_c_ms": (
                    (output_assertions["first_command_frame_seen_ns"] - enter_started) / 1_000_000
                    if output_assertions["first_command_frame_seen_ns"] is not None else None
                ),
                "enter_to_first_osc_d_ms": (
                    (output_assertions["first_command_end_seen_ns"] - enter_started) / 1_000_000
                    if output_assertions["first_command_end_seen_ns"] is not None else None
                ),
                "enter_to_prompt_asserted_ms": (
                    output_assertions["prompt_asserted_ns"] - enter_started
                ) / 1_000_000,
                "prompt_asserted_to_window_ack_ms": (
                    window_ack_ns - output_assertions["prompt_asserted_ns"]
                ) / 1_000_000,
                "controller_window_start": arm_ack,
                "controller_window_stop": window_ack,
                "output_assertions": output_assertions,
                "latency_ms": (time.monotonic_ns() - enter_started) / 1_000_000,
            })
            wait_phase = "iteration complete"
            write_progress(
                run_dir, args.mode, active_iteration, args.iterations, len(records), wait_phase
            )
            if index + 1 < args.iterations:
                session.pump_for(0.02)

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
            "profile_boundary": "controller starts main plus pipeline-worker sampling before Enter, discovers and starts new pipeline workers while waiting, and stops all window threads immediately on the completion continuation render semaphore; Python parity and prompt/cursor checks remain post-assertions",
            "cache_policy": "fresh nshell process; no warmup and no cache clear, preserving cold first completion",
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
