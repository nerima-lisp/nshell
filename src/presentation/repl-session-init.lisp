;;; REPL state initialization
(in-package #:nshell.presentation)

(defun initialize-repl-state ()
  (setf *boundaries* (make-real-boundary-context)
        *running* t
        *last-exit-code* 0
        *last-command-duration-ms* nil
        *history* (history-kit:make-history)
        *config* (nshell.domain.configuration:default-config)
        *kb* (nshell.domain.completion:make-empty-knowledge-base)
        *input-state* (make-repl-input-state)
        *completion-rendered-lines* 0
        *prompt-rendered-lines* 0
        *prompt-rendered-cursor-row* 0
        *environment* (nshell.domain.environment:inject-os-environment
                       (nshell.domain.environment:make-default-environment)))
  (%reset-repl-state-tables)
  (setf *vi-mode-enabled*
        (let ((flag (host-kit:getenv "NSHELL_VI_MODE")))
          (and flag (not (member flag '("" "0" "false" "no") :test #'string-equal)))))
  (install-expansion-filesystem)
  (configure-completion-filesystem)
  (dolist (entry (reverse (nshell.infrastructure.persistence:load-history-file)))
    (history-kit:history-add *history* entry))
  (seed-repl-completion-knowledge-base *kb*))
