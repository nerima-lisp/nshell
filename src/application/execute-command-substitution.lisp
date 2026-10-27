(in-package #:nshell.application)

(defun %execute-command-substitution-output (context command-string)
  "Execute COMMAND-STRING as a command substitution within CONTEXT.
Returns its trailing-newline-trimmed output, or NIL on error or timeout."
  (declare (ftype (function (t list &optional t) (values t integer)) source-lines)
           (ftype (function (stream) list) collect-source-lines))
  (handler-case
      (let ((*foreground-terminal-runner* nil))
        (let ((timeout
               (nshell.infrastructure.acl:ensure-timeout-seconds
                *command-substitution-timeout*
                "command substitution timeout")))
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
                       (let ((first-content-token
                              (find-if
                               (lambda (token)
                                 (not (member
                                       (nshell.domain.parsing:scan-token-kind token)
                                       '(:whitespace :line-comment :block-comment))))
                               (nshell.domain.parsing:scan-result-tokens scan-result))))
                         (if (and (not (find #\Newline command-string))
                                  first-content-token
                                  (eq (nshell.domain.parsing:scan-token-reader-context
                                       first-content-token)
                                      :bare-line))
                             (nshell.domain.parsing:with-parsed-command-line-case
                                 (result ast command-string)
                               (:complete
                                (let ((output-stream (make-string-output-stream)))
                                  (let ((*standard-output* output-stream))
                                    (multiple-value-bind (output exit-code)
                                        (execute-ast-in-context context ast)
                                      (declare (ignore exit-code))
                                      (%trim-command-substitution-output
                                       (if (and (stringp output) (plusp (length output)))
                                           output
                                           (get-output-stream-string output-stream)))))))
                               (:error nil)
                               (:incomplete nil)
                               (:empty nil))
                             (multiple-value-bind (output exit-code)
                                 (source-lines
                                  context
                                  (collect-source-lines
                                   (make-string-input-stream command-string)))
                               (declare (ignore exit-code))
                               (%trim-command-substitution-output output))))))))
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
