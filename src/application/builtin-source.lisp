(in-package #:nshell.application)

(defun %builtin-source (context args)
  (if args
      (handler-case
          (with-open-file (stream (first args) :direction :input)
            (%source-lines context (%collect-source-lines stream) (first args)))
        (error (condition)
          (values (format nil "source: ~a: ~a~%" (first args) condition) 1)))
      (%builtin-usage "source" "source file")))

(defun %source-line-parse-error-result (result)
  (values (format nil "source: parse error: ~a~%"
                  (nshell.domain.parsing:format-parse-error-messages result))
          2))

(defun %execute-source-line (context line)
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) line)))
    (if (string= trimmed "")
        (values nil 0)
        (nshell.domain.parsing:with-parsed-command-line-case (result ast trimmed)
          (:complete
           (execute-ast-in-context context ast))
          (:error
           (%source-line-parse-error-result result))
          (:incomplete
           (%source-line-parse-error-result result))))))
