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
      (%assistant-sidecar-nonempty-string (uiop:getenv "NSHELL_AI_MODEL"))))

(defun %assistant-sidecar-effort (options)
  (or (%assistant-sidecar-nonempty-string (getf options :effort))
      "low"))

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
  (or (getf options :arguments)
      (assistant-sidecar-command-arguments options)))
