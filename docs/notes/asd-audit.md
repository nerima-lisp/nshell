# nshell.asd audit

A mechanical cross-check between `nshell.asd`'s three system definitions and
the actual file tree, plus a manual pass over metadata-key ordering and
component ordering, run as the `.asd` counterpart to `flake.nix`'s own
extensively-commented review.

## Method and result: component lists vs. the file tree

Every `(:file "...")` entry was checked against the pathname declared by its
containing component in each of the three `defsystem` forms (`nshell`,
`nshell/test`, `nshell/weave`). The runtime comparison includes the shared
`src/` tree, the command-line feature under `packages/feature/`, and the
explicit static-data files under `data/`; the test comparisons cover `t/`
(excluding `t/weave/`) and `t/weave/` respectively:

| system | components | in tree but missing from components | in components but missing from tree |
|---|---|---|---|
| `nshell` | matches the declared `src/`, feature, and `data/` roots | none | none |
| `nshell/test` | matches `t/` (non-weave) exactly | none | none |
| `nshell/weave` | matches `t/weave/` exactly | none | none |

No declared component points at a missing file, and the production files are
all reachable from one of the declared roots. The static tables intentionally
live in `data/` while remaining part of the serial runtime system through
explicit `:pathname` entries. The one apparent duplicate `:file "package"` is
not a bug: `nshell`'s is `src/package.lisp` and `nshell/test`'s is `t/package.lisp`,
distinct files under each system's own `:pathname`.

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

- All package modules load before every logic file, so no file can reference a
  package before it exists. The completion catalog is split into command data
  and display data, and REPL output event handlers have their own component.
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

No drift between `nshell.asd` and its declared roots, no ordering violation,
and the metadata-order question (duplicate `:file "package"`) resolves to a
non-issue on inspection. Re-run the cross-check by resolving each component's
effective pathname (including `:pathname` overrides) and comparing it with
`rg --files src packages data t -g '*.lisp'`, while treating `t/weave/` as the
separate weave system.
