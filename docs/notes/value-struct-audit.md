# Value-struct audit

`define-value-struct` (`src/util/struct-macros.lisp`) now generates every applicable
value struct in nshell (37 converted this cycle). This table mechanically accounts
for **every** raw `defstruct` that remains, with the concrete reason it is not a
`define-value-struct` candidate. Regenerate by re-running the classifier over `src/`.

| struct | file | reason it stays a raw `defstruct` |
|---|---|---|
| `%argument-word-sequence` | `domain/completion/knowledge-base-candidates.lisp` | mutable — writable slot(s): words, latest, words-before-latest |
| `%attached-option-value-prefix` | `domain/completion/knowledge-base-candidates.lisp` | mutable — writable slot(s): option, value-prefix |
| `%buffer-clear-edit` | `presentation/input-state-buffer.lisp` | mutable — writable slot(s): plan |
| `%buffer-clear-plan` | `presentation/input-state-buffer.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%buffer-deletion` | `presentation/input-state-buffer.lisp` | mutable — writable slot(s): plan |
| `%buffer-deletion-plan` | `presentation/input-state-buffer.lisp` | mutable — writable slot(s): splice |
| `%buffer-deletion-request` | `presentation/input-state-buffer.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%buffer-insertion` | `presentation/input-state-buffer.lisp` | mutable — writable slot(s): plan |
| `%buffer-insertion-plan` | `presentation/input-state-buffer.lisp` | mutable — writable slot(s): splice |
| `%buffer-splice` | `presentation/input-state-buffer.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%catalog-command-entry` | `domain/completion/catalog-build.lisp` | mutable — writable slot(s): exclusive-options, command, synopsis, description, subcommands, flags, option-values |
| `%catalog-command-projection` | `domain/completion/catalog-data.lisp` | mutable — writable slot(s): exclusive-options, command, description, synopsis, subcommands, flags, option-values |
| `%command-list-components` | `domain/parsing/parser.lisp` | mutable — writable slot(s): commands |
| `%command-list-redirect-split-state` | `domain/parsing/ast-redirect-split.lisp` | mutable — writable slot(s): clean-commands |
| `%command-redirect-arg-cursor` | `domain/parsing/ast-redirect-split.lisp` | mutable — writable slot(s): arg |
| `%command-redirect-split-state` | `domain/parsing/ast-redirect-split.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%command-redirect-split-step` | `domain/parsing/ast-redirect-split.lisp` | mutable — writable slot(s): state |
| `%complete-parse-state` | `application/builtin-complete.lisp` | mutable — writable slot(s): command, flags, long-options, short-options, arguments, description, erase |
| `%completion-help-command-facts` | `domain/completion/knowledge-base-help.lisp` | mutable — writable slot(s): subcommands |
| `%completion-help-line-facts` | `domain/completion/knowledge-base-help.lisp` | mutable — writable slot(s): kind |
| `%completion-help-scan-state` | `domain/completion/knowledge-base-help.lisp` | mutable — writable slot(s): subcommands, flags, option-values, collecting-subcommands-p |
| `%completion-input-analysis` | `domain/completion/context.lisp` | mutable — writable slot(s): partial-input |
| `%completion-word` | `domain/completion/context.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%control-flow-body-scan` | `domain/parsing/control-flow.lisp` | mutable — writable slot(s): body |
| `%control-flow-boundary-consumption` | `domain/parsing/control-flow-sequence.lisp` | mutable — writable slot(s): separator |
| `%control-flow-clause-parse-result` | `domain/parsing/control-flow.lisp` | mutable — writable slot(s): clauses |
| `%control-flow-clause-scan` | `domain/parsing/control-flow.lisp` | mutable — writable slot(s): clauses |
| `%control-flow-diagnostic-span` | `domain/parsing/control-flow-data.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%control-flow-for-header-binding` | `domain/parsing/control-flow.lisp` | mutable — writable slot(s): var-name |
| `%control-flow-grouper-route` | `domain/parsing/control-flow-sequence.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%control-flow-header-args` | `domain/parsing/control-flow-data.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%control-flow-node-grouping` | `domain/parsing/control-flow.lisp` | mutable — writable slot(s): node |
| `%control-flow-node-span` | `domain/parsing/control-flow-data.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%control-flow-sequence` | `domain/parsing/control-flow-sequence.lisp` | mutable — writable slot(s): commands |
| `%control-flow-sequence-step` | `domain/parsing/control-flow-sequence.lisp` | mutable — writable slot(s): grouped-command |
| `%control-flow-stack-transition` | `domain/parsing/control-flow-data.lisp` | mutable — writable slot(s): stack |
| `%control-flow-switch-case-patterns` | `domain/parsing/control-flow.lisp` | mutable — writable slot(s): values |
| `%cursor-move-edit` | `presentation/input-state-buffer.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%cursor-move-request` | `presentation/input-state-buffer.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%external-process-redirect-plan` | `application/execute-pipeline-stage-external.lisp` | mutable — writable slot(s): stdout-target, merge-stderr-p, stdout-mode, stderr-target, stderr-mode |
| `%fd-redirect-token-text` | `domain/parsing/tokenizer-handlers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%file-completion-prefix-projection` | `domain/completion/filesystem.lisp` | mutable — writable slot(s): directory-prefix |
| `%file-completion-query` | `domain/completion/filesystem.lisp` | mutable — writable slot(s): directory-prefix |
| `%filesystem-candidate-set` | `domain/completion/filesystem.lisp` | mutable — writable slot(s): candidates |
| `%here-doc-body` | `domain/parsing/parser-here-doc.lisp` | mutable — writable slot(s): body, next-position |
| `%here-doc-consumption` | `domain/parsing/parser-here-doc.lisp` | mutable — writable slot(s): bodies, next-position |
| `%here-doc-consumption-state` | `domain/parsing/parser-here-doc.lisp` | mutable — writable slot(s): reversed-bodies, next-position |
| `%here-doc-delimiter-scan` | `domain/parsing/parser-here-doc.lisp` | mutable — writable slot(s): reversed-delimiters |
| `%here-doc-line` | `domain/parsing/parser-here-doc.lisp` | mutable — writable slot(s): text, next-position |
| `%here-doc-target-body-cursor` | `domain/parsing/parser-here-doc.lisp` | mutable — writable slot(s): body, remaining-bodies |
| `%history-last-argument-scan-state` | `domain/history/last-argument.lisp` | mutable — writable slot(s): last-argument, skip-redirect-target, seen-command-word |
| `%history-logical-word-cursor` | `domain/history/last-argument.lisp` | mutable — writable slot(s): remaining |
| `%history-token-window` | `domain/history/last-argument.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%input-edit-snapshot` | `presentation/input-state-undo.lisp` | mutable — writable slot(s): buffer, cursor-pos |
| `%input-session-clear` | `presentation/input-state-helpers.lisp` | mutable — writable slot(s): kind, overrides |
| `%kb-command-entry` | `domain/completion/knowledge-base.lisp` | mutable — writable slot(s): description, subcommands, flags, option-values, exclusive-options |
| `%mixed-sequence-build-state` | `domain/parsing/parser-assembly.lisp` | mutable — writable slot(s): sequence-commands, sequence-separators, pipe-group |
| `%parse-result-facts` | `domain/parsing/parse-result.lisp` | mutable — writable slot(s): ast |
| `%parsed-command-line-case-clause` | `domain/parsing/parse-result.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%path-command-query` | `domain/completion/filesystem.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%redirect-entry` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): kind, target |
| `%redirect-facts` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): text, kind, fd-dup-p |
| `%redirect-kind-fact-spec` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): kind, input-p, output-p, stderr-p, append-p |
| `%redirect-kind-facts` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): kind, input-p, output-p, stderr-p, append-p |
| `%redirect-output-destination-state` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): stdout-target, stdout-mode, stderr-target, stderr-mode |
| `%redirect-spec-entry` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): text, kind |
| `%redirect-target-policy` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): kind, target-required-p |
| `%reduced-command-entry` | `domain/parsing/parser-separator-data.lisp` | mutable — writable slot(s): command |
| `%reduced-command-stream` | `domain/parsing/parser.lisp` | mutable — writable slot(s): commands |
| `%separate-option-value-prefix` | `domain/completion/knowledge-base-candidates.lisp` | mutable — writable slot(s): option, value-prefix |
| `%separator-facts` | `domain/parsing/parser-separator-data.lisp` | mutable — writable slot(s): kind, token-type, text, continues-p |
| `%separator-rule-entry` | `domain/parsing/parser-separator-data.lisp` | mutable — writable slot(s): kind, token-type, text, continues-p |
| `%shell-character-boundary` | `domain/parsing/tokenizer-data.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%shell-input-blankness-spec` | `domain/parsing/tokenizer-data.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%shell-token-range-set` | `presentation/input-state-words-scan.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%source-function-consumption` | `application/builtin-source-reader.lisp` | mutable — writable slot(s): closed-p |
| `%source-function-definition-result` | `application/builtin-source-reader.lisp` | mutable — writable slot(s): remaining-lines |
| `%source-lines-step-result` | `application/builtin-source-reader.lisp` | mutable — writable slot(s): remaining-lines |
| `%structural-diagnostics` | `domain/parsing/parser.lisp` | mutable — writable slot(s): incomplete-p |
| `%structural-diagnostics-accumulator` | `domain/parsing/parser.lisp` | mutable — writable slot(s): incomplete-p, diagnostics |
| `%structural-diagnostics-input` | `domain/parsing/parser.lisp` | mutable — writable slot(s): commands |
| `%token-extent` | `domain/parsing/tokenizer-data.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%token-reduction-argument` | `domain/parsing/parser-reduction.lisp` | mutable — writable slot(s): value |
| `%token-reduction-diagnostic-policy` | `domain/parsing/parser-reduction.lisp` | mutable — writable slot(s): kind |
| `%token-reduction-result` | `domain/parsing/parser-reduction.lisp` | mutable — writable slot(s): commands, errors |
| `%token-reduction-state` | `domain/parsing/parser-reduction.lisp` | mutable — writable slot(s): current-args, current-cmd, current-cmd-token, pending-redirect-token, pending-sep, pending-sep-token, errors, all-cmds |
| `%tokenizer-ampersand-route` | `domain/parsing/tokenizer-handlers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%tokenizer-balanced-token-boundary` | `domain/parsing/tokenizer-readers.lisp` | mutable — writable slot(s): substitution-end |
| `%tokenizer-left-angle-route` | `domain/parsing/tokenizer-handlers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%tokenizer-left-paren-route` | `domain/parsing/tokenizer-handlers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%tokenizer-pipe-route` | `domain/parsing/tokenizer-handlers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%tokenizer-right-redirect-route` | `domain/parsing/tokenizer-handlers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%tokenizer-special-dispatch-route` | `domain/parsing/tokenizer-handlers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%tokenizer-word-scan-action` | `domain/parsing/tokenizer-readers.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `%transient-session-clear` | `presentation/input-state-session.lisp` | mutable — writable slot(s): kind, overrides |
| `%type-options` | `application/builtin-type-helpers.lisp` | mutable — writable slot(s): all-p, short-p, no-functions-p, color-p, query-p, path-p, force-path-p, type-p, help-p |
| `%undo-recording-step` | `presentation/input-state-undo.lisp` | mutable — writable slot(s): undo-stack, redo-stack |
| `%undo-recording-transition` | `presentation/input-state-undo.lisp` | mutable — writable slot(s): old-state, new-state, output, key-event |
| `%undo-stack-step` | `presentation/input-state-undo.lisp` | mutable — writable slot(s): snapshot, undo-stack, redo-stack |
| `argument-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `arithmetic-substitution` | `domain/expansion/arithmetic.lisp` | helper-collision — `%arithmetic-substitution-end` already names a 2-arg function; the macro's private accessor would clash (verified by revert) |
| `ast-node` | `domain/parsing/ast.lisp` | include-hierarchy BASE — 12 subtypes `:include` it; cannot become a define-value-struct parent |
| `begin-end-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `brace-expansion-frame` | `domain/expansion/brace.lisp` | mutable — writable slot(s): input |
| `case-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `command-list-redirect-split-result` | `domain/parsing/ast-redirect-split.lisp` | mutable — writable slot(s): clean-commands |
| `command-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `command-redirect-split-result` | `domain/parsing/ast-redirect-split.lisp` | mutable — writable slot(s): clean-command |
| `completion-context` | `domain/completion/context.lisp` | mutable — writable slot(s): argument-words |
| `completion-query` | `domain/completion/engine.lisp` | mutable — writable slot(s): partial-input |
| `config` | `domain/configuration/config.lisp` | accessor/type mismatch — public reader `config-prompt` maps to slot `prompt-format`; the macro would emit `config-prompt-format` instead |
| `env-var` | `domain/environment/env.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `environment` | `domain/environment/env.lisp` | capsule — read-only, but its slots have no public readers (behavior-only API); the macro would leak them |
| `error-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `event-dispatcher` | `application/event-dispatcher.lisp` | mutable — writable slot(s): subscribers, queue |
| `for-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `here-doc-target-replacer` | `domain/parsing/parser-here-doc.lisp` | mutable — writable slot(s): bodies, target-pending-p |
| `if-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `incomplete-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `input-state` | `presentation/input-state-core.lisp` | mutable — writable slot(s): cursor-pos, completion-index, completion-base-buffer, completion-base-cursor, last-candidates, suggestion, mode, vi-count, vi-visual-anchor, abbreviation-expander, kill-ring, last-yank-start, last-yank-end, last-yank-index, last-argument-start, last-argument-end, last-argument-index, search-query, search-original-buffer, search-original-cursor, search-index, undo-stack, redo-stack, buffer |
| `job` | `domain/execution/job.lisp` | mutable — writable slot(s): state-kw, pgid-int, exit-code-int, pids-list, command-line-str, background-visible-p |
| `job-monitor` | `domain/job-control/monitor.lisp` | mutable — writable slot(s): jobs-table, next-id-int |
| `job-wait-event` | `application/manage-job.lisp` | mutable — writable slot(s): pid, state, status-code |
| `knowledge-base` | `domain/completion/knowledge-base.lisp` | mutable — writable slot(s): commands |
| `operator-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `pipeline-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `pty-process` | `infrastructure/acl/pty.lisp` | mutable — writable slot(s): pid, pgid, master-fd, stream |
| `redirect-output-destinations` | `domain/parsing/parser-data.lisp` | mutable — writable slot(s): stdout-target, stdout-mode, stderr-target, stderr-mode |
| `rule-knowledge-base` | `domain/completion/rule-data.lisp` | mutable — writable slot(s): facts, rules |
| `sequence-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `shell-context` | `application/shell-context.lisp` | mutable — writable slot(s): history, config, knowledge-base, environment, dispatcher, job-monitor, alias-table, abbreviation-table, function-table, function-source-table, filesystem-fns, process-fns, terminal-fns, redirect-fns, execution-strategy, running, last-exit-code, input-state, process-registry, terminal-rows, terminal-cols |
| `theme` | `domain/configuration/theme.lisp` | encapsulation — the mutable `colors` hash-table is exposed only via `theme-color`/`theme-set-color`; the macro would leak a `theme-colors` reader |
| `token` | `domain/parsing/tokenizer-data.lisp` | mutable — writable slot(s): quote-style |
| `tokenizer-state` | `domain/parsing/tokenizer-data.lisp` | mutable — writable slot(s): input, len, cursor-pos, pos, tokens, incomplete |
| `vi-input-transition` | `presentation/input-state-vi-data.lisp` | mutable — writable slot(s): state |
| `while-node` | `domain/parsing/ast.lisp` | include-hierarchy — `:include ast-node`; the macro cannot generate an inheriting struct |
| `whitespace-field-scanner` | `domain/expansion/fields.lisp` | mutable — writable slot(s): boundaries, start |

**Total: 137 raw defstructs.** mutable: 93; capsule: 28; include-hierarchy: 13; accessor/type mismatch: 1; encapsulation: 1; helper-collision: 1

`command-history` and `history-entry` (both formerly `domain/history/`) are gone from this
count: generic history storage is now `history-kit:history`/`history-kit:history-entry`,
defined and audited in the `cl-history-kit` library itself, not in this tree. Only the
tokenizer-coupled last-argument structs above remain nshell's own.

Unexplained (needs review): **none** — every remaining defstruct has a concrete non-applicability reason.
