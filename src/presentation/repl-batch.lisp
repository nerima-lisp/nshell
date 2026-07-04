;;; Batch REPL execution
(in-package #:nshell.presentation)

(defun %initialize-batch-state ()
  "Reset the global shell state for a non-interactive (batch or script) run."
  (setf *running* t
        *last-exit-code* 0
        *last-command-duration-ms* nil
        *environment* (nshell.domain.environment:inject-os-environment
                       (nshell.domain.environment:make-default-environment)))
  (%reset-repl-state-tables)
  (install-expansion-filesystem)
  (configure-completion-filesystem))

(defun %run-batch-source-lines (lines)
  (handler-case
         (multiple-value-bind (output code)
             (%execute-with-repl-shell-context
              (lambda (context)
                (nshell.application:source-lines context lines)))
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
            (%execute-with-repl-shell-context
             (lambda (context)
               (funcall (nshell.application:lookup-builtin "source")
                        context (list path))))
          (declare (ignore output))
          (setf *last-exit-code* (or code 0))))
    (error (condition)
      (format *error-output* "nshell: ~a~%" condition)
      (setf *last-exit-code* 1)))
  *last-exit-code*)
