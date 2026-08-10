# Removed API and alias audit

The current source tree keeps no compatibility aliases or dual behavior paths.
The tests below make selected removals explicit, so a later redesign cannot
silently regenerate the old public names.

## Reproduction

```
rg -n -i "deprecated|legacy|backward.?compat|for compat|kept for|old-style|obsolete" src t
```

The command is expected to find only removal-oriented tests and no runtime
compatibility path. Classify every hit before treating the result as clean.

## Removal guards

The relevant hits are negative assertions — tests proving an unprefixed name
does not exist, not code that keeps one working:

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

## Conclusion

No compatibility shim or deprecated alias is present in the runtime source.
When a value struct or helper is redesigned, the old name is deleted and the
absence of the unprefixed constructor or copier is tested. This keeps the
public surface intentionally current rather than preserving an obsolete API.
