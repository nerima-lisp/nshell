;;; Live theme switching for the interactive session.
(in-package #:nshell.presentation)

(defun apply-repl-theme (theme)
  "Replace the session configuration's theme with THEME."
  (setf *config*
        (nshell.domain.configuration:make-config
         :theme theme
         :east-asian-ambiguous-width
         (nshell.domain.configuration:config-east-asian-ambiguous-width
          *config*)))
  theme)
