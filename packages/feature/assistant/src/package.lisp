;;; Assistant is a vertical feature: each DDD layer lives beside the others
;;; under this feature root instead of being spread across a global layer tree.
(in-package #:cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.feature.assistant
    (:documentation
     "The assistant feature's public boundary.
The domain values and infrastructure boundaries live here so later layers can
depend on one stable feature package.")
    (:use #:cl)
    (:export
     #:assistant-safety-rule
     #:assistant-safety-rule-p
     #:assistant-safety-rule-name
     #:assistant-safety-rule-classification
     #:assistant-safety-rule-command
     #:assistant-safety-rule-condition
     #:assistant-safety-rule-reason
     #:+assistant-safety-rules+
     #:assistant-safety-result
     #:assistant-safety-result-p
     #:assistant-safety-result-classification
     #:assistant-safety-result-reason
     #:assistant-safety-result-command
     #:assistant-safety-result-rule-name
     #:classify-command
     #:classify-pipeline
     #:classify-ast
     #:+assistant-redacted-token+
     #:redact-text
     #:redact-lines
     #:redact-payload
     #:+assistant-default-output-max-bytes+
     #:assistant-context
     #:assistant-context-p
     #:assistant-context-command
     #:assistant-context-exit
     #:assistant-context-duration-ms
     #:assistant-context-cwd
     #:assistant-context-git-status
     #:assistant-context-last-output
     #:assistant-context-environment-names
     #:make-assistant-context
     #:assistant-context-payload
     #:assemble-assistant-context
     #:*assistant-audit-file-path-override*
     #:assistant-audit-file-path
     #:append-assistant-audit-entry
     #:*assistant-boundaries*
     #:make-assistant-boundary-context
     #:assistant-model-boundary
     #:assistant-model-boundary-p
     #:make-assistant-model-boundary
     #:assistant-boundary-start
     #:assistant-boundary-request
     #:assistant-boundary-poll
     #:assistant-boundary-stop
     #:assistant-boundary-status
     #:assistant-boundary-value
     #:assistant-boundary-message
     #:assistant-model-start
     #:assistant-model-request
     #:assistant-model-poll
     #:assistant-model-stop
     #:assistant-model-event
     #:assistant-model-event-p
     #:assistant-model-event-generation
     #:assistant-model-event-kind
     #:assistant-model-event-payload
     #:next-assistant-turn-generation
     #:make-assistant-user-payload
     #:assistant-system-init-safe-p
     #:make-assistant-sidecar-boundary
     #:assistant-sidecar-command-arguments
     #:make-assistant-fixture-boundary)))
