(in-package #:nshell.feature.assistant)

(defstruct (assistant-pending-cell
            (:constructor %make-assistant-pending-cell
                (generation events completion)))
  generation
  events
  completion)

(defstruct (assistant-write-item
            (:constructor %make-assistant-write-item (generation line)))
  generation
  line)

(defun %assistant-sidecar-current-pending (state)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (assistant-sidecar-state-pending state)))

(defun %assistant-sidecar-set-pending (state pending)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (setf (assistant-sidecar-state-pending state) pending)))

(defun %assistant-sidecar-clear-pending (state pending)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (when (eq pending (assistant-sidecar-state-pending state))
      (setf (assistant-sidecar-state-pending state) nil)
      t)))

(defun %assistant-sidecar-publish (cell event)
  (when (assistant-pending-cell-p cell)
    (handler-case
        (cl-concurrent-kit:send (assistant-pending-cell-events cell) event)
      (error () nil))))

(defun %assistant-sidecar-complete (cell)
  (when (assistant-pending-cell-p cell)
    (handler-case
        (unless (cl-concurrent-kit:promise-settled-p
                (assistant-pending-cell-completion cell))
          (cl-concurrent-kit:deliver
           (assistant-pending-cell-completion cell) t))
      (error () nil))))

(defun %assistant-sidecar-error-event (generation message)
  (make-assistant-model-event
   generation
   :stream-error
   (list (cons "message" (or message "assistant sidecar stream error")))))

(defun %assistant-sidecar-reader-loop (state handle)
  (loop
    (multiple-value-bind (object status message)
        (%assistant-read-json-value
         (nshell.infrastructure.acl:sidecar-handle-output handle))
      (let ((pending (%assistant-sidecar-current-pending state)))
        (case status
          (:value
           (when pending
             (let* ((kind (%assistant-event-kind object))
                    (event (make-assistant-model-event
                            (assistant-pending-cell-generation pending)
                            kind
                            object)))
               (%assistant-sidecar-publish pending event)
               (when (eq kind :result)
                 (%assistant-sidecar-complete pending)))))
          (:eof
           (%assistant-sidecar-mark-dead state :reader-eof)
           (when pending
             (%assistant-sidecar-publish
              pending
              (make-assistant-model-event
               (assistant-pending-cell-generation pending)
               :stream-ended
               nil))
             (%assistant-sidecar-complete pending))
           (return))
          (otherwise
           (when (and (eq status :error)
                      (member
                       (nshell.infrastructure.acl:sidecar-handle-cleanup-state handle)
                       '(:stopping :stopped)))
             (return))
           (%assistant-sidecar-mark-dead state (list :reader-error message))
           (when pending
             (%assistant-sidecar-publish
              pending
              (%assistant-sidecar-error-event
               (assistant-pending-cell-generation pending)
               message))
             (%assistant-sidecar-complete pending))
           (return)))))))

(defun %assistant-sidecar-write-item (state item)
  (handler-case
      (let ((stream (and (assistant-sidecar-state-handle state)
                         (nshell.infrastructure.acl:sidecar-handle-input
                          (assistant-sidecar-state-handle state)))))
        (if (streamp stream)
            (progn
              (write-line (assistant-write-item-line item) stream)
              (finish-output stream))
            (error "assistant sidecar input stream is unavailable")))
    (error (condition)
      (%assistant-sidecar-mark-dead state (list :writer-error (princ-to-string condition)))
      (let ((pending (%assistant-sidecar-current-pending state)))
        (when (and pending
                   (eql (assistant-write-item-generation item)
                        (assistant-pending-cell-generation pending)))
          (%assistant-sidecar-publish
           pending
           (%assistant-sidecar-error-event
            (assistant-pending-cell-generation pending)
            (princ-to-string condition)))
          (%assistant-sidecar-complete pending))))))

(defun %assistant-sidecar-writer-loop (state channel)
  (loop
    (multiple-value-bind (item present-p)
        (cl-concurrent-kit:recv channel)
      (unless present-p
        (return))
      (%assistant-sidecar-write-item state item))))

(defun %assistant-sidecar-drain-error (stream)
  (when (streamp stream)
    (handler-case
        (let ((buffer (make-string 4096)))
          (loop for count = (read-sequence buffer stream)
                while (plusp count)))
      (error () nil))))

(defun %assistant-sidecar-join-thread (thread)
  (when thread
    (ignore-errors (sb-thread:join-thread thread))))

(defun %assistant-sidecar-close-channel (channel)
  (when channel
    (ignore-errors (cl-concurrent-kit:close-channel channel))))

(defun %assistant-sidecar-stop-state (state)
  (let ((pending (%assistant-sidecar-current-pending state))
        (write-channel (assistant-sidecar-state-write-channel state))
        (handle (assistant-sidecar-state-handle state))
        (reader (assistant-sidecar-state-reader-thread state))
        (writer (assistant-sidecar-state-writer-thread state))
        (error-thread (assistant-sidecar-state-error-thread state)))
    (when pending
      (%assistant-sidecar-close-channel
       (assistant-pending-cell-events pending)))
    (%assistant-sidecar-close-channel write-channel)
    (when handle
      (nshell.infrastructure.acl:stop-sidecar handle))
    (%assistant-sidecar-join-thread reader)
    (%assistant-sidecar-join-thread writer)
    (%assistant-sidecar-join-thread error-thread)
    (setf (assistant-sidecar-state-handle state) nil
          (assistant-sidecar-state-init-p state) nil
          (assistant-sidecar-state-reader-thread state) nil
          (assistant-sidecar-state-writer-thread state) nil
          (assistant-sidecar-state-error-thread state) nil
          (assistant-sidecar-state-dead-p state) nil
          (assistant-sidecar-state-dead-reason state) nil
          (assistant-sidecar-state-pending state) nil
          (assistant-sidecar-state-write-channel state) nil)
  t))

(defun %assistant-sidecar-start (state)
  (if (and (assistant-sidecar-state-handle state)
           (assistant-sidecar-state-init-p state)
           (not (assistant-sidecar-state-dead-p state))
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
                   (assistant-sidecar-state-arguments state)
                   :input :stream
                   :output :stream
                   :error :stream)
                (if (null handle)
                    (progn
                      (setf (assistant-sidecar-state-disabled-reason state)
                            (list :spawn spawn-status))
                      nil)
                    (let* ((pending
                             (%make-assistant-pending-cell
                              0
                              (cl-concurrent-kit:make-channel :buffer-size 128)
                              (cl-concurrent-kit:make-promise)))
                           (write-channel
                             (cl-concurrent-kit:make-channel :buffer-size 8)))
                      (setf (assistant-sidecar-state-handle state) handle
                            (assistant-sidecar-state-version state) version
                            (assistant-sidecar-state-dead-p state) nil
                            (assistant-sidecar-state-dead-reason state) nil
                            (assistant-sidecar-state-pending state) pending
                            (assistant-sidecar-state-write-channel state)
                              write-channel
                            (assistant-sidecar-state-reader-thread state)
                              (sb-thread:make-thread
                               (lambda ()
                                 (%assistant-sidecar-reader-loop state handle))
                               :name "nshell assistant sidecar reader")
                            (assistant-sidecar-state-writer-thread state)
                              (sb-thread:make-thread
                               (lambda ()
                                 (%assistant-sidecar-writer-loop
                                  state write-channel))
                               :name "nshell assistant sidecar writer")
                            (assistant-sidecar-state-error-thread state)
                              (sb-thread:make-thread
                               (lambda ()
                                 (%assistant-sidecar-drain-error
                                  (nshell.infrastructure.acl:sidecar-handle-error
                                   handle)))
                               :name "nshell assistant sidecar error reader"))
                      (multiple-value-bind (init present-p)
                          (cl-concurrent-kit:recv
                           (assistant-pending-cell-events pending))
                        (if (and present-p
                                 (assistant-model-event-p init)
                                 (eq :system-init
                                     (assistant-model-event-kind init))
                                 (assistant-system-init-safe-p
                                  (assistant-model-event-payload init)))
                            (progn
                              (setf (assistant-sidecar-state-init-p state) t
                                    (assistant-sidecar-state-disabled-reason state)
                                      nil)
                              (%assistant-sidecar-complete pending)
                              (%assistant-sidecar-clear-pending state pending)
                              (%assistant-sidecar-close-channel
                               (assistant-pending-cell-events pending))
                              t)
                            (progn
                              (setf (assistant-sidecar-state-disabled-reason state)
                                    :mcp-isolation-failed)
                              (%assistant-sidecar-stop-state state)
                              nil)))))))))))

(defun %assistant-sidecar-request (state generation payload)
  (unless (and (assistant-sidecar-state-handle state)
               (assistant-sidecar-state-init-p state)
               (not (%assistant-sidecar-dead-p state)))
    (unless (%assistant-sidecar-start state)
      (return-from %assistant-sidecar-request nil)))
  (let ((handle (assistant-sidecar-state-handle state))
        (pending (%assistant-sidecar-current-pending state))
        (channel (assistant-sidecar-state-write-channel state)))
    (if (and handle
             (assistant-sidecar-state-init-p state)
             (not (%assistant-sidecar-dead-p state))
             (null pending)
             channel)
        (handler-case
            (let* ((object (json-kit:alist->json-object payload))
                   (line (json-kit:stringify object)))
              (unless (json-kit:parse line :object-type :alist)
                (return-from %assistant-sidecar-request nil))
              (let ((new-pending
                      (%make-assistant-pending-cell
                       generation
                       (cl-concurrent-kit:make-channel :buffer-size 128)
                       (cl-concurrent-kit:make-promise))))
                (%assistant-sidecar-set-pending state new-pending)
                (if (cl-concurrent-kit:try-send
                     channel
                     (%make-assistant-write-item generation line))
                    t
                    (progn
                      (%assistant-sidecar-clear-pending state new-pending)
                      (%assistant-sidecar-close-channel
                       (assistant-pending-cell-events new-pending))
                      nil))))
          (error () nil))
        nil)))

(defun %assistant-sidecar-poll (state generation)
  (let ((pending (%assistant-sidecar-current-pending state)))
    (if (and pending
             (eql generation (assistant-pending-cell-generation pending)))
        (multiple-value-bind (event present-p closed-p)
            (cl-concurrent-kit:try-recv
             (assistant-pending-cell-events pending))
          (declare (ignore closed-p))
          (when (and present-p
                     (assistant-model-event-p event)
                     (member (assistant-model-event-kind event)
                             '(:result :stream-ended :stream-error)))
            (%assistant-sidecar-clear-pending state pending)
            (%assistant-sidecar-close-channel
             (assistant-pending-cell-events pending)))
          (values event present-p))
        (values nil nil))))

(defun %assistant-sidecar-stop (state)
  (%assistant-sidecar-stop-state state))

(defun %assistant-sidecar-outcome (ok state)
  (values ok (unless ok (assistant-sidecar-state-disabled-reason state))))

(defun make-assistant-sidecar-boundary (&rest options)
  (let ((state (%make-assistant-sidecar-state
                (%assistant-sidecar-command options)
                (%assistant-sidecar-arguments options))))
    (make-assistant-model-boundary
     :start-fn (lambda ()
                 (%assistant-sidecar-outcome (%assistant-sidecar-start state)
                                             state))
     :request-fn (lambda (generation payload)
                   (%assistant-sidecar-outcome
                    (%assistant-sidecar-request state generation payload)
                    state))
     :poll-fn (lambda (generation)
                (%assistant-sidecar-poll state generation))
     :stop-fn (lambda () (%assistant-sidecar-stop state)))))
