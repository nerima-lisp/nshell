#!/usr/bin/env python3
"""Focused schema and aggregation checks for the NFR-05 diagnostic pass."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    "measure_nfr05_diagnostics", SCRIPTS / "measure-nfr05-diagnostics.py"
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load NFR-05 diagnostic module")
DIAGNOSTICS = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = DIAGNOSTICS
SPEC.loader.exec_module(DIAGNOSTICS)


def diagnostic_record(**overrides: object) -> dict[str, object]:
    record: dict[str, object] = {
        "schema_version": 1,
        "record": "nfr05-render-diagnostic",
        "output_event": "redraw",
        "render_wall_ns": 10,
        "gc_count": 0,
        "gc_time_ns": 0,
        "suggestion_ns": 1,
        "grapheme_geometry_ns": 2,
        "display_width_ns": 3,
        "terminal_write_ns": 4,
        "terminal_flush_ns": 5,
        "lock_wait_ns": None,
        "lock_wait_source": "not measured in process",
        "command_execution_requested": False,
    }
    record.update(overrides)
    return record


class Nfr05DiagnosticTests(unittest.TestCase):
    def test_schema_accepts_required_durations_and_null_lock_measurement(self) -> None:
        record = DIAGNOSTICS.validate_diagnostic_record(diagnostic_record())
        self.assertEqual(record["gc_count"], 0)
        self.assertIsNone(record["lock_wait_ns"])

    def test_schema_rejects_missing_or_negative_durations(self) -> None:
        for record in (
            diagnostic_record(suggestion_ns=None),
            diagnostic_record(terminal_write_ns=-1),
        ):
            with self.subTest(record=record):
                with self.assertRaises(ValueError):
                    DIAGNOSTICS.validate_diagnostic_record(record)

    def test_summary_uses_only_nonempty_stage_samples_without_an_acceptance_gate(self) -> None:
        rows = [
            {
                "sample_role": role,
                "pair_id": pair_id,
                "latency_ms": latency,
                "diagnostics": diagnostic_record(render_wall_ns=duration),
            }
            for role, pair_id, latency, duration in (
                ("stage-control", 0, 2.0, 20),
                ("stage-native", 0, 3.0, 30),
                ("stage-control", 1, 4.0, 40),
                ("stage-native", 1, 5.0, 50),
            )
        ]
        summary = DIAGNOSTICS.summarize_diagnostic_samples(rows)
        self.assertEqual(summary["sample_count"], 4)
        self.assertEqual(summary["sample_pair_count"], 2)
        self.assertEqual(summary["stage_control"]["latency_ms"]["median"], 3.0)
        self.assertEqual(summary["stage_native"]["latency_ms"]["median"], 4.0)
        self.assertEqual(summary["observed_native_latency_delta_ms"]["median"], 1.0)
        self.assertIsNone(summary["acceptance_threshold_ms"])
        with self.assertRaises(ValueError):
            DIAGNOSTICS.summarize_diagnostic_samples([])

    def test_strace_parser_tags_futex_signal_mask_terminal_and_process_events(self) -> None:
        trace = "\n".join(
            (
                "[pid 12] 100.000000 futex(0x1, FUTEX_WAIT_PRIVATE, 2, NULL) = 0 <0.000040>",
                " > /nix/store/sbcl/libsbcl.so(sb_thread_wait+0x1) [0x1]",
                " > /nix/store/libc/libc.so.6(__futex_wait+0x1) [0x2]",
                "[pid 12] 100.000050 futex(0x1, FUTEX_WAKE_PRIVATE, 1, NULL) = 1 <0.000001>",
                "[pid 12] 100.000060 rt_sigprocmask(SIG_BLOCK, NULL, NULL, 8) = 0 <0.000002>",
                " > /nix/store/sbcl/libsbcl.so(gc_stop_the_world+0x1) [0x3]",
                "[pid 12] 100.000070 write(1, \"prompt\", 6) = 6 <0.000003>",
                " > /nix/store/libc/libc.so.6(write+0x1) [0x4]",
                "[pid 12] 100.000075 read(0, \"x\", 1) = 1 <0.000004>",
                " > /nix/store/sbcl/libsbcl.so(sb_thread_wait_for_key+0x1) [0x5]",
                "[pid 12] 100.000077 ppoll([{fd=1}], 1, NULL, NULL, 8) = 0 <0.000006>",
                " > /nix/store/libc/libc.so.6(ppoll+0x1) [0x6]",
                "[pid 12] 100.000080 execve(\"/bin/tool\", [\"tool\"], 0x0) = 0 <0.001000>",
            )
        )
        parsed = DIAGNOSTICS._parse_strace_trace(trace)
        self.assertEqual(parsed["lock_wait_ns"], 40_000)
        self.assertEqual(parsed["futex_wait"]["count"], 1)
        self.assertIn("sb_thread_wait", parsed["futex_wait"]["events"][0]["stack"][0])
        self.assertEqual(parsed["signal_mask"]["count"], 1)
        self.assertEqual(parsed["terminal_syscalls"]["count"], 1)
        self.assertEqual(parsed["terminal_waits"]["count"], 2)
        self.assertIn(
            "sb_thread_wait_for_key",
            parsed["terminal_waits"]["events"][0]["stack"][0],
        )
        self.assertEqual(parsed["process_activity"]["exec_count"], 1)

    def test_sample_parser_records_pid_wait_stacks_without_inventing_duration(self) -> None:
        parsed = DIAGNOSTICS.parse_sample_profile_from_text(
            "\n".join(
                (
                    "Analysis of sampling nshell (pid 314) every 1 millisecond",
                    "  pthread_mutex_lock",
                    "  __pthread_sigmask",
                    "  GC_stop_the_world",
                    "  kevent",
                    "  write",
                    "  execve",
                )
            )
        )
        self.assertIsNone(parsed["lock_wait_ns"])
        self.assertEqual(parsed["sampled_pid"], 314)
        self.assertEqual(parsed["sampled_process"], "nshell")
        self.assertEqual(parsed["sample_symbol_occurrences"]["pthread_mutex"], 1)
        self.assertEqual(len(parsed["stack_evidence"]["named_mutex_wait"]), 1)
        self.assertEqual(len(parsed["stack_evidence"]["terminal_protocol_wait"]), 1)
        self.assertEqual(len(parsed["stack_evidence"]["subprocess_or_pipeline"]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
