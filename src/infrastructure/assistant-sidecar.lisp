(in-package #:nshell.feature.assistant)

(defstruct (assistant-sidecar-state
            (:constructor %make-assistant-sidecar-state (command arguments)))
  command
  arguments
  handle
  version
  init-p
  disabled-reason
  (lock (sb-thread:make-mutex :name "nshell assistant sidecar"))
  reader-thread
  writer-thread
  error-thread
  dead-p
  dead-reason
  pending
  write-channel)

(defun %assistant-sidecar-nonempty-string (value)
  (and (stringp value) (plusp (length value)) value))

(defun %assistant-sidecar-model (options)
  (or (%assistant-sidecar-nonempty-string (getf options :model))
      (%assistant-sidecar-nonempty-string
       (assistant-setting-value :model))
      (%assistant-sidecar-nonempty-string (uiop:getenv "NSHELL_AI_MODEL"))))

(defun %assistant-sidecar-effort (options)
  (or (%assistant-sidecar-nonempty-string (getf options :effort))
      (%assistant-sidecar-nonempty-string
       (assistant-setting-value :effort))
      "low"))

(defun %assistant-sidecar-status (state)
  (cond
    ((and (assistant-sidecar-state-handle state)
          (assistant-sidecar-state-init-p state)
          (not (%assistant-sidecar-dead-p state)))
     (list :state :running
           :version (assistant-sidecar-state-version state)))
    ((assistant-sidecar-state-disabled-reason state)
     (list :state :unavailable
           :version (assistant-sidecar-state-version state)
           :reason (princ-to-string
                    (assistant-sidecar-state-disabled-reason state))))
    ((assistant-sidecar-state-dead-p state)
     (list :state :unavailable
           :version (assistant-sidecar-state-version state)
           :reason (princ-to-string
                    (or (assistant-sidecar-state-dead-reason state)
                        "assistant sidecar stopped"))))
    (t
     (list :state :not-started
           :version (assistant-sidecar-state-version state)))))

(defun assistant-sidecar-command-arguments (&optional options)
  (let ((arguments
          (list "-p"
                "--input-format" "stream-json"
                "--output-format" "stream-json"
                "--verbose"
                "--no-session-persistence"
                "--tools" ""
                "--strict-mcp-config"
                "--effort" (%assistant-sidecar-effort options)
                "--append-system-prompt" (assistant-sidecar-system-prompt)
                "--json-schema" (assistant-sidecar-json-schema))))
    (let ((model (%assistant-sidecar-model options)))
      (if model
          (append arguments (list "--model" model))
          arguments))))

(defun %assistant-sidecar-command (options)
  (or (getf options :command)
      (let ((configured (uiop:getenv "NSHELL_AI_COMMAND")))
        (and configured (plusp (length configured)) configured))
      "claude"))

(defun %assistant-sidecar-arguments (options)
  (getf options :arguments))
