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
        "schema_version": 2,
        "record": "nfr05-render-diagnostic",
        "output_event": "redraw",
        "render_wall_ns": 10,
        "gc_count": 0,
        "gc_time_ns": 0,
        "gc_real_time_ns": 0,
        "suggestion_ns": 1,
        "suggestion_scan_ns": 1,
        "suggestion_history_ns": 0,
        "suggestion_completion_ns": 0,
        "completion_ran": False,
        "grapheme_geometry_ns": 2,
        "display_width_ns": 3,
        "input_buffer_render_ns": 4,
        "terminal_write_ns": 4,
        "terminal_flush_ns": 5,
        "lock_wait_ns": None,
        "lock_wait_source": "not measured in process",
        "stage_timing_relationships": {
            "suggestion_scan_history_completion_are_nested_within_suggestion": True,
            "input_buffer_render_includes_work_performed_inside_render_edit_buffer": True,
        },
        "command_execution_requested": False,
    }
    record.update(overrides)
    return record


class Nfr05DiagnosticTests(unittest.TestCase):
    def test_schema_accepts_required_durations_and_null_lock_measurement(self) -> None:
        record = DIAGNOSTICS.validate_diagnostic_record(diagnostic_record())
        self.assertEqual(record["gc_count"], 0)
        self.assertEqual(record["gc_real_time_ns"], 0)
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
                "[pid 12] 100.000065 rt_sigreturn({mask=[]}) = 0 <0.000001>",
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
        self.assertEqual(parsed["lock_wait_scope"], "capture_window")
        self.assertEqual(parsed["futex_wait"]["count"], 1)
        self.assertEqual(parsed["futex_wait"]["events"][0]["trace_pid_tid"], 12)
        self.assertEqual(
            parsed["futex_wait"]["events"][0]["timestamp_realtime_ns"],
            100_000_000_000,
        )
        self.assertEqual(parsed["futex_wait"]["events"][0]["duration_ns"], 40_000)
        self.assertIn("sb_thread_wait", parsed["futex_wait"]["events"][0]["stack"][0])
        self.assertEqual(parsed["signal_mask"]["count"], 1)
        self.assertEqual(parsed["signal_return"]["count"], 1)
        self.assertEqual(parsed["terminal_syscalls"]["count"], 1)
        self.assertEqual(parsed["terminal_waits"]["count"], 2)
        self.assertIn(
            "sb_thread_wait_for_key",
            parsed["terminal_waits"]["events"][0]["stack"][0],
        )
        self.assertEqual(parsed["process_activity"]["exec_count"], 1)

    def test_strace_correlation_uses_event_intervals_and_rejects_missing_evidence(self) -> None:
        parsed = DIAGNOSTICS._parse_strace_trace(
            "\n".join(
                (
                    "[pid 21] 100.000010 futex(0x1, FUTEX_WAIT_PRIVATE, 2, NULL) = 0 <0.000020>",
                    " > /nix/store/sbcl/libsbcl.so(sb_thread_wait+0x1) [0x1]",
                    "22 100.000150 rt_sigprocmask(SIG_BLOCK, NULL, NULL, 8) = 0 <0.000010>",
                    "[pid 23] futex(0x1, FUTEX_WAIT_PRIVATE, 2, NULL) = 0 <0.000020>",
                )
            )
        )
        event_window = {
            "keypress_realtime_ns": 100_000_000_000,
            "redraw_complete_realtime_ns": 100_000_100_000,
        }
        DIAGNOSTICS.correlate_strace_events(parsed, event_window)
        futex_event, missing_time_event = parsed["futex_wait"]["events"]
        signal_event = parsed["signal_mask"]["events"][0]
        self.assertEqual(futex_event["trace_pid_tid"], 21)
        self.assertEqual(futex_event["redraw_overlap_ns"], 20_000)
        self.assertEqual(futex_event["origin_evidence"], "overlapping-user-stack-candidate")
        self.assertEqual(signal_event["redraw_overlap_ns"], 0)
        self.assertEqual(signal_event["redraw_overlap_status"], "outside-redraw-window")
        self.assertEqual(missing_time_event["redraw_overlap_ns"], None)
        self.assertEqual(
            missing_time_event["redraw_overlap_status"],
            "missing-event-timestamp-or-duration",
        )
        self.assertEqual(missing_time_event["origin_evidence"], "insufficient-time-evidence")
        self.assertEqual(parsed["futex_wait_redraw_overlap_ns_sum"], 20_000)

    def test_strace_pairs_interleaved_unfinished_syscalls_by_tid_and_correlates_entry_intervals(self) -> None:
        trace = "\n".join(
            (
                "[pid 21] 100.000010 futex(0x1, FUTEX_WAIT_PRIVATE, 2, NULL <unfinished ...>",
                "[pid 22] 100.000020 rt_sigprocmask(SIG_BLOCK, NULL, NULL, 8) <unfinished ...>",
                "[pid 23] 100.000030 futex(0x2, FUTEX_WAIT_PRIVATE, 2, NULL <unfinished ...>",
                "[pid 21] 100.000050 <... futex resumed>) = 0 <0.000040>",
                " > /nix/store/sbcl/libsbcl.so(sb_thread_wait_21+0x1) [0x21]",
                "[pid 22] 100.000060 <... rt_sigprocmask resumed>) = 0 <0.000040>",
                " > /nix/store/sbcl/libsbcl.so(gc_stop_the_world_22+0x1) [0x22]",
                "[pid 23] 100.000070 <... futex resumed>) = 0 <0.000040>",
                " > /nix/store/sbcl/libsbcl.so(sb_thread_wait_23+0x1) [0x23]",
            )
        )
        parsed = DIAGNOSTICS._parse_strace_trace(trace)
        DIAGNOSTICS.correlate_strace_events(
            parsed,
            {
                "keypress_realtime_ns": 100_000_025_000,
                "redraw_complete_realtime_ns": 100_000_060_000,
            },
        )

        futex_events = parsed["futex_wait"]["events"]
        self.assertEqual(parsed["futex_wait"]["count"], 2)
        self.assertEqual(parsed["futex_wait"]["duration_ns_total"], 80_000)
        self.assertEqual(parsed["futex_wait_redraw_overlap_ns_sum"], 55_000)
        self.assertEqual(
            [(event["trace_pid_tid"], event["timestamp_realtime_ns"], event["duration_ns"]) for event in futex_events],
            [(21, 100_000_010_000, 40_000), (23, 100_000_030_000, 40_000)],
        )
        self.assertEqual([event["redraw_overlap_ns"] for event in futex_events], [25_000, 30_000])
        self.assertIn("sb_thread_wait_21", futex_events[0]["stack"][0])
        self.assertIn("sb_thread_wait_23", futex_events[1]["stack"][0])

        mask_events = parsed["signal_mask"]["events"]
        self.assertEqual(parsed["signal_mask"]["count"], 1)
        self.assertEqual(parsed["signal_mask"]["duration_ns_total"], 40_000)
        self.assertEqual(parsed["signal_mask"]["redraw_overlap_ns_sum"], 35_000)
        self.assertEqual(mask_events[0]["trace_pid_tid"], 22)
        self.assertEqual(mask_events[0]["timestamp_realtime_ns"], 100_000_020_000)
        self.assertEqual(mask_events[0]["resume_timestamp_realtime_ns"], 100_000_060_000)
        self.assertEqual(mask_events[0]["redraw_overlap_ns"], 35_000)
        self.assertIn("gc_stop_the_world_22", mask_events[0]["stack"][0])

    def test_strace_unmatched_events_keep_only_observed_timestamps_and_durations(self) -> None:
        parsed = DIAGNOSTICS._parse_strace_trace(
            "\n".join(
                (
                    "[pid 31] 101.000010 futex(0x1, FUTEX_WAIT_PRIVATE, 2, NULL <unfinished ...>",
                    "[pid 32] 101.000050 <... rt_sigprocmask resumed>) = 0 <0.000010>",
                    " > /nix/store/sbcl/libsbcl.so(gc_stop_the_world_32+0x1) [0x32]",
                    "[pid 33] 101.000060 <... futex resumed>) = 0 <0.000005>",
                )
            )
        )
        DIAGNOSTICS.correlate_strace_events(
            parsed,
            {
                "keypress_realtime_ns": 101_000_000_000,
                "redraw_complete_realtime_ns": 101_000_100_000,
            },
        )

        self.assertEqual(len(parsed["unmatched_events"]), 3)
        unfinished = next(
            event for event in parsed["unmatched_events"] if event["event_status"] == "unfinished-unmatched"
        )
        resumed = next(
            event
            for event in parsed["unmatched_events"]
            if event["syscall"] == "rt_sigprocmask"
        )
        resumed_futex = next(
            event for event in parsed["unmatched_events"] if event["syscall"] == "futex"
        )
        self.assertEqual(unfinished["event_status"], "unfinished-unmatched")
        self.assertEqual(unfinished["trace_pid_tid"], 31)
        self.assertEqual(unfinished["timestamp_realtime_ns"], 101_000_010_000)
        self.assertIsNone(unfinished["duration_ns"])
        self.assertIsNone(unfinished["redraw_overlap_ns"])
        self.assertEqual(
            unfinished["redraw_overlap_status"], "missing-event-timestamp-or-duration"
        )

        self.assertEqual(resumed["event_status"], "resumed-unmatched")
        self.assertEqual(resumed["trace_pid_tid"], 32)
        self.assertIsNone(resumed["timestamp_realtime_ns"])
        self.assertEqual(resumed["resume_timestamp_realtime_ns"], 101_000_050_000)
        self.assertEqual(resumed["duration_ns"], 10_000)
        self.assertIsNone(resumed["redraw_overlap_ns"])
        self.assertEqual(
            resumed["redraw_overlap_status"], "missing-event-timestamp-or-duration"
        )
        self.assertEqual(resumed_futex["event_status"], "resumed-unmatched")
        self.assertIsNone(resumed_futex["timestamp_realtime_ns"])
        self.assertEqual(resumed_futex["resume_timestamp_realtime_ns"], 101_000_060_000)
        self.assertEqual(resumed_futex["duration_ns"], 5_000)
        self.assertEqual(parsed["futex_wait"]["count"], 1)
        self.assertEqual(parsed["futex_wait"]["duration_ns_total"], 0)
        self.assertEqual(parsed["signal_mask"]["count"], 1)
        self.assertEqual(parsed["signal_mask"]["duration_ns_total"], 10_000)

    def test_low_overhead_strace_filter_labels_omitted_terminal_syscalls(self) -> None:
        trace_syscalls = set(DIAGNOSTICS.NFR05_STRACE_SYSCALLS.split(","))
        self.assertTrue({"futex", "futex_waitv", "rt_sigprocmask"}.issubset(trace_syscalls))
        self.assertTrue({"clone", "execve", "wait4"}.issubset(trace_syscalls))
        self.assertTrue({"read", "poll", "write", "writev"}.isdisjoint(trace_syscalls))
        profile = DIAGNOSTICS._mark_untraced_strace_groups(
            DIAGNOSTICS._parse_strace_trace(
                "[pid 12] 100.000000 futex(0x1, FUTEX_WAIT_PRIVATE, 2, NULL) = 0 <0.000040>"
            ),
            trace_syscalls,
        )
        self.assertEqual(profile["terminal_waits"]["status"], "not-traced")
        self.assertIsNone(profile["terminal_waits"]["count"])
        self.assertEqual(profile["terminal_syscalls"]["status"], "not-traced")
        self.assertEqual(profile["signal_return"]["status"], "not-traced")

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
