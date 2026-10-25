(in-package #:nshell.application)

(defun %execute-command-substitution-output (context command-string)
  "Execute COMMAND-STRING as a command substitution within CONTEXT.
Returns its trailing-newline-trimmed output, or NIL on error or timeout."
  (declare (ftype (function (t list &optional t) (values t integer)) source-lines))
  (handler-case
      (let ((*foreground-terminal-runner* nil))
        (flet ((execute-substitution ()
                 (let ((scan-result
                         (nshell.domain.parsing:scan-input
                          command-string
                          :reader-context :auto
                          :head-classifier
                          (lambda (head-source)
                            (classify-sexp-head context head-source)))))
                   (when (eq (nshell.domain.parsing:scan-result-status scan-result)
                             :complete)
                     (multiple-value-bind (output exit-code)
                         (source-lines context (list command-string))
                       (declare (ignore exit-code))
                       (%trim-command-substitution-output output))))))
          (let ((timeout
                  (nshell.infrastructure.acl:ensure-timeout-seconds
                   *command-substitution-timeout*
                   "command substitution timeout")))
            (if timeout
                (sb-ext:with-timeout timeout
                  (execute-substitution))
                (execute-substitution)))))
    (sb-ext:timeout ()
      (format *error-output* "nshell: command substitution timed out: ~a~%"
              command-string)
      nil)))

(defun %execute-command-substitution-fields (context command-string)
  "Execute COMMAND-STRING and split its output into substitution fields."
  (%command-substitution-fields
   (%execute-command-substitution-output context command-string)))
