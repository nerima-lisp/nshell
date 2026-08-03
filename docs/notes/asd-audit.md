# nshell.asd audit

A mechanical cross-check between `nshell.asd`'s three system definitions and
the actual file tree, plus a manual pass over metadata-key ordering and
component ordering, run as the `.asd` counterpart to `flake.nix`'s own
extensively-commented review.

## Method and result: component lists vs. the file tree

Every `(:file "...")` entry was extracted from each of the three `defsystem`
forms (`nshell`, `nshell/test`, `nshell/weave`) and diffed against a
recursive walk of `src/`, `t/` (excluding `t/weave/`), and `t/weave/`
respectively:

| system | components | in tree but missing from components | in components but missing from tree |
|---|---|---|---|
| `nshell` (150 files) | matches `src/` exactly | none | none |
| `nshell/test` (118 files) | matches `t/` (non-weave) exactly | none | none |
| `nshell/weave` (7 files) | matches `t/weave/` exactly | none | none |

No orphaned source file, and no component pointing at a file that does not
exist -- the failure mode `:serial t` systems are prone to (someone adds a
file and forgets the `.asd` entry, or deletes one and leaves it) is absent.
The one apparent duplicate `:file "package"` (275 total entries, one
repeated name) is not a bug: `nshell`'s is `src/package.lisp` and
`nshell/test`'s is `t/package.lisp`, distinct files under each system's own
`:pathname`.

## Metadata key order

The file's own header comment states the canonical order: `:description
:long-description :author :maintainer :license :version :homepage
:bug-tracker :source-control :depends-on :pathname :serial :components
:in-order-to`. All three `defsystem` forms follow it exactly (none declares
`:long-description`, so that key is simply absent from all three, which is
consistent -- an omitted key is still "in order" by not appearing out of
place). The three build keys (`:build-operation`/`:build-pathname`/
`:entry-point`) and the `:perform` methods are explicitly documented as
exempt from this order, per the org standard the header cites.

## Component ordering

`:serial t` makes load order significant, and it already encodes real
constraints, verified rather than assumed:

- The five `package*.lisp` files load before every logic file (this
  session's split), so no file can reference a package before it exists.
- `application/` loads before `infrastructure/`, which looks backwards for
  a layered architecture until read against `shell-context.lisp`: the
  application layer receives infrastructure's functions as *values*
  through dependency injection (`shell-context-filesystem-fns` and
  siblings), not through a compile-time package dependency, so
  infrastructure genuinely does not need to exist yet when application
  compiles.
- `infrastructure.terminal` does depend on `domain.input` directly
  (`:import-from`), and domain loads first -- consistent.

## Conclusion

No drift between `nshell.asd` and the tree, no ordering violation, and the
one metadata-order question (duplicate `:file "package"`) resolves to a
non-issue on inspection. Re-run the cross-check by extracting `(:file
"...")` names per `defsystem` and diffing against `find src -name '*.lisp'`
/ `find t -name '*.lisp'` (excluding `t/weave`) / `find t/weave -name
'*.lisp'`.
