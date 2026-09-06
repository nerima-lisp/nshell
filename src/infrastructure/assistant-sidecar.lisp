(in-package #:nshell.feature.assistant)

(defstruct (assistant-sidecar-state
            (:constructor %make-assistant-sidecar-state (command)))
  command
  handle
  version
  init-p
  disabled-reason)

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

(defun %assistant-sidecar-read-init (handle)
  (handler-case
      (json-kit:read-json (nshell.infrastructure.acl:sidecar-handle-output handle)
                          :object-type :alist
                          :array-type :list)
    (error () nil)))

(defun %assistant-sidecar-stop-state (state)
  (when (assistant-sidecar-state-handle state)
    (nshell.infrastructure.acl:stop-sidecar
     (assistant-sidecar-state-handle state)))
  (setf (assistant-sidecar-state-handle state) nil
        (assistant-sidecar-state-init-p state) nil)
  t)

(defun %assistant-sidecar-start (state)
  (if (and (assistant-sidecar-state-handle state)
           (nshell.infrastructure.acl:sidecar-alive-p
            (assistant-sidecar-state-handle state)))
      t
      (progn
        (%assistant-sidecar-stop-state state)
        (multiple-value-bind (version version-status)
            (nshell.infrastructure.acl:run-sidecar-version
             (assistant-sidecar-state-command state))
          (if (not (eq :ok version-status))
              (progn
                (setf (assistant-sidecar-state-disabled-reason state)
                      (list :version version-status))
                nil)
              (multiple-value-bind (handle spawn-status)
                  (nshell.infrastructure.acl:spawn-sidecar
                   (assistant-sidecar-state-command state)
                   (assistant-sidecar-command-arguments)
                   :input :stream
                   :output :stream
                   :error :stream)
                (if (null handle)
                    (progn
                      (setf (assistant-sidecar-state-disabled-reason state)
                            (list :spawn spawn-status))
                      nil)
                    (let ((init (%assistant-sidecar-read-init handle)))
                      (if (assistant-system-init-safe-p init)
                          (progn
                            (setf (assistant-sidecar-state-handle state) handle
                                  (assistant-sidecar-state-version state) version
                                  (assistant-sidecar-state-init-p state) t
                                  (assistant-sidecar-state-disabled-reason state) nil)
                            t)
                          (progn
                            (setf (assistant-sidecar-state-disabled-reason state)
                                  :mcp-isolation-failed)
                            (nshell.infrastructure.acl:stop-sidecar handle)
                            nil))))))))))

(defun %assistant-sidecar-request (state generation payload)
  (declare (ignore generation))
  (let ((handle (assistant-sidecar-state-handle state)))
    (if (and handle (assistant-sidecar-state-init-p state))
        (handler-case
            (let* ((object (json-kit:alist->json-object payload))
                   (line (json-kit:stringify object)))
              (unless (json-kit:parse line :object-type :alist)
                (return-from %assistant-sidecar-request nil))
              (write-line line (nshell.infrastructure.acl:sidecar-handle-input
                                handle))
              (finish-output (nshell.infrastructure.acl:sidecar-handle-input
                              handle))
              t)
          (error () nil))
        nil)))

(defun %assistant-sidecar-poll (state generation)
  (declare (ignore state generation))
  (values nil nil))

(defun %assistant-sidecar-stop (state)
  (%assistant-sidecar-stop-state state))

(defun make-assistant-sidecar-boundary (&rest options)
  (let ((state (%make-assistant-sidecar-state
                (%assistant-sidecar-command options))))
    (make-assistant-model-boundary
     :start-fn (lambda () (%assistant-sidecar-start state))
     :request-fn (lambda (generation payload)
                   (%assistant-sidecar-request state generation payload))
     :poll-fn (lambda (generation)
                (%assistant-sidecar-poll state generation))
     :stop-fn (lambda () (%assistant-sidecar-stop state)))))
