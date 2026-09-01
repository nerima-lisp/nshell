(in-package #:nshell.application)

(defun %update-shell-environment (context update-fn &rest args)
  (setf (shell-context-environment context)
        (apply update-fn (shell-context-environment context) args)))

(defun %erase-set-variables (context names)
  (dolist (name names)
    (%update-shell-environment context
                               #'nshell.domain.environment:env-unset
                               name))
  (values nil 0))

(defun %query-set-variables (context names)
  (let ((missing 0)
        (env (shell-context-environment context)))
    (dolist (name names)
      (unless (nshell.domain.environment:env-get env name)
        (incf missing)))
    (values nil (min missing 255))))

(defun %shell-variable-name-p (name)
  (and (stringp name)
       (plusp (length name))
       (let ((first (char name 0)))
         (or (alpha-char-p first)
             (char= first #\_)))
       (loop for index from 1 below (length name)
             always (let ((character (char name index)))
                      (or (alphanumericp character)
                          (char= character #\_))))))

(defun %export-assignment (argument)
  (let ((separator (position #\= argument)))
    (if separator
        (values (subseq argument 0 separator)
                (subseq argument (1+ separator))
                t)
        (values argument nil nil))))

(defun %set-usage ()
  (%builtin-usage
   "set"
   "set [-x|--export] name value... | set [-e|--erase] name... | set [-q|--query] name... | set [-o|+o] pipefail"))

(defun %set-export-option-p (arg)
  (%builtin-option-p arg '("-x" "--export")))

(defun %set-erase-option-p (arg)
  (%builtin-option-p arg '("-e" "--erase")))

(defun %set-query-option-p (arg)
  (%builtin-option-p arg '("-q" "--query")))

(defun %format-set-variable (var)
  (format nil "set ~:[~;-x ~]~a ~a~%"
          (nshell.domain.environment:env-binding-exported-p var)
          (nshell.domain.environment:env-binding-name var)
          (nshell.domain.environment:env-binding-value var)))

(defun %format-set-variables (env)
  (with-output-to-string (out)
    (dolist (var (nshell.domain.environment:env-bindings env))
      (write-string (%format-set-variable var) out))))

(defun %builtin-set (context args)
  (macrolet ((with-set-name-argument (option &body body)
               `(%with-required-argument (%builtin-set args "set" ,option "a name" 2)
                  ,@body)))
    (cond
      ((null args)
       (values (%format-set-variables (shell-context-environment context)) 0))
      ((%set-export-option-p (first args))
       (unless (second args)
         (return-from %builtin-set (values (%set-usage) 1)))
       (%update-shell-environment context
                                  #'nshell.domain.environment:env-set-values
                                  (second args)
                                  (cddr args)
                                  t)
       (values nil 0))
      ((%set-erase-option-p (first args))
       (with-set-name-argument "-e"
         (%erase-set-variables context (rest args))))
      ((%set-query-option-p (first args))
       (with-set-name-argument "-q"
         (%query-set-variables context (rest args))))
      ((and (member (first args) '("-o" "+o") :test #'string=)
            (string= (second args) "pipefail")
            (null (cddr args)))
       (setf (shell-context-pipefail-p context)
             (string= (first args) "-o"))
       (values nil 0))
      ((%builtin-option-like-p (first args))
       (values (%set-usage) 1))
      (t
       (%update-shell-environment context
                                  #'nshell.domain.environment:env-set-values
                                  (first args)
                                  (rest args)
                                  nil)
       (values nil 0)))))

(defun %builtin-export (context args)
  (let ((arguments (if (and args (string= (first args) "--"))
                       (rest args)
                       args)))
    (if (null arguments)
        (%builtin-usage "export" "export name[=value] ...")
        (dolist (argument arguments (values nil 0))
          (multiple-value-bind (name value assignment-p)
              (%export-assignment argument)
            (unless (%shell-variable-name-p name)
              (return-from %builtin-export
                (values (format nil "export: invalid identifier: ~a~%" argument) 2)))
            (if assignment-p
                (%update-shell-environment context
                                           #'nshell.domain.environment:env-set
                                           name
                                           value
                                           t)
                (if (nshell.domain.environment:env-defined-p
                     (shell-context-environment context)
                     name)
                    (%update-shell-environment context
                                               #'nshell.domain.environment:env-export
                                               name)
                    (%update-shell-environment context
                                               #'nshell.domain.environment:env-set
                                               name
                                               ""
                                               t))))))))

(defun %builtin-unset (context args)
  (let ((arguments (if (and args (string= (first args) "--"))
                       (rest args)
                       args)))
    (when (and arguments
               (%builtin-option-like-p (first arguments)))
      (return-from %builtin-unset
        (%builtin-usage "unset" "unset [name ...]" 2)))
    (dolist (name arguments (values nil 0))
      (unless (%shell-variable-name-p name)
        (return-from %builtin-unset
          (values (format nil "unset: invalid identifier: ~a~%" name) 2)))
      (%update-shell-environment context
                                 #'nshell.domain.environment:env-unset
                                 name))))

(defun %builtin-read (context args)
  (let ((prompt nil)
        (variable nil)
        (remaining args))
    (when (and remaining (string= (first remaining) "-p"))
      (%with-required-argument (%builtin-read remaining "read" "-p" "a prompt" 2)
        (setf prompt (second remaining)
              remaining (cddr remaining))))
    (setf variable (first remaining))
    (unless variable
      (return-from %builtin-read
        (%builtin-usage "read" "read [-p prompt] variable")))
    (when prompt
      (write-string prompt)
      (finish-output))
    (let ((line (read-line *standard-input* nil nil)))
      (if line
          (progn
            (%update-shell-environment context
                                       #'nshell.domain.environment:env-set
                                       variable
                                       line
                                       nil)
            (values nil 0))
          (values nil 1)))))

(defun %parse-loop-control-count (args)
  (cond
    ((null args) 1)
    ((cdr args) nil)
    (t
     (handler-case
         (let ((count (parse-integer (first args) :junk-allowed nil)))
           (and (plusp count) count))
       (error () nil)))))

(defun %builtin-loop-control (command kind args)
  (unless (plusp *loop-control-depth*)
    (return-from %builtin-loop-control
      (values (format nil "~a: only meaningful in a loop~%" command) 1)))
  (let ((count (%parse-loop-control-count args)))
    (unless count
      (return-from %builtin-loop-control
        (values (format nil "~a: usage: ~a [N]~%" command command) 2)))
    (setf *loop-control-signal* (cons kind count))
    (values nil 0)))

(define-builtin %builtin-break (context args) (context)
  (%builtin-loop-control "break" :break args))

(define-builtin %builtin-continue (context args) (context)
  (%builtin-loop-control "continue" :continue args))
