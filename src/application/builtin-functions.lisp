(in-package #:nshell.application)

;;; `functions` (lists, shows, and erases shell functions) and `builtin`
;;; (bypass functions and aliases, run a builtin directly).

(defun %builtin-functions-names (context)
  (let ((names nil))
    (maphash (lambda (name body) (declare (ignore body)) (push name names))
             (shell-context-function-table context))
    (values (format nil "~{~a~%~}" (sort names #'string<)) 0)))

(defun %builtin-functions-source (context name)
  (multiple-value-bind (body-lines defined-p)
      (gethash name (shell-context-function-table context))
    (if (not defined-p)
        (values (format nil "functions: ~a: not a function~%" name) 1)
        (let ((source-path (gethash name (shell-context-function-source-table context))))
          (values
           (with-output-to-string (out)
             (when source-path
               (format out "# Defined in ~a~%" source-path))
             (write-string (%format-function-definition name body-lines) out))
           0)))))

(defun %builtin-functions-erase (context args)
  (if args
      (progn
        (dolist (name args) (%remove-shell-function-definition context name))
        (values nil 0))
      (values (%required-argument-error "functions" "-e" "a name") 2)))

(define-builtin %builtin-functions (context args) ()
  (cond
    ((null args) (%builtin-functions-names context))
    ((member (first args) '("-e" "--erase") :test #'string=)
     (%builtin-functions-erase context (rest args)))
    ((rest args) (%builtin-usage "functions" "functions [-e] [NAME]" 2))
    (t (%builtin-functions-source context (first args)))))

(define-builtin %builtin-builtin (context args) ()
  (if (null args)
      (%builtin-usage "builtin" "builtin NAME [args...]" 2)
      (let ((handler (lookup-builtin (first args))))
        (if handler
            (%assistant-gated-command-dispatch
             context (first args) (rest args)
             (lambda () (funcall handler context (rest args))))
            (values (format nil "builtin: ~a: not a builtin~%" (first args)) 1)))))
