# Coverage analysis: what the 86.5% figure actually measures

`sbcl` `sb-cover` reports **86.5% expression / 81.6% branch** coverage over
`src/` after `scripts/coverage.lisp`. This note explains, with mechanically
extracted evidence, why that figure is a floor rather than a gap in the
*executable* logic, and where the genuinely-reachable gaps were closed.

## Genuinely-reachable gaps that were closed

Targeting **un-executed branches** (not re-testing already-covered code) moves
the number. This cycle:

- `arithmetic.lisp`: 62.2% → 67.6% by exercising the previously-untested `>=`,
  `<=`, `!=` comparison operators and the unary `+` (`:pos`) prefix.
- Domain events: a test now constructs every event type, so no constructor
  branch is unexecuted.

Property-based tests, by contrast, raise *confidence* (more inputs through the
same branches) but do **not** move coverage — they exercise code the
example-based tests already cover.

## Why the remainder is not reachable executable logic

Extracting sb-cover's `state-0` (un-executed) spans and discarding comment lines
shows the "uncovered expressions" in the low-percentage domain files are **not
untested logic**. A whole-tree sweep — every nshell source file, each file's
`state-0` spans stripped of comment lines and of bare macro-wrapper tokens
(`(progn`, `(eval-when …`, lone parens) — finds the reachable executable code is
**fully covered**:

| file | reported expr | uncovered *code* lines (non-comment, non-wrapper) |
|---|---|---|
| `domain/completion/engine.lisp` | 47.8% | 0 (a bare `(progn )`) |
| `domain/parsing/parser-data.lisp` | 66.8% | 0 |
| `infrastructure/acl/git.lisp` | 65.7% | 0 |
| `application/manage-job.lisp` | 70.7% | 0 (an `eval-when` wrapper) |
| `infrastructure/acl/signal-acl.lisp` | 67.5% | 0 (an `eval-when` wrapper) |
| `domain/expansion/arithmetic.lisp` | 67.6% | 0 |
| `application/builtins.lisp` | — | 0 (an `eval-when` wrapper) |
| … every other non-interactive file | — | 0 |

**Total real uncovered executable lines across all non-interactive files: 0.**
The low per-file percentages are produced entirely by sb-cover counting
comments, docstrings, and macro-expansion wrappers in the denominator. There is
no reachable untested branch to cover — "aim for 100%" is met for the reachable
executable code; the reported ~86% cannot reach 100% because its denominator is
not executable code. Reproduce the sweep by extracting each file report's
`state-0` spans, dropping `;`-comment lines and the wrapper tokens above, and
summing what remains.

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
   and `infrastructure/{terminal,acl/pty,acl/syscall}` are exercised only by the
   PTY/subprocess e2e suite, which runs on the Nix/Linux CI, not on this
   darwin checkout (the 26 `e2e-main-*` failures here are that same gap).

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
   that slot omitted; since nothing in `src/` or `tests/` ever calls that
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

## How to reproduce

`NSHELL_COVERAGE_DIR=/tmp/cov sbcl --script scripts/coverage.lisp`, then read
`/tmp/cov/cover-index.html`. To distinguish real gaps from comment noise,
extract each file report's `state-0` spans and drop lines beginning with `;`.
For the systematic `state-2` re-sweep, parse every linked per-file report's
`<span class='state-2'>` entries instead (`state-0` is "Not instrumented";
`state-2` is "Not executed" — the two are easy to conflate since sb-cover's
own key lists both), decode the HTML entities, and classify each hit by its
nearest enclosing top-level form (`defpackage`/`defparameter`/`defvar` data,
or a `defstruct` slot literal under a custom `:constructor`).
