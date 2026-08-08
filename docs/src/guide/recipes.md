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
[cl-dataflow](https://github.com/nerima-lisp/cl-dataflow) computation-graph
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
nix develop -c sbcl --script scripts/coverage.lisp
```

The report is written to `coverage/cover-index.html`. Set `NSHELL_COVERAGE_DIR`
to redirect the output.

## Add a test

Unit, integration, property-based, and end-to-end tests live under `t/` and run
under [cl-weave](https://github.com/nerima-lisp/cl-weave) using
`describe`/`it`/`expect`. Changes to shell-language, expansion, completion,
job-control, or input-state behaviour should carry a focused regression test,
plus property or PTY coverage when the change crosses a process, terminal, or
parser boundary.
