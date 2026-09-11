;;; Batch REPL execution
(in-package #:nshell.presentation)

(defun %initialize-batch-state ()
  "Reset the global shell state for a non-interactive (batch or script) run."
  (setf *running* t
        *last-exit-code* 0
        *pipefail* nil
        *last-command-duration-ms* nil
        *last-command-output* nil
        *last-command-text* nil
        *failure-explain-available-p* nil
        *agent-session* nil
        *assistant-session-id* nil
        *assistant-pending-transcript* nil
        nshell.application:*agent-start-handler* nil
        nshell.application:*ai-reset-handler* nil
        ;; A script inspects and sets the same shell state an interactive
        ;; session does, so the handlers the builtins reach through are
        ;; installed here too.
        nshell.application:*theme-apply-handler* (function apply-repl-theme)
        nshell.application:*bind-table-handler* (function bind-dispatch-handler)
        nshell.application:*prompt-format-apply-handler* (function apply-prompt-format)
        nshell.application:*prompt-format-query-handler* (function current-prompt-format)
        nshell.application:*prompt-preview-handler* (function preview-prompt-format)
        *prompt-rendered-terminal-width* +default-terminal-width+
        *prompt-rendered-prompt-width* 0
        *prompt-rendered-origin-row* 1
        *prompt-rendered-origin-column* 1
        *prompt-rendered-origin-known-p* t
        *interactive-terminal-installed-p* nil
        *config* (nshell.domain.configuration:default-config)
        *kb* (seed-repl-completion-knowledge-base
              (nshell.domain.completion:make-empty-knowledge-base))
        *environment* (nshell.application:seed-shell-status-environment
                       (nshell.domain.environment:inject-os-environment
                        (nshell.domain.environment:make-default-environment)
                        (nshell.infrastructure.acl:current-environment-entries)
                        (function nshell.infrastructure.acl:current-working-directory))))
  (nshell.feature.assistant:reset-assistant-usage)
  (nshell.feature.assistant:reset-assistant-settings)
  (%reset-repl-state-tables))

(defun %run-batch-source-lines (lines)
  (handler-case
         (multiple-value-bind (output code)
             (%with-repl-shell-context (context)
               (nshell.application:source-lines context lines))
        (declare (ignore output))
        (setf *last-exit-code* (or code 0)))
    (error (condition)
      (format *error-output* "nshell error: ~a~%" condition)
      (setf *last-exit-code* 1))))

(defun run-repl-batch (&key line script-args)
  "Batch (non-interactive) mode: read lines, execute commands, print raw output.
SCRIPT-ARGS are exposed as $argv for `nshell -c COMMAND ARGS...'."
  (%initialize-batch-state)
  (let ((nshell.domain.expansion:*positional-args* script-args))
         (if line
             (%run-batch-source-lines (list line))
             (%run-batch-source-lines
              (nshell.application:collect-source-lines *standard-input*))))
  *last-exit-code*)

(defun run-repl-script (path &optional script-args)
  "Execute the script file at PATH (multiline blocks supported, via the same
block-aware reader as the `source' builtin). SCRIPT-ARGS are exposed to the
script as $argv. Returns the exit status of the last command."
  (%initialize-batch-state)
  (handler-case
      (let ((nshell.domain.expansion:*positional-args* script-args))
        (multiple-value-bind (output code)
            (%with-repl-shell-context (context)
              (funcall (nshell.application:lookup-builtin "source")
                       context (list path)))
          (declare (ignore output))
          (setf *last-exit-code* (or code 0))))
    (error (condition)
      (format *error-output* "nshell: ~a~%" condition)
      (setf *last-exit-code* 1)))
  *last-exit-code*)
