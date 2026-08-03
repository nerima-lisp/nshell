# Backward-compatibility audit

Every occurrence of "legacy", "deprecated", "backward-compat", "obsolete", or
"old-style" in `src/` and `t/` (case-insensitive, whole-tree grep), classified.

## Method

```
grep -rniE "deprecated|legacy|backward.?compat|for compat|kept for|old-style|obsolete" src/ t/
```

## Result: zero backward-compat code; eight regression guards against its return

Every hit is in `t/`, and every one is a **negative assertion** — a test
proving a legacy/unprefixed name does *not* exist, not code that keeps one
working:

| test | asserts |
|---|---|
| `test-parser-control-flow.lisp` `control-flow-stack-transition-rejects-legacy-string-frames` | the old raw-string stack-frame shape is rejected, not silently accepted |
| `test-tokenizer.lisp` (tokenizer-state construction) | `MAKE-TOKENIZER-STATE`/`COPY-TOKENIZER-STATE` (the old unprefixed, unvalidated constructor/copier defstruct would auto-generate) are not `FBOUNDP`; only the invariant-checking `%MAKE-TOKENIZER-STATE-FOR-INPUT` is |
| `test-parser-diagnostics.lisp` (parse-result construction) | `MAKE-PARSE-RESULT`/`MAKE-PARSE-DIAGNOSTIC` are not `FBOUNDP`; only `%MAKE-NORMALIZED-PARSE-RESULT` is |
| `test-parser-diagnostics.lisp` `structural-diagnostics-has-no-legacy-multiple-value-wrapper` | the old raw-argument multiple-value API is gone |
| `test-completion-context.lisp` (completion-context construction) | no legacy unprefixed helper names are defined in the package |
| `test-completion-context.lisp` (path-command helpers) | no unprefixed legacy names are exported |
| `test-completion-context.lisp` (file-completion helpers) | no unprefixed legacy names are exported |
| `test-repl-completion-data.lisp` (catalog-derived-data helpers) | no unprefixed legacy symbols remain in the package |

The two `src/` hits for the word "removed" are unrelated to compatibility —
both are docstrings describing ordinary data transformation ("redirect args
... are removed from the args list" during parsing), not code kept around
for callers of an old API.

## Conclusion

There is no backward-compatibility shim, deprecated alias, or dual-path
"old behavior vs. new behavior" branch anywhere in `src/`. The pattern this
codebase uses instead — visible in every hit above — is to delete the old
name outright when a value struct or helper is redesigned, and add a test
that asserts its absence, so a future refactor cannot silently reintroduce
it by accident (e.g. by letting `defstruct` regenerate an unprefixed
`MAKE-`/`COPY-` pair nothing calls). "Backward-compat は撲滅してほしい,
理想的なコードのみ残して" is met by construction, not by a one-time sweep.
