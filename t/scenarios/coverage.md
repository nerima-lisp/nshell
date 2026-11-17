# Use-case coverage

This index maps use-case (UC) IDs from the run requirements catalog, supplied
with the orchestration materials, to scenario files.
Shared scenarios can appear on multiple UC rows and may be stored under a different
UC's directory. A05 uses A04's login-path handoff scenario, and B02–B06 use
B01's shell-caller handoff scenario. The Total row counts unique manifest
entries as executable scenarios; that count matches the runner summary's
`selected` count in an unfiltered `--mode all` run. Its manual-check count is
the sum of the per-UC manual-check counts. See the [scenario format](README.md)
for how each JSON scenario is structured.

Coverage labels describe evidence for each UC; they are per-UC assessments,
not properties of filenames. A direct JSON scenario exercises the stated
behavior and asserts a result; an approximation covers related behavior
without claiming the full contract. A shared scenario can be direct for one UC
and an approximation for another, so a UC row may say approximation even when
its listed filename lacks the `approx-` prefix. A filename prefixed with
`approx-` marks a scenario that explicitly advertises approximation. A
`manual.md` file records a check requiring a person; some UCs have both
executable scenarios and manual checks.

| UC | Coverage | Executable scenarios | Manual checks | Scenario files |
| --- | --- | ---: | ---: | --- |
| A01 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| A02 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| A03 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/A03/manual.md` |
| A04 | direct, manual | 1 | 1 | `t/scenarios/A04/login-path-handoff.json`, `t/scenarios/A04/manual.md` |
| A05 | direct, manual | 1 | 1 | `t/scenarios/A04/login-path-handoff.json`, `t/scenarios/A05/manual.md` |
| A06 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/A06/manual.md` |
| A07 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/A07/manual.md` |
| A08 | direct | 2 | 0 | `t/scenarios/A08/ctrl-d-exits.json`, `t/scenarios/A08/exit-warns-about-job.json` |
| A09 | approximation, manual | 1 | 1 | `t/scenarios/A09/WP-R01-hup-forwards-to-job.json`, `t/scenarios/A09/manual.md` |
| A10 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| A11 | direct, manual | 1 | 1 | `t/scenarios/A11/nested-nshell-session.json`, `t/scenarios/A11/manual.md` |
| A12 | direct | 1 | 0 | `t/scenarios/A12/no-config-skips-startup.json` |
| A13 | direct | 1 | 0 | `t/scenarios/A13/config-error-keeps-prompt.json` |
| B01 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/B01/manual.md` |
| B02 | approximation | 1 | 0 | `t/scenarios/B02/approx-remote-shell-command-contract.json` |
| B03 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| B04 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/B04/manual.md` |
| B05 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/B05/manual.md` |
| B06 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| B07 | approximation, manual | 1 | 1 | `t/scenarios/B07/interactive-callers.json`, `t/scenarios/B07/manual.md` |
| B08 | approximation, manual | 1 | 1 | `t/scenarios/B07/interactive-callers.json`, `t/scenarios/B08/manual.md` |
| B09 | direct | 1 | 0 | `t/scenarios/B09/pty-command-uses-nshell-builtins.json` |
| B10 | direct, manual | 1 | 1 | `t/scenarios/B10/login-command-environment.json`, `t/scenarios/B10/manual.md` |
| C01 | direct | 1 | 0 | `t/scenarios/C01/pty-paste.json` |
| C02 | direct | 1 | 0 | `t/scenarios/C02/quoted-unicode-arguments.json` |
| C03 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C04 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C05 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C06 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C07 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C08 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C09 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C10 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C11 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C12 | approximation | 1 | 0 | `t/scenarios/C12/approx-privileged-command-dispatch.json` |
| C13 | direct | 1 | 0 | `t/scenarios/C13/glob-patterns-and-unmatched-path.json` |
| C14 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C15 | approximation | 1 | 0 | `t/scenarios/C15/approx-captured-command-value.json` |
| C16 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C17 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| C18 | approximation | 1 | 0 | `t/scenarios/C18/approx-sigpipe-is-quiet.json` |
| D01 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D02 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D03 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D04 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D05 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D06 | approximation | 1 | 0 | `t/scenarios/D06/approx-editor-child-tty.json` |
| D07 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D08 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D09 | direct, manual | 1 | 1 | `t/scenarios/D09/tmux-attach-session.json`, `t/scenarios/D09/manual.md` |
| D10 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| D11 | approximation | 1 | 0 | `t/scenarios/D11/approx-cooked-mode-after-crash.json` |
| D12 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| E01 | direct | 1 | 0 | `t/scenarios/E01/ctrl-z-stops-redirected-foreground-job.json` |
| E02 | direct | 1 | 0 | `t/scenarios/E02/T3-fg-resumes-stopped-descendant.json` |
| E03 | direct | 1 | 0 | `t/scenarios/E03/kill-percent-one.json` |
| E04 | direct | 1 | 0 | `t/scenarios/E04/disown-removes-job.json` |
| E05 | direct | 1 | 0 | `t/scenarios/E05/wait-collects-background-status.json` |
| E06 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| E07 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| E08 | direct | 1 | 0 | `t/scenarios/E08/ctrl-c-interrupts-whole-pipeline.json` |
| E09 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| F01 | direct | 1 | 0 | `t/scenarios/F01/foreground-child-restores-terminal-output.json` |
| F02 | manual | 0 | 1 | `t/scenarios/F02/manual.md` |
| F03 | direct, manual | 1 | 1 | `t/scenarios/F03/WP-R01-sigterm-exit-status.json`, `t/scenarios/F03/manual.md` |
| F04 | direct, manual | 1 | 1 | `t/scenarios/F04/ctrl-quit-stops-cat-and-shell-recovers.json`, `t/scenarios/F04/manual.md` |
| F05 | approximation, manual | 1 | 1 | `t/scenarios/F05/approx-terminal-title-cwd.json`, `t/scenarios/F05/manual.md` |
| F06 | approximation | 1 | 0 | `t/scenarios/F06/approx-osc-7-cwd.json` |
| F07 | approximation | 1 | 0 | `t/scenarios/F07/approx-osc-133-prompt.json` |
| F08 | approximation | 1 | 0 | `t/scenarios/F08/approx-large-bracketed-paste.json` |
| F09 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/F09/manual.md` |
| F10 | direct | 1 | 0 | `t/scenarios/F10/unicode-grapheme-cursor-edit.json` |
| F11 | direct, manual | 4 | 1 | `t/scenarios/F11/16-color-sgr.json`, `t/scenarios/F11/256-color-sgr.json`, `t/scenarios/F11/no-color-sgr.json`, `t/scenarios/F11/truecolor-sgr.json`, `t/scenarios/F11/manual.md` |
| F12 | approximation, manual | 1 | 1 | `t/scenarios/F12/approx-term-dumb-command-line.json`, `t/scenarios/F12/manual.md` |
| F13 | direct, manual | 1 | 1 | `t/scenarios/F13/startup-cursor-report-is-consumed.json`, `t/scenarios/F13/manual.md` |
| G01 | direct, approximation | 8 | 0 | `t/scenarios/G01/case-conversion.json`, `t/scenarios/G01/char-transpose.json`, `t/scenarios/G01/word-forward-motion.json`, `t/scenarios/G01/word-motion-deletion.json`, `t/scenarios/G01/word-transpose.json`, `t/scenarios/G01/approx-emacs-case-transform.json`, `t/scenarios/G01/approx-emacs-transpose.json`, `t/scenarios/G01/approx-emacs-word-delete.json` |
| G02 | direct, approximation | 10 | 0 | `t/scenarios/G02/delete-a-word.json`, `t/scenarios/G02/delete-inner-word.json`, `t/scenarios/G02/goto-end.json`, `t/scenarios/G02/insert-command-cursor-shape.json`, `t/scenarios/G02/runtime-vi-toggle.json`, `t/scenarios/G02/undo-find-replace-repeat.json`, `t/scenarios/G02/yank-put-inner-word.json`, `t/scenarios/G02/approx-vi-mode-editing.json`, `t/scenarios/G02/vi-e-nfd-grapheme-boundary.json`, `t/scenarios/G02/vi-insert-escape-e-same-write.json` |
| G03 | direct, manual | 1 | 1 | `t/scenarios/G03/undo-redo.json`, `t/scenarios/G03/manual.md` |
| G04 | direct, approximation, manual | 2 | 1 | `t/scenarios/G04/kill-ring-yank-pop.json`, `t/scenarios/G04/approx-kill-ring-yank.json`, `t/scenarios/G04/manual.md` |
| G05 | approximation | 1 | 0 | `t/scenarios/G05/approx-multiline-buffer-navigation.json` |
| G06 | direct, manual | 1 | 1 | `t/scenarios/G06/nested-matching-delimiters.json`, `t/scenarios/G06/manual.md` |
| G07 | direct, manual | 2 | 1 | `t/scenarios/G07/nested-continuation-indentation-and-single-execution.json`, `t/scenarios/G07/blank-continuation-line-keeps-shell-alive.json`, `t/scenarios/G07/manual.md` |
| G08 | direct, manual | 1 | 1 | `t/scenarios/G08/structural-editing.json`, `t/scenarios/G08/manual.md` |
| G09 | approximation | 1 | 0 | `t/scenarios/G09/approx-balanced-parentheses-before-enter.json` |
| G10 | approximation, manual | 1 | 1 | `t/scenarios/G10/external-editor.json`, `t/scenarios/G10/manual.md` |
| G11 | direct | 2 | 0 | `t/scenarios/G11/clear-screen.json`, `t/scenarios/G11/clear-screen-keeps-prompt.json` |
| G12 | direct, approximation | 3 | 0 | `t/scenarios/G12/grapheme-boundary.json`, `t/scenarios/G12/approx-grapheme-cursor-boundary.json`, `t/scenarios/G02/vi-e-nfd-grapheme-boundary.json` |
| G13 | direct | 2 | 0 | `t/scenarios/G13/ctrl-y-yank.json`, `t/scenarios/G13/ctrl-y-yanks-killed-text.json` |
| G14 | manual | 0 | 1 | `t/scenarios/G14/manual.md` |
| H01 | direct | 1 | 0 | `t/scenarios/H01/history-persists-after-exit.json` |
| H02 | direct, approximation | 2 | 0 | `t/scenarios/H02/live-history-shared-between-sessions.json`, `t/scenarios/H02/approx-seeded-session-history.json` |
| H03 | direct | 1 | 0 | `t/scenarios/H03/duplicate-entry-suppression.json` |
| H04 | direct | 1 | 0 | `t/scenarios/H04/leading-space-is-not-saved.json` |
| H05 | direct | 1 | 1 | `t/scenarios/H05/private-mode-does-not-save-history.json`, `t/scenarios/H05/manual.md` |
| H06 | direct | 1 | 0 | `t/scenarios/H06/multiline-reverse-search.json` |
| H07 | approximation | 1 | 0 | `t/scenarios/H07/approx-history-cwd-and-exit-filters.json` |
| H08 | direct | 1 | 0 | `t/scenarios/H08/delete-history-entry.json` |
| H09 | direct | 1 | 0 | `t/scenarios/H09/up-arrow-prefix-search.json` |
| H10 | direct | 1 | 0 | `t/scenarios/H10/token-history-search.json` |
| H11 | direct | 1 | 0 | `t/scenarios/H11/last-argument-insertion.json` |
| H12 | direct | 1 | 0 | `t/scenarios/H12/history-expansion.json` |
| H13 | direct | 1 | 0 | `t/scenarios/H13/malformed-history-recovers.json` |
| H14 | direct, approximation | 3 | 0 | `t/scenarios/H14/history-persists-timestamp-metadata.json`, `t/scenarios/H14/history-timestamps-display-utc.json`, `t/scenarios/H14/approx-history-timestamp-metadata.json` |
| H15 | direct | 2 | 0 | `t/scenarios/H15/history-uses-xdg-data-home.json`, `t/scenarios/H15/history-ignores-xdg-state-home.json` |
| I01 | direct | 1 | 0 | `t/scenarios/I01/history-autosuggestion.json` |
| I02 | direct | 1 | 0 | `t/scenarios/I02/completion-autosuggestion.json` |
| I03 | direct | 1 | 0 | `t/scenarios/I03/partial-word-suggestion-acceptance.json` |
| I04 | direct | 1 | 0 | `t/scenarios/I04/multiline-history-suggestion.json` |
| I05 | direct | 1 | 0 | `t/scenarios/I05/cwd-ranked-history-suggestion.json` |
| I06 | direct | 3 | 0 | `t/scenarios/I06/enter-does-not-accept-suggestion.json`, `t/scenarios/I06/enter-typed-text-only.json`, `t/scenarios/I06/paste-enter-typed-text-only.json` |
| I07 | direct | 1 | 0 | `t/scenarios/I07/suggestion-keystrokes-remain-responsive.json` |
| J01 | direct | 1 | 0 | `t/scenarios/J01/command-name.json` |
| J02 | direct | 3 | 0 | `t/scenarios/J02/bare-file-completion.json`, `t/scenarios/J02/filename-insertion-pty.json`, `t/scenarios/J02/filename-variants.json` |
| J03 | direct | 1 | 0 | `t/scenarios/J03/cd-and-cdpath.json` |
| J04 | direct | 1 | 0 | `t/scenarios/J04/home-and-variable-path.json` |
| J05 | direct | 1 | 0 | `t/scenarios/J05/option-name-and-description.json` |
| J06 | direct | 1 | 0 | `t/scenarios/J06/catalog-subcommands.json` |
| J07 | direct | 1 | 0 | `t/scenarios/J07/ssh-hostname.json` |
| J08 | direct | 1 | 0 | `t/scenarios/J08/make-target.json` |
| J09 | approximation | 1 | 0 | `t/scenarios/J09/approx-kill-completion.json` |
| J10 | direct | 1 | 0 | `t/scenarios/J10/environment-variable-name.json` |
| J11 | direct | 1 | 0 | `t/scenarios/J11/wrapper-command-completion.json` |
| J12 | direct | 2 | 0 | `t/scenarios/J12/twenty-thousand-entry-directory.json`, `t/scenarios/J12/large-directory-completion.json` |
| J13 | direct | 1 | 0 | `t/scenarios/J13/completion-pager.json` |
| J14 | direct | 2 | 0 | `t/scenarios/J14/case-and-fuzzy-match.json`, `t/scenarios/J14/fuzzy-match-insertion-pty.json` |
| J15 | direct | 1 | 0 | `t/scenarios/J15/sexp-context.json` |
| J16 | approximation | 1 | 0 | `t/scenarios/J16/approx-user-defined-completion.json` |
| J17 | approximation | 2 | 0 | `t/scenarios/J17/approx-unknown-command-learning-responsiveness.json`, `t/scenarios/J17/ctrl-c-immediate-next-command.json` |
| J18 | approximation | 1 | 0 | `t/scenarios/J18/approx-completion-candidate-preview.json` |
| K01 | direct | 1 | 0 | `t/scenarios/K01/command-existence-colors.json` |
| K02 | direct | 1 | 0 | `t/scenarios/K02/existing-path-is-underlined.json` |
| K03 | direct | 1 | 0 | `t/scenarios/K03/redirection-target-is-not-an-error.json` |
| K04 | direct | 1 | 0 | `t/scenarios/K04/unbalanced-parenthesis-diagnostic.json` |
| K05 | direct | 1 | 0 | `t/scenarios/K05/string-highlighting.json` |
| K06 | direct | 1 | 0 | `t/scenarios/K06/sexp-and-command-island-evaluation.json` |
| K07 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| K08 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| L01 | direct | 1 | 0 | `t/scenarios/L01/left-and-right-prompt.json` |
| L02 | direct, manual | 2 | 1 | `t/scenarios/L02/git-prompt-responsiveness.json`, `t/scenarios/L02/slow-git-status-does-not-block-input.json`, `t/scenarios/L02/manual.md` |
| L03 | direct | 1 | 0 | `t/scenarios/L03/status-duration-jobs-prompt-segments.json` |
| L04 | approximation | 1 | 0 | `t/scenarios/L04/approx-transient-prompt-keeps-current-prompt.json` |
| L05 | approximation | 1 | 0 | `t/scenarios/L05/approx-custom-prompt-format.json` |
| L06 | approximation | 1 | 0 | `t/scenarios/L06/approx-narrow-terminal-redraw.json` |
| L07 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| M01 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| M02 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| M03 | removed (prevd/nextd deleted in P2-6) | 0 | 0 | — |
| M04 | manual | 0 | 1 | `t/scenarios/M04/manual.md` |
| M05 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| M06 | direct | 1 | 0 | `t/scenarios/M06/shell-continues-after-current-directory-is-removed.json` |
| N01 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| N02 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| N03 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| N04 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| N05 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| N06 | manual | 0 | 1 | `t/scenarios/N06/manual.md` |
| N07 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O01 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O02 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O03 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O04 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O05 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O06 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O07 | direct | 1 | 0 | `t/scenarios/O07/O07-interactive-command-failed-restart.json` |
| O08 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O09 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O10 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O11 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O12 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O13 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O14 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O15 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O16 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O17 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| O18 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| P01 | approximation | 1 | 0 | `t/scenarios/P01/approx-P01-xdg-init-file.json` |
| P02 | approximation | 1 | 0 | `t/scenarios/P02/approx-P02-conf-d-order.json` |
| P03 | approximation | 1 | 0 | `t/scenarios/P03/approx-P03-function-directory.json` |
| P04 | approximation | 1 | 0 | `t/scenarios/P04/approx-P04-abbreviation-expansion.json` |
| P05 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| P06 | direct | 1 | 0 | `t/scenarios/P06/P06-key-binding.json` |
| P07 | direct | 1 | 0 | `t/scenarios/P07/P07-theme-selection.json` |
| P08 | approximation | 1 | 0 | `t/scenarios/P08/approx-P08-prompt-format.json` |
| P09 | direct, manual | 1 | 1 | `t/scenarios/P09/hooks-order-arguments-and-error-recovery.json`, `t/scenarios/P09/manual.md` |
| P10 | direct | 1 | 0 | `t/scenarios/P10/P10-completion-definition.json` |
| P11 | approximation | 1 | 0 | `t/scenarios/P11/approx-P11-continue-after-config-error.json` |
| P12 | direct, manual | 1 | 1 | `t/scenarios/P12/public-api-stability.json`, `t/scenarios/P12/manual.md` |
| Q01 | direct | 1 | 0 | `t/scenarios/Q01/Q01-no-debug-dump.json` |
| Q02 | direct | 1 | 0 | `t/scenarios/Q02/Q02-bounded-recursion-recovery.json` |
| Q03 | direct, manual | 1 | 1 | `t/scenarios/Q03/Q03-real-heap-exhaustion.json`, `t/scenarios/Q03/manual.md` |
| Q04 | direct | 1 | 0 | `t/scenarios/Q04/Q04-cancel-completion.json` |
| Q05 | direct | 1 | 0 | `t/scenarios/Q05/git-probe-timeout-does-not-block-input.json` |
| Q06 | approximation | 1 | 0 | `t/scenarios/Q06/approx-Q06-read-only-home-session.json` |
| Q07 | direct, manual | 1 | 1 | `t/scenarios/Q07/history-write-failure-on-bounded-filesystem.json`, `t/scenarios/Q07/manual.md` |
| Q08 | direct, manual | 2 | 1 | `t/scenarios/Q08/fault-injected-key-handler-preserves-input.json`, `t/scenarios/Q08/normal-key-handler-remains-usable.json`, `t/scenarios/Q08/manual.md` |
| S01 | approximation | 1 | 0 | `t/scenarios/S01/approx-S01-ask-mode-cancel.json` |
| S02 | direct, manual | 2 | 1 | `t/scenarios/S02/S02-enter-approves-proposal.json`, `t/scenarios/S02/S02-proposal-awaits-approval.json`, `t/scenarios/S02/manual.md` |
| S03 | direct, manual | 1 | 1 | `t/scenarios/S03/S03-explains-last-failure.json`, `t/scenarios/S03/manual.md` |
| S04 | direct, manual | 1 | 1 | `t/scenarios/S04/S04-approves-agent-steps-individually.json`, `t/scenarios/S04/manual.md` |
| S05 | direct | 1 | 0 | `t/scenarios/S05/S05-noninteractive-ai-status.json` |
| S06 | direct, manual | 1 | 1 | `t/scenarios/S06/S06-classifies-and-gates-sexp-proposals.json`, `t/scenarios/S06/manual.md` |
| S07 | approximation | 2 | 0 | `t/scenarios/S07/approx-S07-shell-without-claude.json`, `t/scenarios/S07/cancel-resumes-after-new-request.json` |
| T01 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/T01/manual.md` |
| T02 | removed in P2-6 (checked by tests), manual | 0 | 1 | `t/scenarios/T02/manual.md` |
| T03 | removed in P2-6 (checked by tests) | 0 | 0 | — |
| T04 | manual | 0 | 1 | `t/scenarios/T04/manual.md` |
| T05 | direct, approximation | 2 | 0 | `t/scenarios/T05/legacy-history-import-is-idempotent.json`, `t/scenarios/T05/approx-T05-legacy-history-load.json` |
| T06 | direct, manual | 1 | 1 | `t/scenarios/T06/copied-release-bundle-pty-smoke.json`, `t/scenarios/T06/manual.md` |
| U01 | manual | 0 | 1 | `t/scenarios/U01/manual.md` |
| U02 | removed in P2-6 (checked by the F07 scenario) | 0 | 0 | — |
| U03 | approximation | 1 | 0 | `t/scenarios/U03/approx-U03-tmux-screen-terminal.json` |
| Total | expected corpus | 178 | 47 | — |
