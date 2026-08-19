# Recipes

## Draw a pipeline without running it

`pipeline-graph` renders a typed pipeline as a validated Graphviz DOT graph — or
a Mermaid flowchart with `--mermaid` — without executing it. Quote the pipeline
so the shell passes it as a single argument rather than running it:

```sh
pipeline-graph 'cat access.log | grep 404 | wc -l'
pipeline-graph --mermaid 'cat access.log | grep 404 | wc -l'
```

It is a diagnostic built on the
[cl-dataflow-kit](https://github.com/nerima-lisp/cl-dataflow-kit) computation-graph
toolkit, and it validates the pipeline as it builds the graph, so a malformed
redirect shows up as an error rather than a picture.

## Write a script

```sh
#!/usr/bin/env nshell
function greet
    echo "hello $argv[1]"
end

greet $argv[1]
```

Run it with `nshell greet.nsh World`. Multiline blocks (`function`, `if`, `for`,
`while`, `switch`, `begin`/`end`), comments, and a `#!` shebang all work;
arguments after the script name arrive as `$argv`.

## Run the test suite

The hermetic gate CI uses, covering both suites plus formatting and docs:

```sh
nix flake check --print-build-logs
```

Just the primary suite, through the same entry point CI uses:

```sh
nix run .#test
# or, inside `nix develop`:
sbcl --script run-tests.lisp
```

Just the focused completion suite (`nshell/weave`):

```sh
sbcl --script scripts/weave.lisp
```

All repository entry points use `scripts/asdf-runtime.lisp` for source
discovery and compile policy. The Nix development shell supplies a complete
`CL_SOURCE_REGISTRY`; outside that shell, set `NSHELL_SOURCE_TREE` to an
explicit directory containing sibling Common Lisp systems, or set
`CL_SOURCE_REGISTRY` yourself. When no registry is supplied, the repository
itself is registered and the runtime does not scan a worktree's parent
directory. The shared runtime deliberately ignores inherited ASDF output
translations and writes compiled files below `NSHELL_ASDF_OUTPUT_DIR`, or a
temporary `nshell-asdf/` directory when that variable is unset:

```sh
NSHELL_SOURCE_TREE=/path/to/common-lisp-systems \
  sbcl --script run-tests.lisp
```

### The non-sandboxed integration run

Some cases need a real PTY, `stty`, and external binaries, which the Nix
sandbox does not provide; they are skipped inside `nix flake check` and run
instead in CI's `integration` job. Run them locally when changing PTY,
subprocess, terminal, or job-control behaviour:

```sh
nix develop --command sbcl --script run-tests.lisp
```

This covers the real-PTY interactive smoke tests, `Ctrl-C` recovery, and the
job-control lifecycle checks.

## Generate a coverage report

```sh
NSHELL_COVERAGE_DIR="$PWD/coverage" \
  nix develop -c sbcl --script scripts/coverage.lisp
```

The report is written to `coverage/cover-index.html`, with the gate result in
`coverage/coverage-summary.json`. Set `NSHELL_COVERAGE_DIR` to redirect both
artifacts. The default Nix check stores them under its `$out/coverage/` output.

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
