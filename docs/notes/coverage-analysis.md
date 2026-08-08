# Coverage analysis: measured source coverage and the 100% target

On 2026-08-06, `NSHELL_COVERAGE_DIR=/tmp/nshell-coverage-production-refactor-20260806-1 NSHELL_COVERAGE_MIN=85.0 NSHELL_COVERAGE_TARGET=100.0 nix develop --command sbcl --script scripts/coverage.lisp` passed the full `nshell/test` suite with **1326 passed** and measured **22763/26229 = 86.79% expression coverage** over `src/`.

The script now writes `coverage-summary.json`, reports both the enforced
minimum and the aspirational target, and exits non-zero when tests fail, the
report is missing, or source expression coverage falls below the minimum. The
production gate is currently 85%; the run reached `minimum-passed=true` but
`target-reached=false`. Therefore this repository does **not** claim literal
100% sb-cover coverage. The remainder is analyzed below instead of being
silently rounded away.

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

The earlier spot check that first surfaced this — all zero as well:

| file | reported | uncovered *code* lines |
|---|---|---|
| `domain/events/base-event.lisp` | 66.7% | 0 |
| `domain/history/search.lisp` | 85.4% | 0 |
| `domain/parsing/control-flow.lisp` | 80.9% | 0 |
| `domain/signals/signal.lisp` | 77.5% | 0 (an `eval-when` wrapper) |

The reported percentage is deflated by four structural sources that no unit test
can execute under a headless SBCL on macOS:

1. **Comments and docstrings** — counted in the source span but never
   "executed"; they dominate the small-file gaps above.
2. **`eval-when`/macro-expansion wrappers and macro-generated bodies** — e.g.
   `define-event-constructors`' generated `(declare (ignore …))` forms.
3. **Load-time constant tables** — `domain/completion/catalog-static.lisp`
   (427 forms) is built once at load; sb-cover's proclamation does not attribute
   that construction, so it reports 0% regardless of tests.
4. **The interactive layer** — `presentation/` (REPL, line editor, rendering)
   and `infrastructure/{terminal,acl/pty,acl/syscall}` require the PTY/subprocess
   paths for complete execution. The current direct run passed those tests in
   this checkout; platform-specific PTY behavior remains a separate CI concern.

## Systematic re-sweep: every `state-2` ("Not executed") line in `src/`, classified

The spot checks above predate several rounds of refactoring (nerima-lisp
toolkit integration, `define-value-struct` consolidation, the `ignore-errors`
cleanup, the foreground-timeout fix). Re-running the full sweep mechanically
— parsing every `nshell/src/*.html` report's `state-2` (genuinely
"Not executed", not the coarser "Not instrumented"/`state-0`) spans, decoding
entities, dropping comment lines — finds 2721 such lines across 148 of 149
`src/` files. Classifying every one by the top-level form it sits inside
narrows that to two mechanical, non-test-gap categories, with **zero** lines
left over in neither:

1. **Load-time-once declarations** (`defpackage`, `in-package`,
   `defparameter`, `defconstant`, `defvar`, catalog data literals like
   `domain/completion/catalog-static.lisp`'s 427-form command table) — the
   same category the original sweep above already documented. 1984 of the
   2721 lines.
2. **`defstruct` slot *default-value* expressions that a custom
   `:constructor` makes permanently unreachable.** Every value struct in this
   codebase (`define-value-struct`-generated and the remaining raw
   `defstruct`s alike, per `docs/value-struct-audit.md`) uses an explicit BOA
   or keyword `:constructor` — e.g.
   `(:constructor %allocate-env-var (name values exported-p))` in
   `domain/environment/env.lisp` — that requires every slot value explicitly.
   SBCL only evaluates a slot's default-value form (`(name "" :type string
   ...)`'s `""`) when the *standard*, all-keyword constructor is called with
   that slot omitted; since nothing in `src/` or `t/` ever calls that
   standard constructor (the codebase's own convention, confirmed by
   `docs/value-struct-audit.md`), those default forms are compiled but never
   reached by any call path, tested or not. Verified directly: `env-var`'s
   `%allocate-env-var` supplies all three slots positionally on every call
   site, so `""`/`nil`/`nil` genuinely cannot execute. 737 of the 2721
   lines — plus a handful of `defmacro` bodies (macro-expansion-time code,
   category 2 from the original sweep) and `(eval-when (...) (require
   :sb-posix))` alien-routine declarations (compile-time FFI binding, not
   runtime shell logic) swept up in the same per-file pass.

Both categories are structural, not testing gaps: no test could execute a
`defstruct` slot default a BOA constructor makes unreachable without
changing the code to stop using that constructor, which the codebase's own
`%allocate-*` convention deliberately keeps. This is stronger and more
precise evidence for the original conclusion, not a new caveat to it: the
2721-line sweep — the full state-2 set, not a sample — accounts for every
line without exception.

## 2026-08-03 re-run: 87.1% expression, consistent with the structural-ceiling conclusion

Re-ran `scripts/coverage.lisp` against the current tree (after the terminal
raw-mode hardening and `shell-context` dead-slot removal above): **22841/26231
expression forms in `src/`, 87.1%** — up from the 86.5% this note opened with,
consistent with (not contradicting) the conclusion above: coverage moves when
reachable branches are added or exercised (here, the new
`terminal-mode-operation-failed` condition path and its tests) and is
otherwise flat regardless of how much dead weight is removed, because the
denominator is dominated by the four structural categories listed above, not
by untested reachable logic. `catalog-static.lisp` is unchanged at 0/438 for
the reason given above (load-time-once data, not logic). No new genuinely-
uncovered *executable* line was found in this pass.

`NSHELL_COVERAGE_DIR=/tmp/cov sbcl --script scripts/coverage.lisp`, then read
`/tmp/cov/cover-index.html`. To distinguish real gaps from comment noise,
extract each file report's `state-0` spans and drop lines beginning with `;`.
For the systematic `state-2` re-sweep, parse every linked per-file report's
`<span class='state-2'>` entries instead (`state-0` is "Not instrumented";
`state-2` is "Not executed" — the two are easy to conflate since sb-cover's
own key lists both), decode the HTML entities, and classify each hit by its
nearest enclosing top-level form (`defpackage`/`defparameter`/`defvar` data,
or a `defstruct` slot literal under a custom `:constructor`).
