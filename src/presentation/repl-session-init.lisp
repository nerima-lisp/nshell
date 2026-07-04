;;; REPL state initialization
(in-package #:nshell.presentation)

(defun initialize-repl-state ()
  (setf *running* t
        *last-exit-code* 0
        *last-command-duration-ms* nil
        *history* (nshell.domain.history:make-command-history)
        *config* (nshell.domain.configuration:default-config)
        *kb* (nshell.domain.completion:make-empty-knowledge-base)
        *input-state* (make-repl-input-state)
        *completion-rendered-lines* 0
        *prompt-rendered-lines* 0
        *prompt-rendered-cursor-row* 0
        *environment* (nshell.domain.environment:inject-os-environment
                       (nshell.domain.environment:make-default-environment))
        *aliases* (make-hash-table :test #'equal)
        *abbreviations* (make-hash-table :test #'equal)
        *functions* (make-hash-table :test #'equal)
        *function-sources* (make-hash-table :test #'equal)
        *proc-registry* (make-hash-table :test #'eql))
  (setf *vi-mode-enabled*
        (let ((flag (uiop:getenv "NSHELL_VI_MODE")))
          (and flag (not (member flag '("" "0" "false" "no") :test #'string-equal)))))
  (install-expansion-filesystem)
  (configure-completion-filesystem)
  (dolist (entry (reverse (nshell.infrastructure.persistence:load-history-file)))
    (nshell.domain.history:history-add *history* entry))
  (seed-repl-completion-knowledge-base *kb*))
