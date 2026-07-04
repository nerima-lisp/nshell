(in-package #:nshell.application)

(defun %erase-set-variables (context names)
  (dolist (name names)
    (setf (shell-context-environment context)
          (nshell.domain.environment:env-unset
           (shell-context-environment context) name)))
  (values nil 0))

(defun %query-set-variables (context names)
  (let ((missing 0)
        (env (shell-context-environment context)))
    (dolist (name names)
      (unless (nshell.domain.environment:env-get env name)
        (incf missing)))
    (values nil (min missing 255))))

(defun %set-usage ()
  (%builtin-usage "set" "set [-x|--export] name value... | set [-e|--erase] name... | set [-q|--query] name..."))

(defun %set-export-option-p (arg)
  (%builtin-option-p arg '("-x" "--export")))

(defun %set-erase-option-p (arg)
  (%builtin-option-p arg '("-e" "--erase")))

(defun %set-query-option-p (arg)
  (%builtin-option-p arg '("-q" "--query")))

(defun %format-set-variable (var)
  (format nil "set ~:[~;-x ~]~a ~a~%"
          (nshell.domain.environment:env-var-exported-p var)
          (nshell.domain.environment:env-var-name var)
          (nshell.domain.environment:env-var-value var)))

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
        (setf (shell-context-environment context)
              (nshell.domain.environment:env-set-values
               (shell-context-environment context)
               (second args)
               (cddr args)
               t))
       (values nil 0))
      ((%set-erase-option-p (first args))
       (with-set-name-argument "-e"
         (%erase-set-variables context (rest args))))
      ((%set-query-option-p (first args))
       (with-set-name-argument "-q"
         (%query-set-variables context (rest args))))
      ((%builtin-option-like-p (first args))
       (values (%set-usage) 1))
      (t
        (setf (shell-context-environment context)
              (nshell.domain.environment:env-set-values
               (shell-context-environment context)
               (first args)
               (rest args)
               nil))
       (values nil 0)))))

(defun %builtin-export (context args)
  (if args
      (progn
        (setf (shell-context-environment context)
              (nshell.domain.environment:env-export
               (shell-context-environment context) (first args)))
      (values nil 0))
      (%builtin-usage "export" "export name")))

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
            (setf (shell-context-environment context)
                  (nshell.domain.environment:env-set
                   (shell-context-environment context) variable line nil))
            (values nil 0))
          (values nil 1)))))
