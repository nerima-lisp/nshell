# Scenario corpus

Each scenario JSON file defines one executable scenario. Keep scenarios under
`t/scenarios/<UC>/` and register each one in the shared manifest described
below. UC means use case. Get UC IDs from the request that assigns the scenario.
If the task omits them, ask the person who assigned it before adding the
scenario.
For a scenario covering multiple use cases, choose the directory for its
primary assertion and list every covered ID in its `uc` array.

## Scenario format

Every scenario JSON file must define `id`, a `uc` array, `mode` (`batch` or
`pty`), and an `expected` object. `environment` and `preconditions` are optional.
The runner creates an isolated temporary root for each scenario execution.
Paths in `environment.home`, `environment.cwd`, and
`preconditions.files[].path` are relative to that root.
The runner defaults `environment.home` and `environment.cwd` to `home` and
`work`, and the terminal size to 80 columns by 24 rows.
Keys in `environment.variables` override matching variables in the runner's
default environment, which is defined in `scripts/run-scenarios.py`.
When the runner provides `NSHELL_SCENARIO_EXTRA_PATH`, batch scenarios append it
to `PATH` by default. Set `environment.append_extra_path` to `false` when a
scenario must keep its explicit `PATH`, such as a command-not-found check.
If `preconditions.files` is omitted, no precondition files are created. Each
file entry requires a relative `path` and can include string `content`, which
defaults to empty text. Set `environment.terminal_size.columns` and
`environment.terminal_size.rows` to override its dimensions. Every scenario
must define `expected.exit_code`. See
the [batch example](C01/batch-command.json) and
[PTY example](C01/pty-paste.json).

Use `preconditions.file_sets` to generate bounded file collections. Each
entry requires a scenario-relative `directory`, a non-empty `prefix`, and a
`count` from 1 to 20,000; `suffix` and shared file `content` are optional.
Generated names use a five-digit index starting at `00000`. The total number
of generated files is limited to 20,000, and each name is limited to 255 UTF-8
bytes. Paths must stay within the scenario root. Fixture paths cannot be
duplicated or make one fixture path the parent directory of another.

Batch scenarios select `invocation.kind` as `command`, `stdin`, `script`, or
`argv`. The `command` kind passes command text to `nshell --command`; `stdin`
sends text to standard input; `script` writes text to `invocation.path`
(relative to `environment.cwd`) and runs that file. The `argv` kind passes
each string in `invocation.arguments` as one argument after the binary and
sends `invocation.stdin` to standard input; omitted `stdin` means empty input.
It does not add CLI flags or rewrite the argument strings. Batch expectations
can check stdout, stderr, exit code, and files created under the scenario
working directory.

J12 creates 20,000 files in one directory. The unit test
`filesystem-candidate-membership-probes-scale-linearly` counts candidate-set
lookups for 2,000 and 20,000 entries and asserts that the count scales by the
same factor as the input. This count-based check is independent of wall-clock
load. For end-to-end timing, run `bash bench/completion-filesystem.sh
<before-binary> <after-binary>` with binaries built from the baseline and
change revisions. It verifies the fixture and byte-for-byte output parity,
then uses hyperfine for two warmups and ten samples per arm in randomized
order. The report includes host details and load average; the timing is
informational and is not an absolute landing threshold.

PTY scenarios use an ordered `steps` array: `keys` sends literal text,
`paste` sends bracketed paste, `key` sends a key name accepted by tmux
`send-keys`, such as `Enter` or `C-d`, and `wait` waits for its `contains`
string to appear in captured PTY output after the step starts. `wait_exit` waits
for the shell to exit. Set a non-empty `environment.variables.NSHELL_PROMPT`
marker that only the prompt displays.
The optional top-level `arguments` array passes exact additional arguments to
the binary.
The runner sends Enter to make the initial prompt appear and waits for that
marker before executing the scenario steps.
`load_config` is optional and defaults to `false`; it is valid only for PTY
scenarios. Set it to `true` when a scenario needs to load startup configuration
from its isolated home. The runner sets `XDG_CONFIG_HOME` to `.config` under
the scenario home by default, so add `home/.config/nshell/init.lisp` to
`preconditions.files`; the file contains plain nshell commands. If
`environment.home` changes, use that home directory in the fixture path. The
runner otherwise passes `--no-config`.

An input echo is the terminal displaying text or a key sequence sent by a
`keys`, `paste`, or `key` step. A prompt redraw is the shell emitting
`NSHELL_PROMPT` again.

Before launching, the runner derives input echoes from `keys` and `paste` text
plus recognized tmux key sequences for `key` steps. The key sequences it
recognizes are defined in `scripts/run-scenarios.py`. The runner rejects
positive markers that could be satisfied by terminal echo or a prompt redraw
before launching:

- `wait.contains` if an echo from an earlier input step or a prompt redraw
  contains the entire marker;
- any non-empty value in `expected.stream.equals`, `expected.stream.contains`,
  `expected.screen.equals`, or `expected.screen.contains` if an input echo or
  prompt redraw contains the entire value.

`excludes` assertions require the checked text to be absent from its target,
such as output, screen, file, or history contents. They are not subject to this
rejection.

End each PTY step sequence with `wait_exit` to synchronize with shell exit and
record its status. `expected.stream` checks output captured from the PTY during
the run, while `expected.screen` checks the visible pane contents at the end.

## Output and side effects

In either mode, `expected.side_effects.files` is an array of file checks. Each
check requires a `path` and can set `exists` (default `true`) and text
assertions. Set `exists` to `false` to assert that a file is absent. File paths
are relative to `environment.cwd`. The optional
`expected.side_effects.history` object checks the history file with the same
fields and a path relative to `environment.home`.
Text assertions for stdout, stderr, PTY stream, screen, file contents, and
history contents use a string for `equals` and arrays of strings for `contains`
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

## Login and shell-caller coverage

These scenarios exercise the `-l` and `-c` entry points on the real binary.
They use controlled fixtures so the corpus does not depend on a developer's
home directory or exact machine environment.

- A03 runs a login command and checks its output. Its manual check covers the
  account-specific login shell behavior; the scenario does not change the
  account's login shell with `chsh`.
- A04 and A05 share `t/scenarios/A04/login-path-handoff.json`. The scenario
  starts with a synthetic PATH and always checks the fixture's `.profile`
  marker. It also checks for `/usr/bin` when `/etc/profile` is readable and
  `/usr/bin` exists. Linux `nix flake check` and the macOS batch scenario job
  both run this scenario. The A04 manual check covers account-specific
  `path_helper`, nix-darwin, and Home Manager values; the A05 manual check
  covers host-specific values from `/etc/profile`.
- A06 starts with `SHLVL=40` and checks that the delegated shell sees a larger
  value while preserving the supplied `USER` and `SHELL`.
- A07 checks that a non-interactive login command produces no stdout or stderr.
- B01 through B06 share a POSIX loop command as a generic child-shell smoke
  test. B02, B03, and B06 also have separate approximation scenarios for
  remote-shell, remote-copy, and `-c` behavior. These scenarios do not launch
  Vim, SSH, scp, rsync, Git, make, fzf, xargs, cron, or launchd; B04 and B05
  retain their manual caller checks.
- B07 and B08 share an interactive PTY startup scenario. It does not launch
  Emacs, VS Code, or JetBrains; their manual checks cover those callers.
- B09 has three scenarios covering exact command arguments, including quotes,
  spaces, a newline, `--`, a leading-dash value, an empty command, stdin,
  stdout, stderr, and status. They do not test a particular external caller.
- B10 invokes the literal `-ilc env` argument vector with a temporary
  `.nshellrc` that adds a unique PATH marker and emits a startup marker. It
  checks for the PATH marker and verifies that the startup marker is absent
  from stdout, and requires empty stderr. The broader configuration behavior
  assigned to L07 (public Lisp, scripts, autoload, and hooks) remains outside
  this fixture.

## Run scenarios

Build the binary for your platform, then run the corpus in the Nix scenario
shell. These commands do not create a `result` symlink. The scenario shell
provides Python and tmux.

```sh
# Apple Silicon macOS
binary=$(nix build .#packages.aarch64-darwin.default --no-link --print-out-paths)
nix develop .#scenarios -c python3 scripts/run-scenarios.py --binary "$binary/bin/nshell"
```

```sh
# x86_64 Linux
binary=$(nix build .#packages.x86_64-linux.default --no-link --print-out-paths)
nix develop .#scenarios -c python3 scripts/run-scenarios.py --binary "$binary/bin/nshell"
```

Use `--mode batch` or `--mode pty` to select an executor,
`--scenario-id` to select a scenario, and `--repeat 3` to repeat the selection.
Repeat `--scenario-id` to select more than one scenario. For example:

```sh
# Apple Silicon macOS
binary=$(nix build .#packages.aarch64-darwin.default --no-link --print-out-paths)
nix develop .#scenarios -c python3 scripts/run-scenarios.py \
  --binary "$binary/bin/nshell" \
  --scenario-id C10-short-circuit-followed-by-sequence
```

Batch scenarios also run in a
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
