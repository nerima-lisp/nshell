(in-package #:nshell.feature.assistant)

(defun %assistant-event-kind (object)
  (let ((type (%assistant-object-field object "type"))
        (subtype (%assistant-object-field object "subtype")))
    (cond
      ((and (equal type "system") (equal subtype "init")) :system-init)
      ((equal type "assistant") :assistant)
      ((equal type "rate_limit_event") :rate-limit-event)
      ((equal type "result") :result)
      (t :unknown))))

(defun %assistant-read-json-value (stream)
  (handler-case
      (let ((first-char
              (loop for char = (read-char stream nil :eof)
                    do (cond
                         ((eq char :eof) (return :eof))
                         ((find char '(#\Space #\Tab #\Newline #\Return)
                                :test #'char=))
                         (t (unread-char char stream)
                            (return char))))))
        (if (eq first-char :eof)
            (values nil :eof nil)
            (values (json-kit:read-json stream
                                        :object-type :alist
                                        :array-type :list)
                    :value nil)))
    (error (condition)
      (values nil :error (princ-to-string condition)))))

(defstruct (assistant-pending-cell
            (:constructor %make-assistant-pending-cell
                (generation events completion &optional request-payload)))
  generation
  events
  completion
  request-payload)

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
             (let ((kind (%assistant-event-kind object)))
               (if (eq kind :unknown)
                   (progn
                     (%assistant-sidecar-publish
                      pending
                      (%assistant-sidecar-error-event
                       (assistant-pending-cell-generation pending)
                       "assistant sidecar returned an unknown event"))
                     (%assistant-sidecar-complete pending))
                   (let ((event (make-assistant-model-event
                                 (assistant-pending-cell-generation pending)
                                 kind
                                 object)))
                     (%assistant-sidecar-publish pending event)
                     (when (eq kind :result)
                       (%assistant-sidecar-complete pending)))))))
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
    (ignore-errors
     (sb-thread:join-thread thread :default nil :timeout 0.1))
    (when (sb-thread:thread-alive-p thread)
      (ignore-errors (sb-thread:terminate-thread thread))
      (ignore-errors
       (sb-thread:join-thread thread :default nil :timeout 0.1)))))

(defun %assistant-sidecar-close-channel (channel)
  (when channel
    (ignore-errors (cl-concurrent-kit:close-channel channel))))

(defun %assistant-sidecar-discard-pending (state pending)
  (when (%assistant-sidecar-clear-pending state pending)
    (loop
      (multiple-value-bind (event present-p closed-p)
          (cl-concurrent-kit:try-recv
           (assistant-pending-cell-events pending))
        (declare (ignore event closed-p))
        (unless present-p
          (return))))
    (%assistant-sidecar-close-channel
     (assistant-pending-cell-events pending))))

(defun %assistant-sidecar-stop-state (state)
  (setf (assistant-sidecar-state-starting-p state) nil)
  (let ((pending (%assistant-sidecar-current-pending state))
        (write-channel (assistant-sidecar-state-write-channel state))
        (handle (assistant-sidecar-state-handle state))
        (startup (%assistant-sidecar-start-thread state))
        (reader (assistant-sidecar-state-reader-thread state))
        (writer (assistant-sidecar-state-writer-thread state))
        (error-thread (assistant-sidecar-state-error-thread state)))
    (when pending
      (%assistant-sidecar-close-channel
       (assistant-pending-cell-events pending)))
    (%assistant-sidecar-close-channel write-channel)
    (when (and startup
               (not (eq startup sb-thread:*current-thread*)))
      (ignore-errors
       (sb-thread:join-thread startup :default nil :timeout 0.2))
      (when (sb-thread:thread-alive-p startup)
        (ignore-errors (sb-thread:terminate-thread startup))
        (ignore-errors
         (sb-thread:join-thread startup :default nil :timeout 0.2))))
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
          (assistant-sidecar-state-pending state) nil
          (assistant-sidecar-state-write-channel state) nil)
    (%assistant-sidecar-set-start-thread state nil)
  t))

(defparameter *assistant-sidecar-start-threads*
  (make-hash-table :test #'eq))

(defun %assistant-sidecar-start-thread (state)
  (gethash state *assistant-sidecar-start-threads*))

(defun %assistant-sidecar-set-start-thread (state thread)
  (if thread
      (setf (gethash state *assistant-sidecar-start-threads*) thread)
      (remhash state *assistant-sidecar-start-threads*)))

(defun %assistant-sidecar-start-worker (state pending)
  (multiple-value-bind (version version-status)
      (nshell.infrastructure.acl::run-sidecar-version-cancellable
       (assistant-sidecar-state-command state)
       (lambda () (not (assistant-sidecar-state-starting-p state))))
    (if (not (eq :ok version-status))
        (progn
          (setf (assistant-sidecar-state-starting-p state) nil
                (assistant-sidecar-state-disabled-reason state)
                  (list :version version-status))
          (%assistant-sidecar-publish
           pending
           (%assistant-sidecar-error-event
            (assistant-pending-cell-generation pending)
            (format nil "assistant sidecar version probe failed: ~a"
                    version-status)))
          (%assistant-sidecar-complete pending))
        (multiple-value-bind (handle spawn-status)
            (nshell.infrastructure.acl:spawn-sidecar
             (assistant-sidecar-state-command state)
             (or (assistant-sidecar-state-arguments state)
                 (assistant-sidecar-command-arguments))
             :input :stream :output :stream :error :stream)
          (if (null handle)
              (progn
                (setf (assistant-sidecar-state-starting-p state) nil
                      (assistant-sidecar-state-disabled-reason state)
                        (list :spawn spawn-status))
                (%assistant-sidecar-publish
                 pending
                 (%assistant-sidecar-error-event
                  (assistant-pending-cell-generation pending)
                  (format nil "assistant sidecar spawn failed: ~a"
                          spawn-status)))
                (%assistant-sidecar-complete pending))
              (let ((write-channel
                      (cl-concurrent-kit:make-channel :buffer-size 8)))
                (setf (assistant-sidecar-state-handle state) handle
                      (assistant-sidecar-state-version state) version
                      (assistant-sidecar-state-dead-p state) nil
                      (assistant-sidecar-state-dead-reason state) nil
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
                           (%assistant-sidecar-writer-loop state write-channel))
                         :name "nshell assistant sidecar writer")
                      (assistant-sidecar-state-error-thread state)
                        (sb-thread:make-thread
                         (lambda ()
                           (%assistant-sidecar-drain-error
                            (nshell.infrastructure.acl:sidecar-handle-error
                             handle)))
                         :name "nshell assistant sidecar error reader"))
                (let ((deadline (+ (get-internal-real-time)
                                   (round (* +assistant-sidecar-handshake-timeout-seconds+
                                             internal-time-units-per-second)))))
                  (loop
                  (multiple-value-bind (event present-p closed-p)
                      (cl-concurrent-kit:try-recv
                       (assistant-pending-cell-events pending))
                    (declare (ignore closed-p))
                    (when (or (not (assistant-sidecar-state-starting-p state))
                              present-p)
                      (when (and present-p
                                 (assistant-model-event-p event)
                                 (eq :system-init
                                     (assistant-model-event-kind event))
                                 (assistant-system-init-safe-p
                                  (assistant-model-event-payload event)))
                        (setf (assistant-sidecar-state-init-p state) t))
                      (when (and present-p
                                 (assistant-model-event-p event)
                                 (member (assistant-model-event-kind event)
                                         '(:stream-error :stream-ended)))
                        (return))
                      (when (or (assistant-sidecar-state-init-p state)
                                (not (assistant-sidecar-state-starting-p state)))
                        (return))))
                    (when (and (not present-p)
                               (>= (get-internal-real-time) deadline))
                      (return))
                    (sleep 0.01)))
                (if (assistant-sidecar-state-init-p state)
                    (progn
                      (setf (assistant-sidecar-state-starting-p state) nil
                            (assistant-sidecar-state-disabled-reason state) nil)
                      (%assistant-sidecar-publish
                       pending
                       (make-assistant-model-event
                        (assistant-pending-cell-generation pending)
                        :system-init nil))
                      (let ((payload
                              (shiftf
                               (assistant-pending-cell-request-payload pending)
                               nil)))
                        (when payload
                          (cl-concurrent-kit:try-send
                           write-channel
                           (%make-assistant-write-item
                            (assistant-pending-cell-generation pending)
                            payload))))
                    (progn
                      (setf (assistant-sidecar-state-starting-p state) nil
                            (assistant-sidecar-state-disabled-reason state)
                              :mcp-isolation-failed)
                      (%assistant-sidecar-publish
                       pending
                       (%assistant-sidecar-error-event
                        (assistant-pending-cell-generation pending)
                        "assistant sidecar init handshake failed"))
                      (%assistant-sidecar-complete pending)
                      (%assistant-sidecar-stop-state state))))))))))

(defun %assistant-sidecar-start (state)
  (if (null (assistant-sidecar-state-command state))
      (progn
        (setf (assistant-sidecar-state-starting-p state) nil
              (assistant-sidecar-state-disabled-reason state)
              :disabled-by-environment)
        nil)
      (if (and (assistant-sidecar-state-handle state)
           (assistant-sidecar-state-init-p state)
           (not (assistant-sidecar-state-dead-p state))
           (nshell.infrastructure.acl:sidecar-alive-p
            (assistant-sidecar-state-handle state)))
      t
          (progn
        (%assistant-sidecar-stop-state state)
        (setf (assistant-sidecar-state-starting-p state) t
              (assistant-sidecar-state-disabled-reason state) nil
              (assistant-sidecar-state-dead-p state) nil
              (assistant-sidecar-state-dead-reason state) nil)
        (let ((pending
                (%make-assistant-pending-cell
                 0
                 (cl-concurrent-kit:make-channel :buffer-size 128)
                 (cl-concurrent-kit:make-promise))))
          (%assistant-sidecar-set-pending state pending)
          (let ((thread (sb-thread:make-thread
                         (lambda ()
                           (unwind-protect
                                (%assistant-sidecar-start-worker state pending)
                             (%assistant-sidecar-set-start-thread state nil)))
                         :name "nshell assistant sidecar startup")))
            (%assistant-sidecar-set-start-thread state thread))
          t)))))

(defun %assistant-sidecar-request (state generation payload)
  (unless (and (assistant-sidecar-state-handle state)
               (assistant-sidecar-state-init-p state)
               (not (%assistant-sidecar-dead-p state)))
    (unless (%assistant-sidecar-start state)
      (return-from %assistant-sidecar-request nil)))
  (let ((handle (assistant-sidecar-state-handle state))
        (pending (%assistant-sidecar-current-pending state))
        (channel (assistant-sidecar-state-write-channel state)))
    (when (and pending (assistant-sidecar-state-starting-p state))
      (handler-case
          (let ((line (json-kit:stringify (json-kit:alist->json-object payload))))
            (unless (json-kit:parse line :object-type :alist)
              (return-from %assistant-sidecar-request nil))
            (setf (assistant-pending-cell-generation pending) generation
                  (assistant-pending-cell-request-payload pending) line)
            (return-from %assistant-sidecar-request t))
        (error () (return-from %assistant-sidecar-request nil))))
    (when (and pending
               (assistant-sidecar-state-init-p state)
               (zerop (assistant-pending-cell-generation pending)))
      (handler-case
          (let ((line (json-kit:stringify (json-kit:alist->json-object payload))))
            (unless (json-kit:parse line :object-type :alist)
              (return-from %assistant-sidecar-request nil))
            (setf (assistant-pending-cell-generation pending) generation)
            (return-from %assistant-sidecar-request
              (cl-concurrent-kit:try-send
               channel
               (%make-assistant-write-item generation line))))
        (error () (return-from %assistant-sidecar-request nil))))
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
                             '(:result :stream-ended :stream-error
                               :rate-limit-event)))
            (%assistant-sidecar-clear-pending state pending)
            (%assistant-sidecar-close-channel
             (assistant-pending-cell-events pending)))
          (values event present-p))
        (progn
          (when pending
            (%assistant-sidecar-discard-pending state pending))
          (values nil nil)))))

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
     :stop-fn (lambda () (%assistant-sidecar-stop state))
     :status-fn (lambda () (%assistant-sidecar-status state)))))
