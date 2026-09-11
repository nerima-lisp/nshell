(in-package #:nshell.application)

;;; `and` / `or` command builtins -- distinct from the `&&` / `||` sequence
;;; separators in execute-pipeline-control.lisp: these run as ordinary
;;; commands (`echo a; and echo b`), gated on the exit status the *previous*
;;; command already recorded via %RECORD-LAST-EXIT-CODE. They live here
;;; rather than alongside that dispatcher because DEFINE-BUILTIN
;;; (builtin-macros.lisp) is not yet defined at the point execute-pipeline-
;;; control.lisp loads (see nshell.asd's file order) -- every other builtin
;;; already lives in a file the system loads after builtin-macros.lisp, and
;;; this one is no exception. Like %BUILTIN-NOT, the gated command runs
;;; through the existing application entry point rather than a bespoke
;;; dispatch path.

(define-builtin %builtin-and (context args) ()
  (if args
      (if (zerop (shell-context-last-exit-code context))
          (%execute-command-by-name-in-context context (first args) (rest args))
          (values nil (shell-context-last-exit-code context)))
      (%builtin-usage "and" "and command [args...]" 2)))

(define-builtin %builtin-or (context args) ()
  (if args
      (if (zerop (shell-context-last-exit-code context))
          (values nil (shell-context-last-exit-code context))
          (%execute-command-by-name-in-context context (first args) (rest args)))
      (%builtin-usage "or" "or command [args...]" 2)))

;;; `functions` (fish's function inspector, distinct from the singular
;;; `function` builtin in builtin-state-functions.lisp which defines/erases)
;;; and `builtin` (bypass functions and aliases, run a builtin directly).

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
            (funcall handler context (rest args))
            (values (format nil "builtin: ~a: not a builtin~%" (first args)) 1)))))
