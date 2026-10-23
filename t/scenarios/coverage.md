# Use-case coverage

This index maps each catalog use case to its scenario files. Per-use-case counts include every JSON file that lists that UC, so a shared scenario appears in each applicable row. The Total row counts unique scenario files selected by the runner and should equal its `selected` count.

A direct JSON scenario exercises the stated behavior and asserts a result through the scenario interface. A filename prefixed with `approx-` is an approximation that covers related behavior without claiming the full contract. A `manual.md` file records a check that requires a person; some UCs have both an executable scenario and a supplementary manual check.

| UC | Coverage | Executable scenarios | Manual checks | Scenario files |
| --- | --- | ---: | ---: | --- |
| A01 | approximation | 1 | 0 | `t/scenarios/A01/approx-terminal-launch.json` |
| A02 | approximation | 1 | 0 | `t/scenarios/A02/approx-tmux-pane-start.json` |
| A03 | direct, manual | 1 | 1 | `t/scenarios/A03/login-shell-command.json`, `t/scenarios/A03/manual.md` |
| A04 | direct, manual | 1 | 1 | `t/scenarios/A04/login-path-handoff.json`, `t/scenarios/A04/manual.md` |
| A05 | direct, manual | 1 | 1 | `t/scenarios/A04/login-path-handoff.json`, `t/scenarios/A05/manual.md` |
| A06 | direct, manual | 1 | 1 | `t/scenarios/A06/login-environment.json`, `t/scenarios/A06/manual.md` |
| A07 | direct, manual | 1 | 1 | `t/scenarios/A07/quiet-login-command.json`, `t/scenarios/A07/manual.md` |
| A08 | direct | 2 | 0 | `t/scenarios/A08/ctrl-d-exits.json`, `t/scenarios/A08/exit-warns-about-job.json` |
| A09 | approximation, manual | 1 | 1 | `t/scenarios/A09/WP-R01-hup-forwards-to-job.json`, `t/scenarios/A09/manual.md` |
| A10 | direct | 1 | 0 | `t/scenarios/A10/exec-replaces-shell.json` |
| A11 | manual | 0 | 1 | `t/scenarios/A11/manual.md` |
| A12 | direct | 1 | 0 | `t/scenarios/A12/no-config-skips-startup.json` |
| A13 | direct | 1 | 0 | `t/scenarios/A13/config-error-keeps-prompt.json` |
| B01 | direct, manual | 1 | 1 | `t/scenarios/B01/shell-caller-handoff.json`, `t/scenarios/B01/manual.md` |
| B02 | approximation | 2 | 0 | `t/scenarios/B01/shell-caller-handoff.json`, `t/scenarios/B02/approx-remote-shell-command-contract.json` |
| B03 | approximation | 2 | 0 | `t/scenarios/B01/shell-caller-handoff.json`, `t/scenarios/B03/approx-remote-copy-output-is-clean.json` |
| B04 | approximation, manual | 1 | 1 | `t/scenarios/B01/shell-caller-handoff.json`, `t/scenarios/B04/manual.md` |
| B05 | approximation, manual | 1 | 1 | `t/scenarios/B01/shell-caller-handoff.json`, `t/scenarios/B05/manual.md` |
| B06 | approximation | 2 | 0 | `t/scenarios/B01/shell-caller-handoff.json`, `t/scenarios/B06/approx-shell-c-command-contract.json` |
| B07 | approximation, manual | 1 | 1 | `t/scenarios/B07/interactive-callers.json`, `t/scenarios/B07/manual.md` |
| B08 | approximation, manual | 1 | 1 | `t/scenarios/B07/interactive-callers.json`, `t/scenarios/B08/manual.md` |
| B09 | direct | 3 | 0 | `t/scenarios/B09/command-stdio-and-status.json`, `t/scenarios/B09/empty-shell-command.json`, `t/scenarios/B09/shell-command-argv.json` |
| B10 | direct, manual | 1 | 1 | `t/scenarios/B10/login-command-environment.json`, `t/scenarios/B10/manual.md` |
| C01 | direct | 4 | 0 | `t/scenarios/C01/batch-command.json`, `t/scenarios/C01/batch-script.json`, `t/scenarios/C01/batch-stdin.json`, `t/scenarios/C01/pty-paste.json` |
| C02 | direct | 1 | 0 | `t/scenarios/C02/quoted-unicode-arguments.json` |
| C03 | direct | 1 | 0 | `t/scenarios/C03/path-search-and-absolute-path.json` |
| C04 | direct | 1 | 0 | `t/scenarios/C04/missing-command-suggestion-and-status.json` |
| C05 | direct | 1 | 0 | `t/scenarios/C05/last-exit-status-is-visible.json` |
| C06 | direct | 2 | 0 | `t/scenarios/C06/pipeline-streams-all-stages.json`, `t/scenarios/C06/builtin-reads-stdin.json` |
| C07 | direct | 1 | 0 | `t/scenarios/C07/redirection-family.json` |
| C08 | direct | 1 | 0 | `t/scenarios/C08/here-doc-and-here-string.json` |
| C09 | direct | 1 | 0 | `t/scenarios/C09/background-command-returns.json` |
| C10 | direct | 1 | 0 | `t/scenarios/C10/short-circuit-followed-by-sequence.json` |
| C11 | direct | 1 | 0 | `t/scenarios/C11/temporary-command-environment.json` |
| C12 | approximation | 1 | 0 | `t/scenarios/C12/approx-privileged-command-dispatch.json` |
| C13 | direct | 1 | 0 | `t/scenarios/C13/glob-patterns-and-unmatched-path.json` |
| C14 | direct | 1 | 0 | `t/scenarios/C14/tilde-and-brace-expansion.json` |
| C15 | approximation | 1 | 0 | `t/scenarios/C15/approx-captured-command-value.json` |
| C16 | approximation | 1 | 0 | `t/scenarios/C16/approx-process-substitution-input.json` |
| C17 | approximation | 1 | 0 | `t/scenarios/C17/approx-large-binary-and-invalid-utf8-output.json` |
| C18 | approximation | 1 | 0 | `t/scenarios/C18/approx-sigpipe-is-quiet.json` |
| D01 | approximation | 1 | 0 | `t/scenarios/D01/approx-editor-tty.json` |
| D02 | approximation | 1 | 0 | `t/scenarios/D02/approx-pager-tty.json` |
| D03 | approximation | 1 | 0 | `t/scenarios/D03/approx-monitor-tty.json` |
| D04 | approximation | 1 | 0 | `t/scenarios/D04/approx-remote-tty.json` |
| D05 | approximation | 1 | 0 | `t/scenarios/D05/approx-fzf-tty.json` |
| D06 | approximation | 1 | 0 | `t/scenarios/D06/approx-editor-child-tty.json` |
| D07 | approximation | 1 | 0 | `t/scenarios/D07/approx-password-tty.json` |
| D08 | approximation | 1 | 0 | `t/scenarios/D08/approx-repl-tty.json` |
| D09 | manual | 0 | 1 | `t/scenarios/D09/manual.md` |
| D10 | approximation | 1 | 0 | `t/scenarios/D10/approx-container-tty.json` |
| D11 | approximation | 1 | 0 | `t/scenarios/D11/approx-cooked-mode-after-crash.json` |
| D12 | direct | 1 | 0 | `t/scenarios/D12/ctrl-c-stops-foreground-child.json` |
| E01 | direct | 1 | 0 | `t/scenarios/E01/ctrl-z-stops-redirected-foreground-job.json` |
| E02 | direct | 1 | 0 | `t/scenarios/E02/fg-bg-and-jobs.json` |
| E03 | direct | 1 | 0 | `t/scenarios/E03/kill-percent-one.json` |
| E04 | direct | 1 | 0 | `t/scenarios/E04/disown-removes-job.json` |
| E05 | direct | 1 | 0 | `t/scenarios/E05/wait-collects-background-status.json` |
| E06 | direct | 1 | 0 | `t/scenarios/E06/completion-notification-and-removal.json` |
| E07 | direct | 1 | 0 | `t/scenarios/E07/pipeline-is-one-stopped-job.json` |
| E08 | direct | 1 | 0 | `t/scenarios/E08/ctrl-c-interrupts-whole-pipeline.json` |
| E09 | direct | 1 | 0 | `t/scenarios/E09/script-job-state-updates.json` |
| F01 | approximation | 1 | 0 | `t/scenarios/F01/approx-cooked-mode-after-crash.json` |
| F02 | manual | 0 | 1 | `t/scenarios/F02/manual.md` |
| F03 | direct, manual | 1 | 1 | `t/scenarios/F03/WP-R01-sigterm-exit-status.json`, `t/scenarios/F03/manual.md` |
| F04 | manual | 0 | 1 | `t/scenarios/F04/manual.md` |
| F05 | approximation, manual | 1 | 1 | `t/scenarios/F05/approx-terminal-title-cwd.json`, `t/scenarios/F05/manual.md` |
| F06 | approximation | 1 | 0 | `t/scenarios/F06/approx-osc-7-cwd.json` |
| F07 | approximation | 1 | 0 | `t/scenarios/F07/approx-osc-133-prompt.json` |
| F08 | approximation | 1 | 0 | `t/scenarios/F08/approx-large-bracketed-paste.json` |
| F09 | approximation, manual | 1 | 1 | `t/scenarios/F09/approx-mouse-report-default-off.json`, `t/scenarios/F09/manual.md` |
| F10 | direct | 1 | 0 | `t/scenarios/F10/unicode-grapheme-cursor-edit.json` |
| F11 | manual | 0 | 1 | `t/scenarios/F11/manual.md` |
| F12 | approximation, manual | 1 | 1 | `t/scenarios/F12/approx-term-dumb-command-line.json`, `t/scenarios/F12/manual.md` |
| F13 | manual | 0 | 1 | `t/scenarios/F13/manual.md` |
| G01 | direct, approximation | 8 | 0 | `t/scenarios/G01/case-conversion.json`, `t/scenarios/G01/char-transpose.json`, `t/scenarios/G01/word-forward-motion.json`, `t/scenarios/G01/word-motion-deletion.json`, `t/scenarios/G01/word-transpose.json`, `t/scenarios/G01/approx-emacs-case-transform.json`, `t/scenarios/G01/approx-emacs-transpose.json`, `t/scenarios/G01/approx-emacs-word-delete.json` |
| G02 | direct, approximation | 8 | 0 | `t/scenarios/G02/delete-a-word.json`, `t/scenarios/G02/delete-inner-word.json`, `t/scenarios/G02/goto-end.json`, `t/scenarios/G02/insert-command-cursor-shape.json`, `t/scenarios/G02/runtime-vi-toggle.json`, `t/scenarios/G02/undo-find-replace-repeat.json`, `t/scenarios/G02/yank-put-inner-word.json`, `t/scenarios/G02/approx-vi-mode-editing.json` |
| G03 | direct, manual | 1 | 1 | `t/scenarios/G03/undo-redo.json`, `t/scenarios/G03/manual.md` |
| G04 | direct, approximation, manual | 2 | 1 | `t/scenarios/G04/kill-ring-yank-pop.json`, `t/scenarios/G04/approx-kill-ring-yank.json`, `t/scenarios/G04/manual.md` |
| G05 | approximation | 1 | 0 | `t/scenarios/G05/approx-multiline-buffer-navigation.json` |
| G06 | manual | 0 | 1 | `t/scenarios/G06/manual.md` |
| G07 | manual | 0 | 1 | `t/scenarios/G07/manual.md` |
| G08 | manual | 0 | 1 | `t/scenarios/G08/manual.md` |
| G09 | approximation | 1 | 0 | `t/scenarios/G09/approx-balanced-parentheses-before-enter.json` |
| G10 | approximation, manual | 1 | 1 | `t/scenarios/G10/external-editor.json`, `t/scenarios/G10/manual.md` |
| G11 | direct | 2 | 0 | `t/scenarios/G11/clear-screen.json`, `t/scenarios/G11/clear-screen-keeps-prompt.json` |
| G12 | direct, approximation | 2 | 0 | `t/scenarios/G12/grapheme-boundary.json`, `t/scenarios/G12/approx-grapheme-cursor-boundary.json` |
| G13 | direct | 2 | 0 | `t/scenarios/G13/ctrl-y-yank.json`, `t/scenarios/G13/ctrl-y-yanks-killed-text.json` |
| G14 | manual | 0 | 1 | `t/scenarios/G14/manual.md` |
| H01 | direct | 1 | 0 | `t/scenarios/H01/history-persists-after-exit.json` |
| H02 | approximation | 1 | 0 | `t/scenarios/H02/approx-seeded-session-history.json` |
| H03 | direct | 1 | 0 | `t/scenarios/H03/duplicate-entry-suppression.json` |
| H04 | direct | 1 | 0 | `t/scenarios/H04/leading-space-is-not-saved.json` |
| H05 | manual | 0 | 1 | `t/scenarios/H05/manual.md` |
| H06 | direct | 1 | 0 | `t/scenarios/H06/multiline-reverse-search.json` |
| H07 | approximation | 1 | 0 | `t/scenarios/H07/approx-history-cwd-and-exit-filters.json` |
| H08 | direct | 1 | 0 | `t/scenarios/H08/delete-history-entry.json` |
| H09 | direct | 1 | 0 | `t/scenarios/H09/up-arrow-prefix-search.json` |
| H10 | direct | 1 | 0 | `t/scenarios/H10/token-history-search.json` |
| H11 | direct | 1 | 0 | `t/scenarios/H11/last-argument-insertion.json` |
| H12 | direct | 1 | 0 | `t/scenarios/H12/history-expansion.json` |
| H13 | direct | 1 | 0 | `t/scenarios/H13/malformed-history-recovers.json` |
| H14 | approximation | 1 | 0 | `t/scenarios/H14/approx-history-timestamp-metadata.json` |
| H15 | direct | 1 | 0 | `t/scenarios/H15/history-uses-xdg-state-home.json` |
| I01 | direct | 1 | 0 | `t/scenarios/I01/history-autosuggestion.json` |
| I02 | direct | 1 | 0 | `t/scenarios/I02/completion-autosuggestion.json` |
| I03 | direct | 1 | 0 | `t/scenarios/I03/partial-word-suggestion-acceptance.json` |
| I04 | direct | 1 | 0 | `t/scenarios/I04/multiline-history-suggestion.json` |
| I05 | direct | 1 | 0 | `t/scenarios/I05/cwd-ranked-history-suggestion.json` |
| I06 | direct | 3 | 0 | `t/scenarios/I06/enter-does-not-accept-suggestion.json`, `t/scenarios/I06/enter-typed-text-only.json`, `t/scenarios/I06/paste-enter-typed-text-only.json` |
| I07 | direct | 1 | 0 | `t/scenarios/I07/suggestion-keystrokes-remain-responsive.json` |
| J01 | direct | 1 | 0 | `t/scenarios/J01/command-name.json` |
| J02 | direct | 1 | 0 | `t/scenarios/J02/filename-variants.json` |
| J03 | direct | 1 | 0 | `t/scenarios/J03/cd-and-cdpath.json` |
| J04 | direct | 1 | 0 | `t/scenarios/J04/home-and-variable-path.json` |
| J05 | direct | 1 | 0 | `t/scenarios/J05/option-name-and-description.json` |
| J06 | direct | 1 | 0 | `t/scenarios/J06/catalog-subcommands.json` |
| J07 | direct | 1 | 0 | `t/scenarios/J07/ssh-hostname.json` |
| J08 | direct | 1 | 0 | `t/scenarios/J08/make-target.json` |
| J09 | approximation | 1 | 0 | `t/scenarios/J09/approx-kill-completion.json` |
| J10 | direct | 1 | 0 | `t/scenarios/J10/environment-variable-name.json` |
| J11 | direct | 1 | 0 | `t/scenarios/J11/wrapper-command-completion.json` |
| J12 | direct | 1 | 0 | `t/scenarios/J12/twenty-thousand-entry-directory.json` |
| J13 | approximation | 1 | 0 | `t/scenarios/J13/approx-completion-pager.json` |
| J14 | direct | 1 | 0 | `t/scenarios/J14/case-and-fuzzy-match.json` |
| J15 | direct | 1 | 0 | `t/scenarios/J15/sexp-context.json` |
| J16 | approximation | 1 | 0 | `t/scenarios/J16/approx-user-defined-completion.json` |
| J17 | approximation | 1 | 0 | `t/scenarios/J17/approx-unknown-command-learning-responsiveness.json` |
| J18 | approximation | 1 | 0 | `t/scenarios/J18/approx-completion-candidate-preview.json` |
| K01 | direct | 1 | 0 | `t/scenarios/K01/command-existence-colors.json` |
| K02 | direct | 1 | 0 | `t/scenarios/K02/existing-path-is-underlined.json` |
| K03 | direct | 1 | 0 | `t/scenarios/K03/redirection-target-is-not-an-error.json` |
| K04 | direct | 1 | 0 | `t/scenarios/K04/unbalanced-parenthesis-diagnostic.json` |
| K05 | direct | 1 | 0 | `t/scenarios/K05/string-highlighting.json` |
| K06 | direct | 1 | 0 | `t/scenarios/K06/sexp-and-command-island-evaluation.json` |
| K07 | direct | 1 | 0 | `t/scenarios/K07/one-line-source-diagnostic.json` |
| K08 | direct | 1 | 0 | `t/scenarios/K08/macro-expansion-error-location.json` |
| L01 | direct | 1 | 0 | `t/scenarios/L01/left-and-right-prompt.json` |
| L02 | manual | 0 | 1 | `t/scenarios/L02/manual.md` |
| L03 | direct | 1 | 0 | `t/scenarios/L03/status-duration-jobs-prompt-segments.json` |
| L04 | approximation | 1 | 0 | `t/scenarios/L04/approx-transient-prompt-keeps-current-prompt.json` |
| L05 | approximation | 1 | 0 | `t/scenarios/L05/approx-custom-prompt-format.json` |
| L06 | approximation | 1 | 0 | `t/scenarios/L06/approx-narrow-terminal-redraw.json` |
| L07 | direct | 1 | 0 | `t/scenarios/L07/theme-can-be-selected.json` |
| M01 | direct | 1 | 0 | `t/scenarios/M01/cd-dash.json` |
| M02 | direct | 1 | 0 | `t/scenarios/M02/logical-pwd-and-pwd-variable.json` |
| M03 | direct | 1 | 0 | `t/scenarios/M03/directory-history-prevd-nextd.json` |
| M04 | manual | 0 | 1 | `t/scenarios/M04/manual.md` |
| M05 | direct | 1 | 0 | `t/scenarios/M05/pushd-popd-stack-round-trip.json` |
| M06 | direct | 1 | 0 | `t/scenarios/M06/shell-continues-after-current-directory-is-removed.json` |
| N01 | direct | 1 | 0 | `t/scenarios/N01/session-variable.json` |
| N02 | direct | 1 | 0 | `t/scenarios/N02/export-reaches-child-process.json` |
| N03 | direct | 1 | 0 | `t/scenarios/N03/colon-separated-path-list.json` |
| N04 | direct | 1 | 0 | `t/scenarios/N04/unset-removes-variable.json` |
| N05 | approximation | 1 | 0 | `t/scenarios/N05/approx-lexical-let-scope.json` |
| N06 | manual | 0 | 1 | `t/scenarios/N06/manual.md` |
| N07 | direct | 1 | 0 | `t/scenarios/N07/status-and-pipeline-status.json` |
| O01 | direct | 1 | 0 | `t/scenarios/O01/O01-bare-line-sugar.json` |
| O02 | direct | 1 | 0 | `t/scenarios/O02/O02-command-island-evaluation.json` |
| O03 | direct | 1 | 0 | `t/scenarios/O03/O03-let-and-set.json` |
| O04 | direct | 1 | 0 | `t/scenarios/O04/O04-control-forms.json` |
| O05 | direct | 1 | 0 | `t/scenarios/O05/O05-nested-command-definitions.json` |
| O06 | direct | 1 | 0 | `t/scenarios/O06/O06-macro-expansion.json` |
| O07 | direct | 2 | 0 | `t/scenarios/O07/O07-conditional-and-handler-case.json`, `t/scenarios/O07/O07-interactive-command-failed-restart.json` |
| O08 | direct | 1 | 0 | `t/scenarios/O08/O08-structured-pipeline.json` |
| O09 | direct | 1 | 0 | `t/scenarios/O09/O09-json-tsv-lines-conversion.json` |
| O10 | direct | 1 | 0 | `t/scenarios/O10/O10-regex-and-string-library.json` |
| O11 | direct | 1 | 0 | `t/scenarios/O11/O11-native-arithmetic.json` |
| O12 | direct | 1 | 0 | `t/scenarios/O12/O12-comments.json` |
| O13 | approximation | 1 | 0 | `t/scenarios/O13/approx-O13-script-shebang-and-source.json` |
| O14 | direct | 1 | 0 | `t/scenarios/O14/O14-function-directory-autoload.json` |
| O15 | direct | 1 | 0 | `t/scenarios/O15/O15-asdf-library-load.json` |
| O16 | direct | 1 | 0 | `t/scenarios/O16/O16-preserve-case.json` |
| O17 | direct | 1 | 0 | `t/scenarios/O17/O17-force-external-command.json` |
| O18 | direct | 1 | 0 | `t/scenarios/O18/O18-alias-eval-and-string-execution.json` |
| P01 | approximation | 1 | 0 | `t/scenarios/P01/approx-P01-xdg-init-file.json` |
| P02 | approximation | 1 | 0 | `t/scenarios/P02/approx-P02-conf-d-order.json` |
| P03 | approximation | 1 | 0 | `t/scenarios/P03/approx-P03-function-directory.json` |
| P04 | approximation | 1 | 0 | `t/scenarios/P04/approx-P04-abbreviation-expansion.json` |
| P05 | direct | 1 | 0 | `t/scenarios/P05/P05-alias-expansion.json` |
| P06 | direct | 1 | 0 | `t/scenarios/P06/P06-key-binding.json` |
| P07 | direct | 1 | 0 | `t/scenarios/P07/P07-theme-selection.json` |
| P08 | approximation | 1 | 0 | `t/scenarios/P08/approx-P08-prompt-format.json` |
| P09 | manual | 0 | 1 | `t/scenarios/P09/manual.md` |
| P10 | direct | 1 | 0 | `t/scenarios/P10/P10-completion-definition.json` |
| P11 | approximation | 1 | 0 | `t/scenarios/P11/approx-P11-continue-after-config-error.json` |
| P12 | manual | 0 | 1 | `t/scenarios/P12/manual.md` |
| Q01 | direct | 1 | 0 | `t/scenarios/Q01/Q01-no-debug-dump.json` |
| Q02 | direct | 1 | 0 | `t/scenarios/Q02/Q02-bounded-recursion-recovery.json` |
| Q03 | manual | 0 | 1 | `t/scenarios/Q03/manual.md` |
| Q04 | direct | 1 | 0 | `t/scenarios/Q04/Q04-cancel-completion.json` |
| Q05 | manual | 0 | 1 | `t/scenarios/Q05/manual.md` |
| Q06 | approximation | 1 | 0 | `t/scenarios/Q06/approx-Q06-read-only-home-session.json` |
| Q07 | manual | 0 | 1 | `t/scenarios/Q07/manual.md` |
| Q08 | manual | 0 | 1 | `t/scenarios/Q08/manual.md` |
| S01 | approximation | 1 | 0 | `t/scenarios/S01/approx-S01-ask-mode-cancel.json` |
| S02 | manual | 0 | 1 | `t/scenarios/S02/manual.md` |
| S03 | manual | 0 | 1 | `t/scenarios/S03/manual.md` |
| S04 | manual | 0 | 1 | `t/scenarios/S04/manual.md` |
| S05 | direct | 1 | 0 | `t/scenarios/S05/S05-noninteractive-ai-status.json` |
| S06 | manual | 0 | 1 | `t/scenarios/S06/manual.md` |
| S07 | approximation | 1 | 0 | `t/scenarios/S07/approx-S07-shell-without-claude.json` |
| T01 | manual | 0 | 1 | `t/scenarios/T01/manual.md` |
| T02 | manual | 0 | 1 | `t/scenarios/T02/manual.md` |
| T03 | approximation | 1 | 0 | `t/scenarios/T03/approx-T03-help-output.json` |
| T04 | manual | 0 | 1 | `t/scenarios/T04/manual.md` |
| T05 | approximation | 1 | 0 | `t/scenarios/T05/approx-T05-legacy-history-load.json` |
| T06 | manual | 0 | 1 | `t/scenarios/T06/manual.md` |
| U01 | manual | 0 | 1 | `t/scenarios/U01/manual.md` |
| U02 | approximation | 1 | 0 | `t/scenarios/U02/approx-U02-osc-133-markers.json` |
| U03 | approximation | 1 | 0 | `t/scenarios/U03/approx-U03-tmux-screen-terminal.json` |
| Total | expected corpus | 197 | 48 | — |
