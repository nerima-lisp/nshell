;;; REPL state initialization
(in-package #:nshell.presentation)

(defparameter *history-persistence-enabled-p* t
  "Whether interactive commands are loaded from and appended to history.")

(defvar *assistant-session-sequence* 0)

(defun %new-assistant-session-id ()
  (format nil "~d-~d-~d-~d"
          (get-universal-time)
          (get-internal-real-time)
          (nshell.infrastructure.acl:current-process-id)
          (incf *assistant-session-sequence*)))

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
                  (%with-repl-shell-context (context)
                    (nshell.application:source-lines
                     context
                     lines
                     source-name))
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
(defun %seed-history-from-file (history)
  "Load persisted entries into HISTORY so recall starts at the newest one.

LOAD-HISTORY-FILE already returns entries oldest first (see its docstring),
which is exactly the order HISTORY-ADD wants: each call records its argument
as the newest entry, so adding oldest-to-last makes the last (newest) file
entry the newest entry in HISTORY too. Do not reverse the loaded list here --
that would hand HISTORY-ADD the newest entry first, burying it under every
older entry added afterward and inverting recall order."
  (dolist (record (nshell.infrastructure.persistence:load-history-file))
    (nshell.infrastructure.persistence::history-record-add
     history
     (nshell.infrastructure.persistence::history-record-text record)
     :timestamp
     (nshell.infrastructure.persistence::history-record-timestamp record)
     :cwd (nshell.infrastructure.persistence::history-record-cwd record)
     :exit-code
     (nshell.infrastructure.persistence::history-record-exit-code record)
     :duration-ms
     (nshell.infrastructure.persistence::history-record-duration-ms record)
     :origin (nshell.infrastructure.persistence::history-record-origin record))))

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
        *last-command-output* nil
        *last-command-text* nil
        *failure-explain-available-p* nil
        *history-persistence-enabled-p* history-p
        *history* (history-kit:make-history)
        *config* (nshell.domain.configuration:default-config)
        *kb* (nshell.domain.completion:make-empty-knowledge-base)
        *input-state* (make-repl-input-state)
        *assistant-turn-generation* 0
        *assistant-turn-started-at* nil
        *assistant-last-cancel-at* nil
        *last-assistant-model-event* nil
        *assistant-model-event-handler* nil
        *assistant-request-kind* nil
        *assistant-explain-candidates* nil
        *assistant-explain-candidate-index* 0
        *agent-session* nil
        *assistant-session-id* (%new-assistant-session-id)
        *assistant-pending-transcript* nil
        nshell.application:*agent-start-handler* #'start-agent-session
        nshell.application:*ai-reset-handler* #'reset-ai-session
        nshell.feature.assistant:*assistant-boundaries*
          (nshell.feature.assistant:make-assistant-boundary-context
           (nshell.feature.assistant:make-assistant-sidecar-boundary))
        *completion-rendered-lines* 0
        *prompt-rendered-lines* 0
        *prompt-rendered-cursor-row* 0
        *prompt-rendered-terminal-width* +default-terminal-width+
        *prompt-rendered-prompt-width* 0
        *prompt-rendered-origin-row* 1
        *prompt-rendered-origin-column* 1
        *prompt-rendered-origin-known-p* nil
        *interactive-terminal-installed-p* nil
        *environment* (nshell.application:seed-shell-status-environment
                       (nshell.domain.environment:inject-os-environment
                        (nshell.domain.environment:make-default-environment)
                        (nshell.infrastructure.acl:current-environment-entries)
                        (function nshell.infrastructure.acl:current-working-directory))))
  (nshell.feature.assistant:reset-assistant-usage)
  (nshell.feature.assistant:reset-assistant-settings)
  (%reset-repl-state-tables)
  (nshell.infrastructure.terminal:reset-terminal-color-depth)
  (setf nshell.domain.prompting:*git-status-resolver*
        (function nshell.infrastructure.acl:get-git-status)
        nshell.application:*theme-apply-handler* (function apply-repl-theme))
  (setf *vi-mode-enabled*
        (%vi-mode-flag-enabled-p
         (nshell.infrastructure.acl:current-environment-value "NSHELL_VI_MODE")))
  (%load-interactive-config :enabled-p load-config-p :path config-path)
  (when history-p
    (%seed-history-from-file *history*))
  (seed-repl-completion-knowledge-base *kb*))
