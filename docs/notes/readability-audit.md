# Readability audit

A whole-tree, metric-based review of whether nshell is written human-readably.
Readability is subjective, so this measures the objective proxies that correlate
with it — function size, nesting depth, and how the outliers were handled — and
records where deliberate density is justified.

The numeric values below are a historical metric snapshot. Re-run the metric
sweep against the current tree before using them as release evidence.

## Structural metrics (1681 `defun`s across `src/`)

| metric | value | reading |
|---|---|---|
| function length, median | 5 lines | most functions are one idea |
| function length, p90 | 16 lines | the long tail is still screen-sized |
| function length, max | historical snapshot | load-time catalog data is split between command and display tables |
| nesting depth, median | 4 | shallow — reads top-to-bottom |
| nesting depth, p90 | 8 | branch-heavy dispatch, still followable |
| functions ≥ 40 lines | 22 | mostly initarg plists and constructors (flat, not complex) |

A median 5-line, depth-4 function body is the core readability result: the code
is built from many small, single-purpose, shallow functions rather than a few
large ones. The DDD layering (domain / application / infrastructure /
presentation, one concern per file) reinforces this at the
file scale — see `docs/dead-code-audit.md` and the file-split history.

## Deep-nesting outliers, and how they were driven down

Depth, not length, is the readability killer. The deepest bodies were flattened
by extracting single-purpose helpers and separating data from logic:

- `spawn-async` (infrastructure): depth 15 → 9. Extracted
  `%resolve-input-redirect` / `%resolve-output-redirect` (taking a `register`
  continuation for cleanup) and `%spawn-in-own-process-group`.
- `%builtin-command-path` (application): depth 14 → 9. Lifted the `emit-name`
  `labels` to a top-level `%emit-command-path`, extracted the nested
  `format`-in-`format` "not found" line into `%command-path-missing-message`,
  and turned the `if args` into a leading `(if (null args) …)` guard so the main
  path stops being nested inside it.

Both remain covered by the integrated suite; the current pass/fail result must
be taken from the verification command for the current tree.

## Where density is deliberate

- `glob-match-p` and the arithmetic Pratt integration stay moderately deep
  because they encode a recursive grammar; each branch is a single grammar rule
  with an explanatory comment, which reads better than hoisting one-use labels.
- `%`-prefixed helpers (the large majority of the 1681) intentionally carry no
  docstring: the private name states the one thing they do, and a docstring would
  restate the name. Public factories/accessors are likewise self-titling.

## Conclusion

The codebase is composed of small, shallow, single-purpose functions with the
few genuine outliers driven down by helper extraction; remaining depth is
grammar-encoding where flattening would hurt clarity. Re-run the metric sweep
over `src/**/*.lisp` to measure the current median length and depth.
