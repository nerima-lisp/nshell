;;; REPL state initialization
(in-package #:nshell.presentation)

(defparameter *history-persistence-enabled-p* t
  "Whether interactive commands are loaded from and appended to history.")

(defun %config-source-name (path)
  (if path
      (namestring (pathname path))
      ".nshellrc"))

(defun %load-interactive-config (&key (enabled-p t) path)
  (when enabled-p
    (let ((source-name (%config-source-name path)))
      (handler-case
          (let ((lines (if path
                           (nshell.infrastructure.persistence:load-config path)
                           (nshell.infrastructure.persistence:load-config))))
            (when lines
              (multiple-value-bind (output code)
                  (%execute-with-repl-shell-context
                   (lambda (context)
                     (nshell.application:source-lines
                      context
                      lines
                      source-name)))
                (declare (ignore output))
                (unless (zerop code)
                  (format *error-output*
                          "nshell: ~a exited with status ~a~%"
                          source-name
                          code)))))
        (error (condition)
          (format *error-output* "nshell: ~a: ~a~%"
                  source-name
                  condition))))))
(defun %vi-mode-flag-enabled-p (flag)
  (and flag
       (not (member flag
                    (list "" "0" "false" "no")
                    :test (function string-equal)))))

(defun initialize-repl-state (&key (load-config-p t) config-path (history-p t))
  "Initialize an interactive session with explicit startup persistence policy.

CONFIG-PATH overrides the default .nshellrc path when LOAD-CONFIG-P is true.
HISTORY-P controls both loading the existing history and appending commands
entered during this session."
  (setf *boundaries* (make-real-boundary-context)
        *running* t
        *last-exit-code* 0
        *pipefail* nil
        *last-command-duration-ms* nil
        *history-persistence-enabled-p* history-p
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
                       (nshell.domain.environment:make-default-environment)
                       (nshell.infrastructure.acl:current-environment-entries)
                       #'nshell.infrastructure.acl:current-working-directory))
  (%reset-repl-state-tables)
  (setf *vi-mode-enabled*
        (%vi-mode-flag-enabled-p
         (nshell.infrastructure.acl:current-environment-value "NSHELL_VI_MODE")))
  (%load-interactive-config :enabled-p load-config-p :path config-path)
  (when history-p
    (dolist (entry (reverse (nshell.infrastructure.persistence:load-history-file)))
      (history-kit:history-add *history* entry)))
  (seed-repl-completion-knowledge-base *kb*))
