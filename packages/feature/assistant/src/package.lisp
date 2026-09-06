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
     #:assemble-assistant-context)))
