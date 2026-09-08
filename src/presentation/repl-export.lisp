(in-package #:nshell.presentation)

(defun %assistant-export-environment-data ()
  (let ((bindings (nshell.domain.environment:env-bindings
                   (ensure-environment))))
    (values (mapcar #'nshell.domain.environment:env-binding-name bindings)
            (mapcar #'nshell.domain.environment:env-binding-value bindings))))

(defun %export-prompt-state ()
  (when (and *interactive-terminal-installed-p* *assistant-session-id*)
    (let ((pending (shiftf *assistant-pending-transcript* nil)))
      (when pending
        (ignore-errors
          (apply #'nshell.application:export-assistant-transcript pending))))
    (multiple-value-bind (environment-names environment-values)
        (%assistant-export-environment-data)
      (ignore-errors
        (nshell.application:export-assistant-snapshot
         :session-id *assistant-session-id*
         :cwd (boundary-current-directory)
         :last (when *last-command-text*
                 (list :text *last-command-text*
                       :exit *last-exit-code*
                       :duration-ms *last-command-duration-ms*))
         :env-names environment-names
         :denylist-values environment-values)))))
