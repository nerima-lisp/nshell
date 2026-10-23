# Scenario corpus

Each JSON file defines one executable scenario. Keep scenarios under
`t/scenarios/<UC>/` so each use case can grow without a shared test-list edit.

## Scenario format

Every scenario has an `id`, a `uc` array, a `mode` (`batch` or `pty`), an
`environment`, `preconditions`, and `expected` results. Set `environment.home`
and `environment.cwd` to paths inside the isolated scenario directory. Set
`environment.variables` for values such as `TERM`, and use
`environment.terminal_size.columns` and `environment.terminal_size.rows` for
terminal dimensions. Precondition file paths are relative to the scenario
directory.

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
The PTY stream includes terminal echo, so choose wait markers absent from the
sent input.
End each PTY step sequence with `wait` or `wait_exit` to synchronize the
assertions with new output or process exit.
Expectations can check the PTY stream, captured screen, exit code, created
files, and shell history. File side-effect paths are relative to
`environment.cwd`; the history path is relative to `environment.home`. Text
expectations accept `equals`, `contains`, and `excludes`.

Every run uses a fresh temporary home and working directory. The PTY executor
uses tmux with `-f /dev/null` and a unique socket, clears the shell process
environment, and reads output through a FIFO. Step and scenario timeouts are
bounded at 60 seconds. PTY stream capture is capped at 1 MiB. A timeout fails
with the current pane screen in the report.

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
Nix check. PTY scenarios run outside the Nix sandbox in the scenario CI
workflow on Linux and Apple Silicon macOS.
