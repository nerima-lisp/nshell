;;; Machine is the vertical feature for nshell's machine interface (--json,
;;; --serve, MCP). Every response those entry points produce is one envelope
;;; (ux/U6), built and serialized here.
(in-package #:cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.feature.machine
    (:documentation
     "The machine-interface feature's public boundary: the response envelope
of ux/U6, its builders, and its JSON serialization.")
    (:use #:cl)
    (:export #:+nshell-api-version+
             #:invalid-envelope
             #:+effect-kinds+
             #:+safety-levels+
             #:+envelope-response-kinds+
             #:envelope-error-codes
             #:envelope-warning-codes
             ;; Parts
             #:make-envelope-output #:envelope-output-p
             #:envelope-output-text #:envelope-output-bytes
             #:envelope-output-lines #:envelope-output-truncated
             #:envelope-output-path
             #:output-from-text
             #:make-envelope-effect #:envelope-effect-p
             #:envelope-effect-kind #:envelope-effect-path #:envelope-effect-size
             #:make-envelope-reason #:envelope-reason-p
             #:envelope-reason-rule #:envelope-reason-text
             #:make-envelope-safety #:envelope-safety-p
             #:envelope-safety-level #:envelope-safety-reasons
             #:make-envelope-state #:envelope-state-p
             #:envelope-state-cwd #:envelope-state-env-changed
             #:envelope-state-jobs #:envelope-state-last-status
             #:make-envelope-span #:envelope-span-p
             #:envelope-span-line #:envelope-span-column #:envelope-span-end
             #:make-envelope-fix #:envelope-fix-p
             #:envelope-fix-input #:envelope-fix-why #:envelope-fix-rule
             #:make-envelope-error #:envelope-error-object-p
             #:envelope-error-code #:envelope-error-message
             #:envelope-error-span #:envelope-error-fixes
             #:make-envelope-warning #:envelope-warning-p
             #:envelope-warning-code #:envelope-warning-message
             #:envelope-warning-span #:envelope-warning-fixes
             #:make-envelope-form #:envelope-form-p
             #:envelope-form-text #:envelope-form-kind
             #:envelope-form-rule #:envelope-form-path
             ;; Envelope
             #:envelope #:envelope-p
             #:envelope-status #:envelope-duration-ms
             #:envelope-stdout #:envelope-stderr
             #:envelope-value #:envelope-value-present-p
             #:envelope-error #:envelope-warnings #:envelope-forms
             #:envelope-effects #:envelope-safety #:envelope-state
             #:envelope-session #:envelope-seq
             #:envelope-ok-p
             #:result-envelope
             #:error-envelope
             #:explain-envelope
             #:build-envelope-response
             #:envelope-json-object
             #:envelope-to-json
             ;; Output economy
             #:+default-max-output-bytes+
             #:+default-head-lines+
             #:+default-tail-lines+
             #:clean-output-text
             #:economize-output-text
             #:envelope-output-for-text
             ;; Noninteractive runs
             #:+noninteractive-child-environment+
             ;; Output store
             #:output-store-root
             #:output-session #:output-session-p
             #:output-session-id #:output-session-directory
             #:open-output-session
             #:output-session-write
             #:prune-output-sessions
             ;; JSON command
             #:run-json-command)
    (:export #:+json-default-timeout-seconds+
             #:*machine-methods*
             #:make-machine-context
             #:explain-input
             #:initialize-envelope
             #:policy-envelope
             #:read-output-envelope)))
