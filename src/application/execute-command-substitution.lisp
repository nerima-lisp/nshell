(in-package #:nshell.application)

(defun %execute-command-substitution-output (context command-string)
  "Execute COMMAND-STRING as a command substitution within CONTEXT.
Returns its trailing-newline-trimmed output, or NIL on error or timeout."
  (handler-case
      (nshell.domain.parsing:with-parsed-command-line-case (result ast command-string)
        (:complete
         (flet ((execute-substitution ()
                  (multiple-value-bind (output exit-code)
                      (execute-ast-in-context context ast)
                    (declare (ignore exit-code))
                    (%trim-command-substitution-output output))))
           (if *command-substitution-timeout*
               (sb-ext:with-timeout *command-substitution-timeout*
                 (execute-substitution))
               (execute-substitution))))
        (:error nil)
        (:incomplete nil))
    (sb-ext:timeout ()
      (format *error-output* "nshell: command substitution timed out: ~a~%"
              command-string)
      nil)))

(defun %execute-command-substitution-fields (context command-string)
  "Execute COMMAND-STRING and split its output into substitution fields."
  (%command-substitution-fields
   (%execute-command-substitution-output context command-string)))
