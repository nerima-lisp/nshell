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
| `t/unit/test-parser-control-flow.lisp:112` | Tests shell-style `if`, `for`, `while`, `begin`, and `switch` blocks closed by `end` through `parse-command-line`. | WP-X01 completed the default-reader cutover. This assertion covers the retained bare-line command parser API; it does not define the default S-expression control syntax. Keep it while that parser API remains supported. |
| `t/unit/test-builtins-source-control-flow.lisp:193-208` | Tests sourced `function foo; echo hi; end` definitions, including a trailing inline command. | WP-X01 completed the default-reader cutover, and WP-X01b removed the old REPL reader route and its opt-in. These assertions cover the source reader's retained bare-line function-definition compatibility path; they do not define the default S-expression source syntax. Keep them while that path remains supported. |
| `t/integration/test-file-config.lisp:82` | Expects config-load errors to be labeled `.nshellrc`. | D-10 retires `~/.nshellrc` in favor of the XDG config location; diagnostics should identify the active config source. WP-R05 owns config placement. |
| `t/integration/test-file-config.lisp:91` | Expects config-read errors to be labeled `.nshellrc`. | D-10 retires `~/.nshellrc` in favor of the XDG config location; diagnostics should identify the active config source. WP-R05 owns config placement. |
