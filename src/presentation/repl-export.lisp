(in-package #:nshell.presentation)

(defun %assistant-environment-denylist-values (bindings)
  ;; Only known, typed non-credential bindings may be omitted. Unknown short
  ;; values remain protected, even when they duplicate a normal setting.
  (loop for binding in bindings
        for name = (nshell.domain.environment:env-binding-name binding)
        for value = (nshell.domain.environment:env-binding-value binding)
        for number = (and (member name '("NSHELL_AI_MAX_STEPS" "?" "status")
                                  :test #'string=)
                          (plusp (length value))
                          (every (lambda (character)
                                   (char<= #\0 character #\9))
                                 value)
                          (parse-integer value))
        unless (and number
                    (or (and (string= name "NSHELL_AI_MAX_STEPS")
                             (plusp number))
                        (and (member name '("?" "status") :test #'string=)
                             (not (nshell.domain.environment:env-binding-exported-p
                                   binding))
                             (<= 0 number 255))))
          collect value))

(defun %assistant-export-environment-data ()
  (let ((bindings (nshell.domain.environment:env-bindings
                   (ensure-environment))))
    (values (mapcar #'nshell.domain.environment:env-binding-name bindings)
            (%assistant-environment-denylist-values bindings))))

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
         :denylist-paths
         nshell.feature.assistant:+assistant-default-denylist-paths+
         :denylist-commands
         nshell.feature.assistant:+assistant-default-denylist-commands+
         :denylist-values environment-values)))))
