# paredit-cli usage inventory

Which structural refactors in this codebase were driven by
[paredit-cli](https://github.com/nerima-lisp/paredit-cli) rather than hand
edits, and which read-only inspections steered them. paredit is preferred for
anything that must stay balanced or must resolve symbols across files; a manual
edit is only used when the change is a localized text substitution paredit has
no operation for (e.g. deleting one already-located `defun`, editing a
docstring).

## Analysis passes (read-only, `paredit inspect …`)

| command | what it drove |
|---|---|
| `inspect unused-definitions src/**/*.lisp t/**/*.lisp` | the dead-code audit (`docs/notes/dead-code-audit.md`): 179 candidates → 18 bulk-removable, each then verified a false positive. Scanning src+t together is what collapsed the 239 src-only candidates. |
| `inspect duplicates src/**/*.lisp` | found the four byte-identical prefix helpers later consolidated into `nshell.util:string-prefix-p`, and confirmed the top clone shapes were idiomatic `let` bindings that must *not* be macro-ified. |
| `inspect duplicates t/unit/*.lisp` | located the same-shape `it`-block clusters that became `it-each` tables (tokenizer word/redirect/command-sub/process-sub, parser diagnostics). |

## Structural rewrites (`paredit refactor …`)

| command | edit |
|---|---|
| `refactor replace-function-calls --from %starts-with-p --to string-prefix-p --write` | rewrote 10 call sites across four completion files in one pass — then *reverted* with the inverse call when the bodies proved to differ (`string-equal` vs `string=`); the reversibility is why a structural tool was used rather than sed. |
| `refactor replace-function-calls --from %string-prefix-p / %case-sensitive-prefix-p / starts-with-p --to string-prefix-p --write` | rewrote the remaining 8 case-sensitive call sites onto the shared helper. |

## Where manual edits were correct instead

- Deleting a single already-located `defun` (the three consolidated prefix
  helpers, `%read-all-lines`, `fake-git-process`): a one-form removal at a known
  location, no rebalancing across siblings.
- Rewriting function *bodies* (git timeout, `spawn-async` decomposition): these
  are semantic rewrites, not structural moves — paredit's value is in balanced
  motion and cross-file symbol resolution, neither of which a body rewrite needs.
- `it-each` conversions: replacing N `it` forms with one `it-each` form is a
  content substitution, verified by re-running the suite, not a structural motion
  paredit exposes.

## Principle

paredit-cli is used wherever a refactor is *structural* (balanced deletion,
cross-file call/symbol rewrite) or wherever a *report* can replace guesswork
(unused, duplicates, similarity). It is not forced onto semantic body rewrites,
where a direct edit verified by the test suite is clearer. Every `--write` pass
above was gated by a preceding read-only report and followed by the full
`nshell/test` run.

## Reproducible development tool

The flake development shell provides `paredit-cli` as a development-only
input, pinned independently from nshell's runtime dependencies. This keeps
the preferred structural-editing workflow available through `nix develop`
without making the delivered executable depend on the refactoring tool.

The shell exposes `paredit` with read-only `inspect` commands, structural
`refactor` commands, and guarded `--write` operations. Check the installed
command with:

```sh
nix develop --command paredit --version
```
