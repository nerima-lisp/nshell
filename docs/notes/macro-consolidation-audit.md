# Macro consolidation audit: `defmacro` に可能な限り全て寄せたい

A whole-tree review of whether repeated, boilerplate-heavy patterns in `src/`
are captured by a `defmacro`, and where they deliberately are not.

## Already macro-driven

Beyond `define-value-struct` (`docs/notes/value-struct-audit.md`), 26 other
`defmacro` forms exist in `src/`, several purpose-built for exactly the
boilerplate categories this goal targets:

- **Builtin command dispatch.** `define-builtin`
  (`application/builtin-macros.lisp`) auto-generates ignore-declarations;
  `%with-option-arguments` / `%with-required-argument`
  (`application/builtin-runtime.lisp`) capture the shared "parse leading
  option flags, validate required args" skeleton; `%table-builtin-case`
  (`application/builtin-state-tables.lisp`) captures the `-e`/`-q`/default
  dispatch shared by `alias`/`abbr`/`function`; `define-plist-accessors`,
  `define-string-line-builtin`, `with-string-options`
  (`application/builtin-string-support.lisp`) cover the `string` subcommand
  family; `define-test-predicate-table` (`application/builtin-test.lisp`)
  covers `test`/`[`. Registration itself is a single data table
  (`+builtin-registry-specs+` in `data/application/builtin-spec-data.lisp`),
  not hand-written per-command code.
- **Value structs.** 37 value structs generate their
  accessor/predicate/constructor boilerplate from `define-value-struct`
  instead of by hand (`docs/notes/value-struct-audit.md`).
- No repeated `defclass` boilerplate exists (`rg -n "defclass" src` is
  empty) and `define-condition` appears exactly once — nothing to
  consolidate there.

## The one genuine straggler found, and fixed

20 sites hand-rolled `(handler-case FORM (error () nil))` /
`(handler-case FORM (error ()))` where the codebase already uses
`ignore-errors` 47 times elsewhere for the identical shape — not a new
pattern to invent, just consistency to restore. Converted each individually
via `paredit edit replace` (diff preview, write, `paredit inspect check`)
across `application/builtin-runtime.lisp`, `domain/completion/filesystem-file-completion.lisp`, `domain/completion/filesystem-path-command.lisp`,
`domain/expansion/expand.lisp`, `infrastructure/acl/{syscall-job-control,
syscall-pipeline,syscall-process}.lisp`, `infrastructure/persistence/
file-history.lisp`, `infrastructure/terminal/{input-core,raw-mode}.lisp`, and
`presentation/{autosuggest,repl-environment,repl-session}.lisp`.

One `handler-case` in `repl-session.lisp` (`install-interactive-terminal`'s
signal-handler installation) was left alone: its `(error (condition) ...)`
clause binds and logs the condition, which `ignore-errors` cannot express.

`%seq-parse-args` (`application/builtin-commands.lisp`) was converted, then
**reverted** after the full suite caught a real behavioral difference:
`ignore-errors`'s error path returns `(values nil condition)`, while
`(handler-case FORM (error () nil))`'s explicit `nil` body returns exactly
one value. `%seq-parse-args` is a genuine multiple-values producer
(`(values first step last)` on success), so leaking a second value on the
error path changes its contract even though its only caller
(`multiple-value-bind (first step last) ...`) happens not to observe it —
the test suite's `(multiple-value-list ...)` assertion did. `ignore-errors`
is not a safe substitute for `handler-case` on a function whose return
arity is part of its contract; this is why the conversion was reviewed
per-site with a full test run, not applied as a blind find/replace.

## Considered and rejected

- **Terminal-width-with-80-fallback**, triplicated across
  `presentation/{completion-ui,prompt-display,repl-rendering}.lisp`, is
  genuine duplicate logic but not boilerplate a macro would help — it needs
  one shared function, not a code shape to abstract. Left as a follow-up
  function-extraction item, not a macro.
- **The `ast-node` `:include` hierarchy** (`domain/parsing/ast.lisp`): 7 of
  12 node types share a `defstruct (:include ast-node)` + public
  `make-X-node` copying-wrapper shape, but the argument arity, optional-arg
  position, and per-slot copier function all vary enough that capturing it
  would need a small spec DSL for a ~4-5 line-per-site saving across 7
  sites — the "three similar-but-different lines" trap this project's own
  `docs/cps-audit.md` warns against. Left as raw `defstruct`s, consistent
  with `docs/notes/value-struct-audit.md`'s stated reason (`define-value-struct`
  assumes no inheritance).

## Conclusion

"defmacroに可能な限り全て寄せたい" was already substantially executed across
prior refactoring rounds; this audit's one actionable finding (`ignore-errors`
consistency) is applied. What remains unconverted is either better solved
without a macro or is a narrow, higher-risk case for a modest win, both
consistent with this project's readability-bounded reading of "as much as
possible" (`docs/cps-audit.md`).
