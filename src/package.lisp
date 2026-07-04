;;; nshell package definitions
;;; DDD architecture: domain/ must not import from application/, infrastructure/, or presentation/

(eval-when (:compile-toplevel :load-toplevel :execute)
;; -- Main package ------------------------------------------
(defpackage #:nshell
  (:use #:cl)
  (:export #:main))

;; -- Domain packages (pure, no side effects) ----------------
(defpackage #:nshell.domain.events
  (:use #:cl)
  (:export #:domain-event #:domain-event-p #:domain-event-type #:domain-event-timestamp
           #:make-generic-domain-event
           #:make-command-entered-event #:make-command-parsed-event
           #:make-parse-failed-event #:make-pipeline-started-event
           #:make-process-created-event #:make-process-exited-event
           #:make-pipeline-completed-event #:make-job-created-event
           #:make-job-stopped-event #:make-job-continued-event
           #:make-job-completed-event #:make-signal-caught-event
           #:make-command-appended-to-history-event #:make-history-searched-event
           #:make-completion-triggered-event))

(defpackage #:nshell.domain.signals
  (:use #:cl)
  (:export #:make-signal #:signal-name #:signal-number #:signal-p #:signal=
           #:+sigint+ #:+sigterm+ #:+sigtstp+ #:+sigcont+ #:+sigchld+))

(defpackage #:nshell.domain.input
  (:use #:cl)
  (:export #:key-event #:key-event-p #:make-key-event
           #:key-event-type #:key-event-char #:key-event-number
           #:key-event-data))

(defpackage #:nshell.domain.abbreviation
  (:use #:cl)
  (:export #:abbreviation-boundary-p
           #:abbreviation-target-before-cursor
           #:abbreviation-command-position-p
           #:abbreviation-p
           #:make-abbreviation
           #:abbreviation-expansion
           #:abbreviation-position
           #:expand-abbreviation))

(defpackage #:nshell.domain.execution
  (:use #:cl)
  (:export #:make-command #:command-name #:command-args
            #:make-pipeline #:pipeline-p #:pipeline-commands
            #:make-pipeline-plan #:pipeline-plan-p #:pipeline-plan-stages
            #:pipeline-stage #:pipeline-stage-p #:pipeline-stage-command
            #:pipeline-stage-pipe-config #:pipe-config #:pipe-config-p
            #:pipe-config-stdin #:pipe-config-stdout #:pipe-config-index
            #:pipe-config-last-p #:pipeline-stage-count
            #:make-job #:job-id #:job-state #:job-pipeline
            #:job-state-valid-p #:job-state-transition #:job-register-background-processes
            #:job-set-background-visible #:job-record-terminal-exit-code
            #:valid-process-group-id-p #:job-control-pgid #:job-command-display-string
            #:command-to-list #:pipeline-length #:pipeline-empty-p #:pipeline-single-command-p #:job-running-p #:job-stopped-p #:job-completed-p #:job-known-pids #:job-last-pid #:job-pgid #:job-exit-code #:job-state-kw #:make-job-monitor #:monitor-find-job
            #:job-pids #:job-command-line #:job-background-p))

  (defpackage #:nshell.domain.parsing
    (:use #:cl)
    (:export #:tokenize #:shell-assignment-word-p #:parse-command-line #:parse-result
           #:shell-input-blank-p
           #:shell-word-separator-p #:shell-operator-separator-p
           #:shell-token-separator-p #:shell-command-separator-token-p
           #:+redirect-specs+ #:+redirect-fd-dup-specs+
           #:tokenization-result-p
           #:tokenization-result-tokens
           #:tokenization-result-cursor-token
           #:tokenization-result-incomplete-p
           #:token-type #:token-value #:token-start #:token-end #:make-token
           #:ast-node-type #:make-command-node #:make-pipeline-node
                #:command-node-p #:pipeline-node-p #:sequence-node-p
                #:command-node-command #:command-node-command-quote-style #:command-node-args
                #:sequence-node-commands #:pipeline-node-commands
                #:sequence-node-separators
                #:command-node-arg-values #:ast-node->command-line
                #:arg-value #:arg-quote-style
             #:do-sequence-node-command-separator-pairs
             #:if-node-p #:if-node-condition #:if-node-then-branch #:if-node-else-branch
             #:for-node-p #:for-node-var-name #:for-node-in-values #:for-node-body
             #:while-node-p #:while-node-condition #:while-node-body
             #:case-node-p #:case-node-value #:case-node-clauses
             #:begin-end-node-p #:begin-end-node-body
             #:var-p #:make-var #:unify #:walk #:extend-bindings #:backtrack #:unify-p
           #:with-parsed-command-line #:with-parsed-command-line-case #:with-complete-command-line
           #:parse-complete-p #:parse-result-state #:parse-errors
           #:parse-error-messages #:format-parse-error-messages
           #:parse-result-ast #:parse-result-incomplete
            #:parse-diagnostic #:parse-diagnostic-p
            #:parse-diagnostic-kind #:parse-diagnostic-kind-p #:parse-diagnostic-message
            #:parse-diagnostic-start #:parse-diagnostic-end
            #:parse-diagnostic-token))

(defpackage #:nshell.domain.environment
  (:use #:cl)
  (:export #:env-var #:env-var-p #:make-env-var
           #:env-var-name #:env-var-value #:env-var-values #:env-var-exported-p
           #:environment #:environment-p #:make-environment
           #:environment-vars #:make-default-environment #:inject-os-environment
           #:env-get #:env-get-values #:env-set #:env-set-values
           #:env-unset #:env-export #:env-bindings #:env-list))

(defpackage #:nshell.domain.expansion
  (:use #:cl)
  (:import-from #:nshell.domain.environment #:env-get)
  (:export #:*glob-directory-files-fn* #:*glob-subdirectories-fn*
           #:glob-match-p
           #:expand-variables #:expand-tilde #:expand-glob #:expand-all
           #:expand-by-quote-style
           #:expand-command-name-fields-by-quote-style
           #:expand-command-name-by-quote-style
           #:expand-double-quoted #:expand-arithmetic #:evaluate-arithmetic
           #:expand-braces #:argv-reference-fields #:*positional-args*))

  (defpackage #:nshell.domain.completion
  (:use #:cl)
  (:export #:make-candidate #:candidate-text #:candidate-kind
            #:candidate-description #:candidate-score
            #:make-empty-knowledge-base #:kb-add-command #:kb-add-command-from-help
            #:kb-add-option
            #:kb-remove-command #:kb-query
            #:make-fact #:make-rule #:fact-p #:rule-p
            #:assert-fact! #:assert-rule! #:prove #:prove-all #:predicate-true-p
            #:+command-path-builtin-specs+
            #:+type-builtin-spec+
            #:builtin-help-entries
            #:builtin-completion-command-specs
            #:external-completion-command-specs
            #:builtin-rule-facts
            #:builtin-rule-rules
            #:rule-complete
            #:complete
            #:completion-context-for #:completion-context-command
            #:completion-context-argument-prefix
            #:completion-context-argument-words
            #:completion-context-command-position-p
            #:completion-context-redirection-target-p
            #:completion-filesystem-fns
            #:*path-command-directory-files-fn* #:*path-command-executable-p-fn*
            #:*file-completion-directory-files-fn*
            #:*file-completion-subdirectories-fn*
            #:command-candidates-from-path))

(defpackage #:nshell.domain.history
  (:use #:cl)
  (:export #:make-history-entry #:entry-text #:entry-timestamp #:entry-exit-code
           #:history-entry-texts
           #:command-history #:command-history-p #:make-command-history
           #:command-history-entries #:command-history-max-entries
           #:history-add #:history-search #:history-entry-line-prefix-suffix #:history-all
           #:history-merge #:history-dedup #:history-clear #:history-delete
           #:history-empty-p #:history-size
           #:command-line-last-argument #:history-last-argument-at
           #:history-previous #:history-next #:history-reset-navigation))

(defpackage #:nshell.domain.job-control
  (:use #:cl)
  (:export #:make-job-monitor #:monitor-add-job #:monitor-add-background-job
            #:monitor-update
            #:monitor-jobs #:monitor-entries #:monitor-find-job
            #:monitor-remove-job
            #:suspend-job #:resume-job #:foreground-job #:background-job
            #:complete-job))

(defpackage #:nshell.domain.configuration
  (:use #:cl)
  (:export #:make-theme #:theme-color #:theme-name #:theme-set-color
           #:theme-p #:config-p
           #:make-config #:config-theme #:config-prompt
           #:default-theme #:default-config))

(defpackage #:nshell.domain.prompting
  (:use #:cl)
  (:export #:make-prompt-model #:prompt-hostname #:prompt-cwd
           #:prompt-exit-code #:prompt-segment #:prompt-right-segments
           #:prompt-segments #:make-prompt-segment #:prompt-segment-text
           #:prompt-segment-kind #:*git-status-resolver*
           #:*prompt-time-resolver*
           #:render-prompt-model #:render-right-prompt-model))

;; -- Application packages -----------------------------------
(defpackage #:nshell.application
  (:use #:cl)
  (:export #:*job-monitor* #:*shell-pgid* #:*foreground-job-pgid*
            #:make-event-dispatcher #:publish-event
            #:subscribe #:unsubscribe #:drain-events
            #:make-shell-context #:shell-context-p
            #:shell-context-history #:shell-context-config
            #:shell-context-knowledge-base #:shell-context-environment
            #:shell-context-dispatcher #:shell-context-job-monitor
            #:shell-context-alias-table #:shell-context-abbreviation-table
            #:shell-context-function-table #:shell-context-function-source-table
            #:shell-context-filesystem-fns
            #:shell-context-process-fns #:shell-context-terminal-fns
            #:shell-context-signal-fns #:shell-context-redirect-fns
            #:shell-context-history-fns #:shell-context-git-fns
            #:shell-context-execution-strategy #:shell-context-running
            #:shell-context-last-exit-code #:shell-context-input-state
            #:shell-context-process-registry #:shell-context-terminal-rows
            #:shell-context-terminal-cols
            #:lookup-builtin
            #:execute-command-line #:execute-pipeline-use-case #:execute-pipeline
            #:execute-command-node-in-context
            #:execute-ast-in-context
            #:execute-external
            #:expand-command-alias-node
            #:job-listing #:job-listing-p #:make-job-listing
            #:job-listing-id #:job-listing-status #:job-listing-command
            #:format-job-listing
            #:fg #:bg #:jobs #:disown #:interrupt-foreground #:suspend-foreground
            #:history-suggestion #:search-history-use-case
            #:interactive-history-search-use-case))

;; -- Infrastructure packages --------------------------------
(defpackage #:nshell.infrastructure.acl
  (:use #:cl)
  (:export #:*exported-environment*
           #:spawn-command #:spawn-pipeline #:spawn-pipeline-async #:wait-job
            #:spawn-async
            #:kill-process #:os-signal->domain
            #:redirect-output #:redirect-error #:redirect-output-and-error
            #:redirect-error-to-output
            #:redirect-input #:redirect-input-document #:redirect-input-string #:restore-redirects #:domain-signal->os
            #:install-signal-handlers
            #:open-pty #:with-pty #:pty-read #:pty-write #:pty-close #:make-pty-stream
            #:pty-spawn #:pty-process #:pty-process-p #:pty-process-pid
            #:pty-process-pgid #:pty-process-master-fd #:pty-process-stream
            #:set-process-group #:set-foreground-pgroup #:get-foreground-pgroup
            #:make-process-group-leader #:reap-children #:get-terminal-size
            #:*external-command-timeout*
            #:run-external #:run-external-capture #:process-exit-status-code
            #:with-git-process-fns #:clear-git-status-cache
            #:invalidate-git-status-cache #:get-git-status
            #:get-git-branch #:git-dirty-p))

(defpackage #:nshell.infrastructure.terminal
  (:use #:cl)
  (:import-from #:nshell.domain.input
                #:key-event #:key-event-p #:make-key-event
                #:key-event-type #:key-event-char #:key-event-number
                #:key-event-data)
  (:export #:with-raw-terminal #:enable-raw-mode #:restore-terminal-mode
            #:ansi-clear-screen #:ansi-clear-line #:ansi-move-cursor
            #:ansi-set-color #:ansi-reset #:ansi-bold #:ansi-dim
            #:ansi-color-code
            #:ansi-save-cursor #:ansi-restore-cursor
            #:ansi-hide-cursor #:ansi-show-cursor
            #:ansi-enable-bracketed-paste #:ansi-disable-bracketed-paste
            #:ansi-enable-sgr-mouse #:ansi-disable-sgr-mouse
            #:ansi-enable-alternate-screen #:ansi-disable-alternate-screen
            #:make-screen #:screen-render #:screen-diff
            #:screen-width #:screen-height #:screen-cell #:screen-put-cell
            #:screen-put-string #:screen-put-line #:screen-resize #:screen-clear
            #:cell-character #:cell-foreground #:cell-background
            #:cell-bold-p #:cell-underline-p
            #:read-key-event
            #:key-event #:key-event-p #:make-key-event
            #:key-event-type #:key-event-char #:key-event-number
            #:key-event-data))

(defpackage #:nshell.infrastructure.persistence
  (:use #:cl)
  (:export #:*history-file-path-override*
           #:load-history-file #:append-history-entry
           #:vacuum-history #:history-file-path
           #:load-config #:save-config #:config-file-path))

;; -- Presentation packages ----------------------------------
(defpackage #:nshell.presentation
  (:use #:cl)
  (:export #:input-state #:input-state-p #:make-input-state
            #:input-state-buffer #:input-state-cursor-pos
            #:input-state-completion-index
            #:input-state-completion-base-buffer
            #:input-state-completion-base-cursor
            #:input-state-last-candidates
            #:input-state-suggestion #:input-state-mode
            #:input-state-vi-visual-anchor
            #:input-state-abbreviation-expander
            #:input-state-kill-ring
            #:input-state-last-argument-start
            #:input-state-last-argument-end
            #:input-state-last-argument-index
            #:input-state-search-query
            #:input-state-search-original-buffer
            #:input-state-search-original-cursor
            #:input-state-search-index
            #:with-normalized-input-state
            #:apply-history-search-results-to-input-state
            #:reduce-input-state #:insert-newline-at-cursor
            #:output-event
            #:run-repl #:trampoline #:render-prompt
            #:compute-suggestion #:accept-suggestion
             #:render-completions #:cycle-completion #:apply-completion
             #:highlight-line #:highlight-span
             #:highlight-span-start #:highlight-span-end
             #:highlight-span-role
             #:highlight->ansi #:theme-color->ansi #:segment-kind->role))
)
