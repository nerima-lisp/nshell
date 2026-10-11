# Recipes

## Draw a pipeline without running it

`pipeline-graph` renders a pipeline as a Graphviz DOT graph, or a Mermaid
flowchart with `--mermaid`, without executing it. Quote the pipeline
so the shell passes it as a single argument rather than running it:

```sh
pipeline-graph 'cat access.log | grep 404 | wc -l'
pipeline-graph --mermaid 'cat access.log | grep 404 | wc -l'
```

Malformed redirects are reported as errors instead of rendered as graphs.

## Write a script

```sh
#!/usr/bin/env nshell
function greet
    echo "hello $argv[1]"
end

greet $argv[1]
```

Save this as `greet.nsh` and run `nshell greet.nsh World`. Multiline blocks (`function`, `if`, `for`,
`while`, `switch`, `begin`/`end`), comments, and a `#!` shebang all work;
arguments after the script name arrive as `$argv`.

## Use the assistant

The assistant requires an authenticated `claude` CLI on PATH. Set
`NSHELL_AI_COMMAND` to use another executable implementing the same streaming
protocol. `NSHELL_AI_DISABLE` disables the assistant.

Start an interactive assistant task from an nshell terminal:

```sh
agent "inspect the current job state"
```

The `agent` builtin is interactive-only. Every proposed command, including one
classified as safe, is shown for review and executes only after Enter. Blocked
commands are not executed. Approval applies to one proposal, not the rest of
the task. Review each command, especially in a directory containing sensitive
data.

The safety label comes from static command analysis, not a security sandbox.
For example, recursive deletion of the filesystem root is blocked. A safe label
does not replace your review of the command, its arguments, and its working
directory.

Before command approval, the assistant receives your task and context: the last
command, its exit status and duration, the working directory, Git branch and
dirty state, a bounded tail of command output, and environment-variable names.
Known sensitive paths, commands, and environment values are redacted, but this
does not guarantee that task text or command output contains no secrets. Do not
submit confidential information unless the configured provider is permitted to
receive it.

At the review panel, press `e` to edit, `s` to skip the proposal, or `q` to cancel
the task. While editing, `q` and `s` insert text; Ctrl-C cancels the task. Enter
reclassifies the edited command and approves it for execution if it is not
blocked.

The sidecar may report only the `StructuredOutput` tool (or no tools) and no MCP
servers. Both fields must be present in its initialization event. Other
configurations are rejected even if a later event reports an acceptable one.

Inspect assistant state and configure the session with `ai`:

```sh
ai status
ai set effort medium
ai set max-steps 20
ai log 10
```

`ai log 10` shows the last ten audit entries. `ai reset` resets the conversation
and usage counters. `ai set model 'model-name'` selects a model identifier
supported by your CLI; without a setting, the CLI chooses its default model.
The default maximum is ten proposals per task. Skipped and blocked proposals
also count toward `max-steps`; editing a proposal does not add a step.

`ai set budget 1.50` sets a US-dollar reference amount for the usage display.
It does **not** enforce a spending limit or stop provider requests.

`ai set` changes the current session. The corresponding environment variables
are `NSHELL_AI_EFFORT`, `NSHELL_AI_MODEL`, `NSHELL_AI_MAX_STEPS`, and
`NSHELL_AI_BUDGET_USD`.

## Run the test suite

The hermetic gate CI uses, covering both suites plus formatting and docs:

```sh
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 1800; exec @ARGV' nix flake check --print-build-logs
```

Just the primary suite, through the same entry point CI uses:

For source-loaded checks, first isolate HOME and XDG directories using the
[validation procedure](../project/public-readiness.md#verification-outside-ci) to keep
personal history and configuration out of the test run.

```sh
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 300; exec @ARGV' nix run .#test
# or, inside `nix develop`:
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 300; exec @ARGV' sbcl --script run-tests.lisp
```

Just the focused completion suite (`nshell/weave`), inside `nix develop`:

```sh
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 300; exec @ARGV' sbcl --script scripts/weave.lisp
```

### The non-sandboxed integration run

Some cases need a real PTY, `stty`, and external binaries, which the Nix
sandbox does not provide; they are skipped inside `nix flake check` and run
instead in CI's `integration` job. When changing PTY, subprocess, terminal,
or job-control behaviour, run the [isolated integration, dependency, and history
suites](../project/public-readiness.md#verification-outside-ci) with `NSHELL_TEST_PTY=1`,
as shown there.

This covers the real-PTY interactive smoke tests, `Ctrl-C` recovery, and the
job-control lifecycle checks.

## Generate a coverage report

```sh
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 900; exec @ARGV' nix develop -c sbcl --script scripts/coverage.lisp
```

The report is written to `$TMPDIR/nshell-coverage/cover-index.html` when `TMPDIR`
is set, otherwise to `coverage/cover-index.html`. Set `NSHELL_COVERAGE_DIR` to
choose the output directory explicitly.

## Performance evidence

Benchmark output is evidence for a defined fixture, not a general claim about
interactive-shell performance. Generate the warm completion evidence and
validate every JSONL record before using it in a report:

```sh
NSHELL_BENCH_MODE=warm NSHELL_BENCH_JSONL=completion.jsonl \
  sbcl --script scripts/benchmark-completion.lisp
perl scripts/verify-benchmark-jsonl.pl completion.jsonl
```

Process-launch evidence requires at least 100 samples and an explicit nshell
binary:

```sh
NSHELL_BENCH_MODE=process NSHELL_BENCH_PROCESS_SAMPLES=100 \
  NSHELL_BENCH_NSHELL_BIN="$PWD/result/bin/nshell" \
  NSHELL_BENCH_JSONL=process.jsonl sbcl --script scripts/benchmark-completion.lisp
perl scripts/verify-benchmark-jsonl.pl process.jsonl
```

For a repeated, process-isolated competitor run, resolve every executable from
the flake's locked `nixpkgs` input and assign a stable run ID. The harness
removes the caller's environment, uses a temporary home, records exact argv,
raw samples, and failures, and accepts only executable paths under `/nix/store`:

```sh
nix build .#default
BASH_STORE=$(nix eval --raw --inputs-from . nixpkgs#bash.outPath)
ZSH_STORE=$(nix eval --raw --inputs-from . nixpkgs#zsh.outPath)
NSHELL_COMPARE_RUN_ID=local-01 NSHELL_COMPARE_REPETITIONS=2 NSHELL_COMPARE_SAMPLES=100 \
  NSHELL_BENCH_NSHELL_BIN="$(nix path-info .#default)/bin/nshell" \
  NSHELL_BENCH_BASH_BIN="$BASH_STORE/bin/bash" \
  NSHELL_BENCH_ZSH_BIN="$ZSH_STORE/bin/zsh" \
  perl scripts/benchmark-competitors.pl
perl scripts/verify-benchmark-jsonl.pl competitors.jsonl
```

The harness uses identical `-c 'echo nshell-bench-sentinel'` arguments. `echo`
is implemented as a builtin by every candidate, and the harness checks stdout,
stderr, and exit status before and after measurement. A run is ranking-eligible
only when at least two candidates complete every one of at least two
repetitions; the verifier independently checks the complete run group.

The cache classification is `fresh-process-warm-fs`: each sample is a fresh
process, but the harness does not claim to flush filesystem or executable
caches. A true cold-cache run requires a separately documented privileged host
protocol and is not emitted by this harness. Eligibility therefore supports
only this minimal noninteractive fixture and is not evidence about interactive
use, completion, or cold startup.

`nix flake check` runs the verifier self-test without a timing threshold, so CI
rejects malformed evidence without turning host performance noise into a flaky
gate. Failed or incomplete comparison groups remain ineligible. Even eligible
fixture results do not by themselves establish a broad "world-fastest" claim.

## Add a test

Unit, integration, property-based, and end-to-end tests live under `t/` and run
under [cl-weave](https://github.com/nerima-lisp/cl-weave) using
`describe`/`it`/`expect`. Changes to shell-language, expansion, completion,
job-control, or input-state behaviour should carry a focused regression test,
plus property or PTY coverage when the change crosses a process, terminal, or
parser boundary.
