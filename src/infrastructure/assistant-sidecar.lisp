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

(defun assistant-sidecar-command-arguments ()
  (list "-p"
        "--input-format" "stream-json"
        "--output-format" "stream-json"
        "--verbose"
        "--no-session-persistence"
        "--tools" ""
        "--strict-mcp-config"))

(defun %assistant-sidecar-command (options)
  (or (getf options :command)
      (let ((configured (uiop:getenv "NSHELL_AI_COMMAND")))
        (and configured (plusp (length configured)) configured))
      "claude"))

(defun %assistant-sidecar-arguments (options)
  (or (getf options :arguments)
      (assistant-sidecar-command-arguments)))
