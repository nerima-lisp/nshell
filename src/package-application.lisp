;;; nshell application package definitions -- see package.lisp for the split's rationale.

(eval-when (:compile-toplevel :load-toplevel :execute)
;; -- Application packages -----------------------------------
(defpackage #:nshell.application
  (:documentation
   "Application: the use cases. Owns the shell context -- the one mutable object
holding history, environment, aliases, functions, and the job monitor -- and
drives the domain through the infrastructure boundary. Executing a pipeline,
running a builtin, and fg/bg/jobs/disown live here; this is the only layer
permitted to know both the domain and infrastructure.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct #:string-prefix-p)
  (:export #:*job-monitor* #:*shell-pgid* #:*foreground-job-pgid*
            ;; Shared S-expression transition contracts; each stub signals
            ;; WP-INTERFACE-NOT-IMPLEMENTED until its owning WP implements it.
            #:wp-interface-not-implemented
            #:wp-interface-not-implemented-owner-wp
            #:wp-interface-not-implemented-interface
            #:command-failed #:command-failed-command #:command-failed-status
            #:command-failed-stage-statuses #:command-failed-signal
            #:call-with-command-failure-policy
            #:value-conversion-error #:value-conversion-error-operation
            #:value-conversion-error-input #:value-conversion-error-cause
            #:command-execution-plan-error
            #:command-execution-plan-error-source-span
            #:command-execution-plan-error-operation
            #:command-execution-plan-error-cause
            #:byte-stream-execution-error
            #:byte-stream-execution-error-operation
            #:byte-stream-execution-error-cause
            #:command-argument-type-error
            #:command-argument-type-error-value
            #:command-argument-type-error-source-span
            #:command-macro-syntax-error
            #:command-macro-syntax-error-source-span
            #:command-macro-syntax-error-source-path
            #:command-macro-syntax-error-cause
            #:*interactive-top-level-p* #:*command-test-position-p* #:*errexit-p*
            #:builtin-binding #:builtin-binding-p #:make-builtin-binding
            #:builtin-binding-handler #:builtin-binding-argument-mode
            #:*builtin-binding-registry* #:register-builtin
            #:lookup-builtin-binding #:dispatch-builtin #:command-argv-strings
            #:evaluated-command-stage #:evaluated-command-stage-p
            #:make-evaluated-command-stage
            #:evaluated-command-stage-command-node
            #:evaluated-command-stage-dispatch-kind
            #:evaluated-command-stage-binding
            #:evaluated-command-stage-arguments
            #:evaluated-command-stage-redirect-target-values
            #:classify-sexp-head #:evaluate-reader-result-in-context
            #:evaluate-command-stage-in-context
            #:shell-function-binding #:shell-function-binding-p
            #:make-shell-function-binding #:shell-function-binding-callable
            #:shell-function-binding-lambda-list
            #:shell-function-binding-display-name
            #:shell-function-binding-source-path
            #:shell-function-binding-source-span
            #:shell-function-registry #:shell-function-registry-p
            #:make-shell-function-registry #:shell-function-registry-global-table
            #:shell-function-registry-lookup-miss-hook
            #:shell-function-scope #:shell-function-scope-p
            #:make-shell-function-scope #:shell-function-scope-table
            #:shell-function-scope-parent #:context-shell-function-registry
            #:active-shell-function-scope #:register-shell-function
            #:peek-shell-function #:lookup-shell-function
            #:pipeline-execution-result #:pipeline-execution-result-p
            #:make-pipeline-execution-result
            #:pipeline-execution-result-status
            #:pipeline-execution-result-stage-statuses
            #:pipeline-execution-result-stage-signals
            #:pipeline-stage-io #:pipeline-stage-io-p #:make-pipeline-stage-io
            #:pipeline-stage-io-descriptor-map
            #:pipeline-stage-io-transient-descriptors
            #:pipeline-execution-handle #:pipeline-execution-handle-p
            #:*pipeline-stage-io* #:pipeline-stage-stream
            #:spawn-byte-stream-node-in-context
            #:wait-byte-stream-execution #:command-node-external-p
            #:execute-reader-ast-in-context #:argv-scalar-string
            ;; Runtime seams consumed by presentation and assistant adapters.
            #:*builtin-registry* #:*execution-confirmed-p* #:*execution-origin*
            #:*foreground-terminal-runner*
            #:*agent-start-handler*
            #:*ai-reset-handler*
            #:*theme-apply-handler*
            #:function-definition-line-p
            #:*bind-table-handler*
            #:*prompt-format-apply-handler*
            #:*prompt-format-query-handler*
            #:*prompt-preview-handler*
            #:make-shell-context #:shell-context-p
            #:shell-context-history #:shell-context-config
            #:shell-context-knowledge-base #:shell-context-environment
            #:shell-context-filesystem
            #:shell-context-job-monitor
            #:shell-context-alias-table #:shell-context-abbreviation-table
            #:shell-context-function-table #:shell-context-function-source-table
            #:shell-context-execution-strategy #:shell-context-pipefail-p
            #:shell-context-running
            #:shell-context-last-exit-code #:shell-context-input-state
            #:shell-context-job-processes #:shell-context-terminal-rows
            #:shell-context-terminal-cols
            #:lookup-builtin
            #:resolve-command-path
            #:seed-shell-status-environment
            #:collect-source-lines #:source-lines
            #:execute-command-line #:execute-pipeline-use-case #:execute-pipeline
            #:execute-command-node-in-context
            #:execute-ast-in-context
            #:execute-external
            #:expand-command-alias-node
            #:job-listing #:job-listing-p
            #:job-listing-id #:job-listing-status #:job-listing-command
            #:format-job-listing
            #:export-assistant-transcript #:export-assistant-snapshot
            #:fg #:bg #:jobs #:disown #:wait-for-job
            #:history-suggestion #:search-history-use-case
            #:interactive-history-search-use-case
            #:+agent-default-max-steps+
            #:agent-step #:agent-step-p #:make-agent-step
            #:agent-step-text #:agent-step-ast #:agent-step-classification
            #:agent-step-status #:agent-step-reason #:agent-step-output
            #:agent-step-exit-code #:agent-step-executable-p
            #:agent-step-blocked-p
            #:agent-session #:agent-session-p #:make-agent-session
            #:agent-session-task #:agent-session-max-steps
            #:agent-session-steps-used #:agent-session-completed-steps
            #:agent-session-current-step #:agent-session-state
            #:agent-session-stop-reason
            #:agent-session-propose-step #:agent-session-reclassify-step
            #:agent-session-record-step #:agent-session-skip-step
            #:agent-session-stop #:agent-session-limit-reached-p
            #:agent-max-steps-from-context #:define-shell-function #:with-shell-functions))
)
