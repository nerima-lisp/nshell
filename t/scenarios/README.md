# Scenario corpus

Each scenario JSON file defines one executable scenario. Keep scenarios under
`t/scenarios/<UC>/` and register each one in the shared manifest described
below. UC means use case. Get UC IDs from the request that assigns the scenario.
If it omits them, ask the person who assigned it before adding the scenario.
The manifest records scenario mappings but is not the UC catalog.
For a scenario covering multiple use cases, place it under the UC whose
behavior its assertions primarily verify, and list every covered ID in its
`uc` array.

## Scenario format

Every scenario JSON file must define `id`, a `uc` array, `mode` (`batch` or
`pty`), and an `expected` object. `environment` and `preconditions` are optional.
The runner creates an isolated temporary root for each scenario execution.
Paths in `environment.home`, `environment.cwd`, and
`preconditions.files[].path` are relative to that root.
The runner defaults `environment.home`, `environment.cwd`, and
`environment.terminal_size` to `home`, `work`, and 80 by 24, respectively.
Keys in `environment.variables` override matching variables in the runner's
default environment, which is defined in `scripts/run-scenarios.py`.
If `preconditions.files` is omitted, no precondition files are created. Each
file entry requires a relative `path` and can include string `content`, which
defaults to empty text. Set `environment.terminal_size.columns` and
`environment.terminal_size.rows` to override its dimensions. Every scenario
must define `expected.exit_code`. See
the [batch example](C01/batch-command.json) and
[PTY example](C01/pty-paste.json).

Batch scenarios select `invocation.kind` as `command`, `stdin`, or `script`.
Every kind requires `invocation.text`; `script` also requires `invocation.path`,
relative to `environment.cwd`. The runner passes command text to `nshell -c`,
sends text to standard input, or writes script text to the path and starts
`nshell` with that path as its script argument.
Batch expectations can check stdout, stderr, exit code, and files created under
the scenario working directory.

PTY scenarios use an ordered `steps` array: `keys` sends literal text,
`paste` sends bracketed paste, `key` sends a key name accepted by tmux
`send-keys`, such as `Enter` or `C-d`, and `wait` waits for matching text in
the captured PTY output after that step starts. `wait_exit` waits for the shell
to exit. Set a non-empty `environment.variables.NSHELL_PROMPT` marker that only
the prompt displays.
The runner sends Enter to make the initial prompt appear and waits for that
marker before executing the scenario steps.
`load_config` is optional and defaults to `false`; it is valid only for PTY
scenarios. Set it to `true` when a scenario needs to load startup configuration
from its isolated home. With the default `environment.home`, add
`home/.nshellrc` to `preconditions.files`; the file contains plain nshell
commands. If `environment.home` changes, place `.nshellrc` there instead. The
runner otherwise passes `--no-config`.

An input echo is the terminal displaying text or a key sequence sent by a
`keys`, `paste`, or `key` step. A prompt redraw is the shell emitting
`NSHELL_PROMPT` again.

Before launching, the runner derives input echoes from `keys` and `paste` text
plus recognized tmux key sequences for `key` steps. The key sequences it
recognizes are defined in `scripts/run-scenarios.py`. The runner rejects these
overlaps with the derived echoes and prompt before launching so terminal echo
cannot falsely satisfy a wait or output assertion:

- a `wait.contains` marker if an echo from an earlier input step or a prompt
  redraw contains that entire marker;
- any non-empty string in `expected.stream.equals`, `expected.stream.contains`,
  `expected.screen.equals`, or `expected.screen.contains` if an input echo or
  prompt redraw contains that entire string.

`excludes` assertions require the text to be absent from output and are not
subject to this rejection.

End each PTY step sequence with `wait_exit` to synchronize with shell exit and
record its status. `expected.stream` checks output captured from the PTY during
the run, while `expected.screen` checks the visible pane contents at the end.
`expected.side_effects.files` is an array of file checks. Each check requires a
`path` and can set `exists` (default `true`) and text assertions. The optional
`expected.side_effects.history` object checks a history file with the same
fields. File paths are relative to `environment.cwd`; the history path is
relative to `environment.home`. Text assertions accept `equals`, `contains`,
and `excludes`.

The full-corpus manifest is `t/scenarios/expected-scenarios.json`. It requires
the top-level fields `version: 1` and a non-empty `scenarios` array; other
top-level fields are ignored. Each object in `scenarios` has exactly three
fields:
`id` is the scenario's ID, `uc` is its use-case ID array, and `path` is the
scenario JSON path relative to `t/scenarios/`.

The runner's `--mode all` option selects both scenario modes. An unfiltered
run (`--mode all` with no `--scenario-id`) checks the exact scenario count,
IDs, UC mapping, and file paths against this manifest.
`--mode` defaults to `all`. `--mode batch`, `--mode pty`, and any
`--scenario-id` selection skip the full-corpus comparison. Update the manifest
when adding, removing, renaming, or remapping a scenario. The runner checks
each manifest `uc` array against the corresponding scenario's `uc` array,
without regard to array order.

Each scenario's top-level `timeout_seconds` defaults to 30 seconds for batch
and 45 seconds for PTY. Each PTY `wait` and `wait_exit` step has its own
`timeout_seconds`, defaulting to 10 seconds. Scenario and step timeouts can be
set up to 60 seconds. PTY stream capture is capped at 1 MiB; exceeding the cap
fails the scenario. A batch timeout reports captured stdout and stderr; a PTY
timeout reports the current pane screen.

## Expected failures

For a known defect, add a top-level `expected_failure` object with a non-empty
`reason` string. Only failed assertions are reported as `XFAIL`; if the assertions
pass, the runner reports `XPASS` and exits nonzero so the obsolete marker can
be removed. Scenario validation errors, launch errors, and timeouts remain
failures.

## Run scenarios

Run these commands from the repository root. The `scenarios` Nix shell supplies
Python and tmux for the scenario runner.

```sh
# Apple Silicon macOS
nix build .#packages.aarch64-darwin.default --out-link result
```

```sh
# x86_64 Linux
nix build .#packages.x86_64-linux.default --out-link result
```

After either build, run the scenario runner:

```sh
nix develop .#scenarios -c python3 scripts/run-scenarios.py --binary "$PWD/result/bin/nshell"
```

Add `--scenario-id` to run one scenario. Repeat the option to select more than
one scenario:

```sh
nix develop .#scenarios -c python3 scripts/run-scenarios.py --binary "$PWD/result/bin/nshell" --scenario-id C10-short-circuit-followed-by-sequence
```

Use `--repeat 3` to repeat the selected corpus. Batch scenarios also run in a
Nix batch-only check. Run it with
`nix build .#checks.aarch64-darwin.scenarios-batch` on Apple Silicon or
`nix build .#checks.x86_64-linux.scenarios-batch` on Linux. This check runs the
runner tests, then runs `scripts/run-scenarios.py` with `--mode batch`. The
scenario CI workflow (`.github/workflows/scenarios.yml`) runs this check on
Apple Silicon macOS.
Run the runner tests from the repository root with:

```sh
nix develop .#scenarios -c python3 scripts/test-run-scenarios.py
```

The suite includes `test_repository_full_corpus_matches_manifest`. The workflow
runs PTY scenarios with `--mode pty --repeat 3` on both Linux and Apple Silicon
macOS.
