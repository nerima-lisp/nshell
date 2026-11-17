# Recipes

## Pass an evaluated value to a command

Use `$NAME` to pass a shell variable's value and `,EXPR` to evaluate an
expression for a command argument. This example keeps a shell variable between
forms and passes the result of `(+ 2 3)` as an argument:

```lisp
(set o02_value "preserved")
(echo $o02_value ,(+ 2 3))
```

The command prints `preserved` and `5`.

## Filter structured records

`->` passes records through value transformations. Here, `where` filters the
records and `select` keeps the requested fields:

```lisp
(echo ,(length
         (-> '((:state "stopped" :id 7 :command "demo")
               (:state "running" :id 8 :command "other"))
             (where (= :state "stopped"))
             (select :id :command))))
```

This prints `1`. The value pipeline carries Lisp records; `|` connects byte
streams between commands.

## Convert JSON, TSV, and lines

The value library converts JSON and TSV strings to records and back. It also
converts newline-delimited strings to and from line values:

```lisp
(echo ,(to-json (from-json "{\"name\":\"Ada\"}")))
(echo ,(to-tsv
         (from-tsv
           (concatenate (quote string) "name" (string #\Tab) "Ada" (string #\Newline)))))
(echo ,(from-lines
         (to-lines
           (concatenate (quote string) "first" (string #\Newline) "second" (string #\Newline)))))
```

## Match text with a regular expression

The `string match -r` command applies a regular expression to its argument:

```text
string match -r "^[a-z]+$" nshell
```

It prints `nshell` when the expression matches.

## Use the assistant

The assistant requires the `claude` CLI on `PATH` and a completed provider
login. Follow the [Claude Code setup guide](https://docs.anthropic.com/en/docs/claude-code/getting-started)
to install and authenticate it. nshell starts the CLI in print mode with
streaming JSON input and output, an empty tool list, and strict MCP
configuration. Set `NSHELL_AI_COMMAND` to select another executable that
accepts the same arguments and streaming protocol. `NSHELL_AI_DISABLE`
disables the assistant.

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

At startup, the assistant must list its tools and MCP servers. It may list no
tools or only `StructuredOutput`, and it must list no MCP servers. Later
messages do not change this startup requirement.

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

To run the hermetic gate used by CI, covering both suites plus formatting and
documentation:

```sh
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 1800; exec @ARGV' nix flake check --print-build-logs
```

To run only the primary suite through the same entry point CI uses, first
isolate HOME and XDG directories with the
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

Run the benchmark commands in `nix develop`, which provides SBCL and the
project's dependencies.

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

Run `perl scripts/verify-benchmark-jsonl.pl --self-test` to exercise the JSONL
verifier without running a benchmark. `nix flake check` does not run this
self-test.

To compare two nshell builds for startup, key latency, Tab completion, prompt
redraw, and memory, use the A/B regression gate in
[`scripts/perf/`](https://github.com/nerima-lisp/nshell/blob/main/scripts/perf/README.md).
It measures both builds on the same machine and reports confidence intervals
for their difference, not absolute timings; it is tested on macOS only. The
gate judges the startup median, key latency p95 and p99, and prompt redraw p95.
When given both source trees, it also judges per-key consing and fails when
every candidate run counts more per-key `stat`, file I/O, or spawn operations
than every baseline run. Tab completion and memory are recorded but not judged
in v0.8; they become ratchets in a later phase (P5-3). None of these results by
themselves establish a broad "world-fastest" claim.

## Add a test

Unit, integration, property-based, and end-to-end tests live under `t/` and run
under [cl-weave](https://github.com/nerima-lisp/cl-weave) using
`describe`/`it`/`expect`. Changes to shell-language, expansion, completion,
job-control, or input-state behaviour should carry a focused regression test,
plus property or PTY coverage when the change crosses a process, terminal, or
parser boundary.
