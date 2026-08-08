# Coverage analysis

## Measured baseline

Running `scripts/coverage.lisp` with SBCL `sb-cover` over `src/` measured
**86.9% expression coverage** and **82.2% branch coverage**. Those are the
only coverage figures this project should claim until the report is regenerated
after a later change.

The report is useful for locating executable branches such as `main` command
dispatch and process cleanup. It is not a release criterion that can be made
100% by adding tests alone: its source-level denominator also includes static
catalog data, declarations, macro-expansion forms, custom-constructor
`defstruct` defaults, and code supplied by Nix dependencies.

## What the suite verifies

- Unit and integration tests cover parser, completion, environment, process,
  timeout, and command-dispatch behaviour.
- The Linux/Nix flake check also runs the weave suite, formatting, benchmark
  artifact integrity, package build, and a packaged-binary smoke test.
- PTY/terminal-specific behaviour requires an appropriate PTY-capable runner;
  a headless local macOS run is not evidence of that layer's complete coverage.

## Coverage policy

Do not call the project "100% covered" based on a filtered HTML report. Treat
the raw `sb-cover` expression and branch values as the published baseline, and
use targeted tests for every newly introduced executable branch. If a release
gate needs a numeric threshold, define a reproducible metric that excludes
non-executable generated/static forms before enforcing it in CI.

## Reproduce

```sh
NSHELL_COVERAGE_DIR=/tmp/cov nix develop 'path:.' --command sbcl --script scripts/coverage.lisp
```

Open `/tmp/cov/cover-index.html` after the command completes. Record the
generated expression and branch values with the environment and SBCL version;
do not compare reports produced with different instrumentation inputs.
