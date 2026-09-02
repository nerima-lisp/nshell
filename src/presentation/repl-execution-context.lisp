(in-package #:nshell.presentation)

(defun %make-repl-shell-context ()
  (nshell.application:make-shell-context
   :history *history*
   :config *config*
   :knowledge-base *kb*
   :environment (ensure-environment)
   :filesystem (nshell.infrastructure.acl:make-host-filesystem)
   :job-monitor nshell.application:*job-monitor*
   :alias-table *aliases*
   :abbreviation-table *abbreviations*
   :function-table *functions*
   :function-source-table *function-sources*
   :running *running*
   :pipefail-p *pipefail*
   :last-exit-code *last-exit-code*
   :input-state *input-state*
   :process-registry *proc-registry*))

(defun %repl-external-command-available-p (command)
  (multiple-value-bind (kind path)
      (nshell.application:resolve-command-path
       (%make-repl-shell-context) command)
    (and (eq kind :path) path)))

(defun %sync-repl-shell-context (context code)
  (setf *environment* (nshell.application:shell-context-environment context)
        *aliases* (nshell.application:shell-context-alias-table context)
        *abbreviations* (nshell.application:shell-context-abbreviation-table context)
        *functions* (nshell.application:shell-context-function-table context)
        *function-sources* (nshell.application:shell-context-function-source-table context)
        *running* (nshell.application:shell-context-running context)
        *pipefail* (nshell.application:shell-context-pipefail-p context)
        *last-exit-code* code
        *input-state* (nshell.application:shell-context-input-state context))
  code)

(defun %execute-with-repl-shell-context (thunk)
  (let ((context (%make-repl-shell-context)))
    (multiple-value-bind (output code)
        (funcall thunk context)
      (%sync-repl-shell-context context (or code 0))
      (when output
        (write-string output))
      (values output (or code 0)))))

(defmacro %with-repl-shell-context ((context) &body body)
  `(%execute-with-repl-shell-context
    (lambda (,context)
      ,@body)))
