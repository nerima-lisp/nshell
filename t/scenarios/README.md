# Scenario corpus

Each JSON file defines one executable scenario. Keep scenarios under
`t/scenarios/<UC>/` so each use case can grow without a shared test-list edit.
UC means use case. For a scenario that covers multiple use cases, choose one UC
directory and list all covered IDs in its `uc` array.

## Scenario format

Every scenario has an `id`, a `uc` array, a `mode` (`batch` or `pty`), an
`environment`, `preconditions`, and `expected` results. Set `environment.home`
and `environment.cwd` to paths relative to the isolated scenario directory. Set
`environment.variables` for values such as `TERM`, and use
`environment.terminal_size.columns` and `environment.terminal_size.rows` for
terminal dimensions. Precondition file paths are relative to the scenario
directory. Every scenario must define `expected.exit_code`, including scenarios
that also check output or side effects. See [a complete batch scenario](C01/batch-command.json)
for an example.

Batch scenarios select `invocation.kind` as `command`, `stdin`, or `script`.
The runner passes command text to `nshell -c`, sends text to standard input,
or writes script text to `invocation.path` (relative to `environment.cwd`)
and runs that file. Batch expectations can check stdout, stderr, exit code,
and files created under the scenario working directory.

PTY scenarios use an ordered `steps` array: `keys` sends literal text,
`paste` sends bracketed paste, `key` sends a named key such as `Enter` or
`C-d`, `wait` waits for matching text emitted after that step starts, and
`wait_exit` waits for the shell to exit. Set a scenario-specific
`NSHELL_PROMPT` marker in `environment.variables` for the startup handshake.
For each `wait.contains` marker, the runner rejects the scenario if that full
value is a substring of an echo from an earlier `keys`, `paste`, or `key` step,
or of the prompt. It also rejects stream or screen `equals` and `contains`
values when the full value is a substring of any input echo or the prompt.
This check covers text sent with `keys` or `paste`, printable keys, and named
keys with a known terminal echo such as `Tab`, `Enter`, `Up`, or `F1`.
`excludes` checks do not assert that text appears and are not subject to this
rejection. Choose an expected-output marker that does not appear in full within
an input echo or prompt.
End each PTY step sequence with `wait` or `wait_exit` to synchronize the
assertions with new output or process exit.
Expectations can check the PTY stream, captured screen, exit code, created
files, and shell history. File side-effect paths are relative to
`environment.cwd`; the history path is relative to `environment.home`. Text
expectations accept `equals`, `contains`, and `excludes`.

The full-corpus manifest is `t/scenarios/expected-scenarios.json`. It requires
the top-level fields `version: 1` and a non-empty `scenarios` array; other
top-level fields are ignored. During the full-corpus comparison, the runner
requires version 1 and rejects entries with missing or extra fields. Each
entry has exactly three fields:
`id` is the scenario's ID, `uc` is its use-case ID array, and `path` is the
scenario JSON path relative to `t/scenarios/`. For example:

```json
{
  "version": 1,
  "scenarios": [
    {"id": "C01-batch-command", "uc": ["C01"], "path": "C01/batch-command.json"}
  ]
}
```

An unfiltered run (`--mode all` with no `--scenario-id`) checks the exact
scenario count, IDs, UC mapping, and file paths against this manifest.
`--mode` defaults to `all`. `--mode batch`, `--mode pty`, and any
`--scenario-id` selection skip the full-corpus comparison. Update the manifest
when adding, removing, renaming, or remapping a scenario. The runner checks
each manifest `uc` array against the corresponding scenario's `uc` array,
without regard to array order.

Every run uses a fresh temporary home and working directory. Step and scenario
timeouts are capped at 60 seconds. PTY stream capture is capped at 1 MiB. A
timeout fails with the current pane screen in the report.

## Expected failures

Use `expected_failure.reason` for a known defect. Failed assertions are
reported as `XFAIL`; if the assertions pass, the runner reports `XPASS` and
exits nonzero so the obsolete marker can be removed. Launch errors and
timeouts remain failures.

## Run scenarios

Build the binary for the current system, then run the corpus in the Nix dev
scenario shell. The scenario shell provides Python and tmux.

```sh
# Apple Silicon macOS
nix build .#packages.aarch64-darwin.default --out-link result

# x86_64 Linux
nix build .#packages.x86_64-linux.default --out-link result

nix develop .#scenarios -c python3 scripts/run-scenarios.py --binary "$PWD/result/bin/nshell"
```

Use `--mode batch` or `--mode pty` to select an executor,
`--scenario-id C10-short-circuit-followed-by-sequence` to select a scenario,
and `--repeat 3` to repeat the selected corpus. Batch scenarios also run in a
Nix batch-only check. Run it with
`nix build .#checks.aarch64-darwin.scenarios-batch` on Apple Silicon or
`nix build .#checks.x86_64-linux.scenarios-batch` on Linux. This check runs the
runner tests and then its `--mode batch` selection, so it does not compare the
full corpus manifest. The scenario CI workflow runs the full unfiltered corpus
outside the Nix sandbox on Linux and Apple Silicon macOS.
