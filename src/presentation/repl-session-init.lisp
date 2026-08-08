;;; REPL state initialization
(in-package #:nshell.presentation)

(defun %load-interactive-config ()
  (handler-case
      (let ((lines (nshell.infrastructure.persistence:load-config)))
        (when lines
          (multiple-value-bind (output code)
              (%execute-with-repl-shell-context
               (lambda (context)
                 (nshell.application:source-lines
                  context
                  lines
                  ".nshellrc")))
            (declare (ignore output))
            (unless (zerop code)
              (format *error-output*
                      "nshell: .nshellrc exited with status ~a~%"
                      code)))))
    (error (condition)
      (format *error-output* "nshell: .nshellrc: ~a~%" condition))))

(defun initialize-repl-state ()
  (setf *boundaries* (make-real-boundary-context)
        *running* t
        *last-exit-code* 0
        *pipefail* nil
        *last-command-duration-ms* nil
        *history* (history-kit:make-history)
        *config* (nshell.domain.configuration:default-config)
        *kb* (nshell.domain.completion:make-empty-knowledge-base)
        *input-state* (make-repl-input-state)
        *completion-rendered-lines* 0
        *prompt-rendered-lines* 0
        *prompt-rendered-cursor-row* 0
        *prompt-rendered-terminal-width* 80
        *prompt-rendered-prompt-width* 0
        *prompt-rendered-origin-row* 1
        *prompt-rendered-origin-column* 1
        *prompt-rendered-origin-known-p* nil
        *interactive-terminal-installed-p* nil
        *environment* (nshell.domain.environment:inject-os-environment
                       (nshell.domain.environment:make-default-environment)))
  (%reset-repl-state-tables)
  (setf *vi-mode-enabled*
        (let ((flag (host-kit:getenv "NSHELL_VI_MODE")))
          (and flag (not (member flag '("" "0" "false" "no") :test #'string-equal)))))
  (install-expansion-filesystem)
  (configure-completion-filesystem)
  (%load-interactive-config)
  (dolist (entry (reverse (nshell.infrastructure.persistence:load-history-file)))
    (history-kit:history-add *history* entry))
  (seed-repl-completion-knowledge-base *kb*))
