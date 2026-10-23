# Existing tests that pin conflicting behavior

This inventory records existing assertions that conflict with the use-case
catalog or its decisions. Decision IDs use the `D-*` prefix; use-case IDs such
as `B09` and `I06` name acceptance criteria, and `WP-*` IDs identify
implementation owners. Keep each assertion until its owner replaces the
behavior and validates the corresponding use case.

WP-R05 verified that startup diagnostics name the selected config file, tested
XDG path selection and explicit overrides separately, and confirmed that a
legacy `~/.nshellrc` is noticed but not loaded ([config tests](../integration/test-file-config.lisp)).

| File:line | Pinned behavior | Conflict |
| --- | --- | --- |
| `t/unit/test-input-state-commands.lisp:401` | Enter accepts the visible suggestion ` hello`, changes the buffer to `echo hello`, then requests execution. | Use case I06 and decision D-10 require Enter to execute only the text already typed. WP-E01 owns the editor behavior. |
| `t/e2e/test-smoke.lisp:319` | Runs `false; printf ... $status` through `nshell -c` and expects the nshell `$status` variable. | Decision D-09 and use case B09 require `-c` to delegate to `/bin/sh`; nshell-specific syntax and variables must use the nshell code interface. WP-R04 owns `-c`. |
| `t/e2e/test-smoke.lisp:328` | Runs a pipeline through `nshell -c` and expects `$pipestatus`. | Decision D-09 and use case B09 require `-c` to use `/bin/sh`, not the nshell evaluator. WP-R04 owns `-c`. |
| `t/unit/test-parser-control-flow.lisp:112` | Treats shell-style `if`, `for`, `while`, `begin`, and `switch` blocks closed by `end` as the parser's accepted control syntax. | Decision D-01 requires control syntax to use S-expressions. Decision D-02 keeps the old reader and its tests until the cutover; WP-X01 owns that switch and test removal. Keep these assertions until the WP-X01 cutover gate described in the [syntax design](../../docs/notes/sexp-syntax-design.md). |
| `t/unit/test-builtins-source-control-flow.lisp:46` | Expects sourced fish-style `switch`/`case`/`end` blocks to execute. | Decision D-01 requires control syntax to use S-expressions. Decision D-02 keeps the legacy reader and tests until cutover; WP-X01 owns that switch and test removal. Keep this assertion until the WP-X01 cutover gate described in the [syntax design](../../docs/notes/sexp-syntax-design.md). |
