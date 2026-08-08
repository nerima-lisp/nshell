# Dead-code audit

A whole-tree `paredit inspect unused-definitions` scan over `src/` **and**
`tests/` together (so cross-references from tests count), and the verification
that every remaining flag is a false positive rather than removable code.

## Method

```
paredit inspect unused-definitions --output json \
  src/**/*.lisp src/*.lisp tests/**/*.lisp tests/*.lisp
```

Scanning src *with* tests matters: scanning `src/` alone reports 239 candidates
because every public accessor and factory looks unused (its only callers are the
test suite). With tests included the count falls to 179, of which paredit marks
18 `bulk_removable`.

## The 18 bulk-removable flags are all false positives

| flag | category | actually used at | why the scan misses it |
|---|---|---|---|
| `main` | function | dumped-executable entry point | not on any in-tree call path |
| `run-tests` | function | `nshell.asd:299`, `scripts/coverage.lisp:43` | invoked via `(funcall (find-symbol "RUN-TESTS" "NSHELL/TEST"))` — a string, invisible to static call graphs |
| `%inject-os-environment-entry` | function | `domain/environment/env.lisp:145` | called inside a `dolist`/`setf` the resolver doesn't trace |
| `string->octets`, `pty-test-*`, `%e2e-pty-*`, `%terminate-pty-process` | function | the PTY test bodies | called inside cl-weave `it`/`describe` macro expansions (paredit's `unknown-macro` category) |
| `open-pty-darwin`, `open-pty-linux`, `%pty-fork-exec`, `pty-spawn`, `with-pty`, `skip-when-pty-round-trip-unreliable` | function/macro | `infrastructure/acl/pty.lisp` + PTY tests | platform dispatch under `#+darwin`/`#+linux` reader conditionals and macro-wrapped call sites |

The other 161 candidates split into `struct` (103) and `unknown-macro` (58):

- **`struct` (103):** `define-value-struct` type names such as `%glob-match-subject`
  or `%domain-event`. The generated *constructor* (`%make-glob-match-subject`) is
  what call sites use, so the type name reads as "defined but uncalled". Removing
  it would delete the struct.
- **`unknown-macro` (58):** definitions emitted by macros paredit does not expand,
  so their references (also macro-generated) are invisible.

## Conclusion

No genuinely dead definition remains. The real dead code was already removed in
earlier paredit-driven passes (`Remove unused virtual screen module`, `Remove 8
more dead functions found via paredit's unused-definitions scan`). This scan is
the negative result that confirms the tree is clean; re-run the command above and
expect the same 18 structurally-explained false positives.
