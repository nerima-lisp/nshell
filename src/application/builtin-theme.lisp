(in-package #:nshell.application)

(defvar *theme-apply-handler* nil
  "NIL, or a function of one THEME that the interactive session installs so
the theme builtin can swap the live configuration.")

(defun %builtin-theme-usage ()
  (%builtin-usage "theme" "theme [show|list|use NAME|set ROLE SPEC|reset]"))

(defun %theme-role-name (role)
  (string-downcase (symbol-name role)))

(defun %theme-find-role (theme name)
  (find name (nshell.domain.configuration:theme-roles theme)
        :key #'%theme-role-name :test #'string-equal))

(defun %theme-role-sample (style)
  (with-output-to-string (stream)
    (write-string
     (nshell.infrastructure.terminal:ansi-style-sequence
      :foreground (nshell.domain.configuration:text-style-foreground style)
      :background (nshell.domain.configuration:text-style-background style)
      :bold (nshell.domain.configuration:text-style-bold style)
      :dim (nshell.domain.configuration:text-style-dim style)
      :italic (nshell.domain.configuration:text-style-italic style)
      :underline (nshell.domain.configuration:text-style-underline style)
      :reverse (nshell.domain.configuration:text-style-reverse style))
     stream)
    (write-string "sample" stream)
    (nshell.infrastructure.terminal:ansi-reset-style stream)))

(defun %theme-show-output (theme)
  (let* ((roles (nshell.domain.configuration:theme-roles theme))
         (width (reduce #'max roles
                        :key (lambda (role) (length (%theme-role-name role)))
                        :initial-value 0))
         (sample-p (nshell.infrastructure.terminal:interactive-terminal-p 1)))
    (with-output-to-string (stream)
      (format stream "~a~%" (nshell.domain.configuration:theme-name theme))
      (dolist (role roles)
        (let ((spec (nshell.domain.configuration:theme-color theme role))
              (style (nshell.domain.configuration:theme-style theme role)))
          (format stream "  ~va  ~a" width (%theme-role-name role) spec)
          (when (and sample-p style)
            (format stream "   ~a" (%theme-role-sample style)))
          (terpri stream))))))

(defun %theme-list-output (current-name)
  (with-output-to-string (stream)
    (dolist (name (nshell.domain.configuration:theme-preset-names))
      (format stream "~a~a~%"
              (if (string-equal name current-name) "* " "  ")
              name))))

(defun %theme-apply (context theme)
  (when (functionp *theme-apply-handler*)
    (funcall *theme-apply-handler* theme))
  (when (shell-context-config context)
    (setf (shell-context-config context)
          (nshell.domain.configuration:make-config :theme theme)))
  theme)

(defun %theme-use (context name)
  (let ((preset (nshell.domain.configuration:find-theme-preset name)))
    (if preset
        (progn (%theme-apply context preset) (values nil 0))
        (values (format nil "theme: unknown theme ~a (try: theme list)~%" name)
                2))))

(defun %theme-set (context theme role-name spec-words)
  (let ((role (%theme-find-role theme role-name)))
    (if (null role)
        (values (format nil "theme: unknown role ~a (try: ~{~a~^, ~})~%"
                        role-name
                        (mapcar #'%theme-role-name
                                (nshell.domain.configuration:theme-roles theme)))
                2)
        (handler-case
            (let ((updated (nshell.domain.configuration:theme-set-color
                            theme role (%string-join spec-words " "))))
              (%theme-apply context updated)
              (values nil 0))
          (nshell.domain.configuration:invalid-style-spec (condition)
            (values (format nil "theme: ~a~%"
                            (nshell.domain.configuration:invalid-style-spec-reason
                             condition))
                    2))))))

(define-builtin %builtin-theme (context args) ()
  (let ((theme (nshell.domain.configuration:config-theme
                (shell-context-config context))))
    (cond
      ((null args) (values (%theme-show-output theme) 0))
      ((and (string-equal (first args) "show") (null (rest args)))
       (values (%theme-show-output theme) 0))
      ((and (string-equal (first args) "list") (null (rest args)))
       (values (%theme-list-output (nshell.domain.configuration:theme-name theme))
               0))
      ((and (string-equal (first args) "use") (second args) (null (cddr args)))
       (%theme-use context (second args)))
      ((and (string-equal (first args) "set") (second args) (third args))
       (%theme-set context theme (second args) (cddr args)))
      ((and (string-equal (first args) "reset") (null (rest args)))
       (%theme-apply context (nshell.domain.configuration:default-theme))
       (values nil 0))
      (t (%builtin-theme-usage)))))
