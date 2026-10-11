(in-package #:nshell.feature.assistant)

(defun %assistant-event-kind (object)
  (let ((type (%assistant-object-field object "type"))
        (subtype (%assistant-object-field object "subtype")))
    (cond
      ((and (equal type "system") (equal subtype "init")) :system-init)
      ((equal type "assistant") :assistant)
      ((equal type "rate_limit_event") :rate-limit-event)
      ((equal type "result") :result)
      ((equal type "control_response") :control-response)
      ((equal type "user") :user)
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

(defun %assistant-sidecar-reader-pending (state handle generation)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (when (and (eql generation
                    (assistant-sidecar-state-startup-generation state))
               (eq handle (assistant-sidecar-state-handle state)))
      (let ((pending (assistant-sidecar-state-pending state)))
        (values pending
                (and pending (assistant-pending-cell-generation pending))
                t)))))

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
  (make-assistant-model-error-event generation message))

(defun %assistant-sidecar-reader-loop (state handle generation)
  (loop
    (multiple-value-bind (object status message)
        (%assistant-read-json-value
         (nshell.infrastructure.acl:sidecar-handle-output handle))
      (multiple-value-bind (pending pending-generation current-p)
          (%assistant-sidecar-reader-pending state handle generation)
        (unless current-p
          (return))
        (case status
          (:value
           (when pending
             (let ((kind (%assistant-event-kind object)))
               (cond
                 ((and (member kind '(:control-response :user))
                       (not (%assistant-sidecar-starting-p state))) nil)
                 ((eq kind :unknown)
                   (progn
                     (%assistant-sidecar-publish
                      pending
                      (%assistant-sidecar-error-event
                       pending-generation
                       "assistant sidecar returned an unknown event"))
                     (%assistant-sidecar-complete pending)))
                 (t (let ((event (make-assistant-model-event
                                 pending-generation
                                 kind
                                 object)))
                     (%assistant-sidecar-publish pending event)
                     (when (and (eq kind :result)
                                (not (%assistant-sidecar-starting-p state)))
                       (%assistant-sidecar-complete pending))))))))
          (:eof
           ;; Closing stdout does not imply process exit.  Use bounded stop
           ;; cleanup and settle the cell captured by its identity check.
           (multiple-value-bind (stopped-p stopped-pending)
               (%assistant-sidecar-stop-state
                state :preserve-pending-p t
                :expected-handle handle :expected-generation generation
                :dead-reason :reader-eof)
             (when (and stopped-p stopped-pending)
               (%assistant-sidecar-publish
                stopped-pending
                (%assistant-sidecar-error-event
                 (assistant-pending-cell-generation stopped-pending)
                 "assistant sidecar process exited before the pending request completed"))
               (%assistant-sidecar-complete stopped-pending)))
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
               pending-generation
               message))
             (%assistant-sidecar-complete pending))
           (return)))))))

(defun %assistant-sidecar-write-item (state item)
  (handler-case
      (let* ((handle (%assistant-sidecar-handle state))
             (stream (and handle
                          (nshell.infrastructure.acl:sidecar-handle-input handle))))
        (if (streamp stream)
            (sb-thread:with-mutex
                ((assistant-sidecar-state-write-lock state))
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
  (when (and thread
             (not (eq thread sb-thread:*current-thread*)))
    (ignore-errors
     (sb-thread:join-thread thread :default nil :timeout 0.1))
    (when (sb-thread:thread-alive-p thread)
      (ignore-errors (sb-thread:terminate-thread thread))
      (ignore-errors
       (sb-thread:join-thread thread :default nil :timeout 0.1)))))

(defun %assistant-sidecar-close-channel (channel)
  (when channel
    (ignore-errors (cl-concurrent-kit:close-channel channel))))

(defun %assistant-sidecar-drain-pending-events (pending)
  (loop
    (multiple-value-bind (event present-p closed-p)
        (cl-concurrent-kit:try-recv
         (assistant-pending-cell-events pending))
      (declare (ignore event closed-p))
      (unless present-p
        (return)))))

(defun %assistant-sidecar-retire-pending (state pending)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    ;; Only the most recently stopped turn can still be polled by the caller.
    (setf (assistant-sidecar-state-retired-pending state) (list pending))))

(defun %assistant-sidecar-terminate-pending (state pending reason)
  (when (and pending (%assistant-sidecar-clear-pending state pending))
    ;; A dead sidecar may have queued ordinary response events immediately
    ;; before EOF.  They must not hide the terminal failure that explains why
    ;; respawn replaced this pending request.
    (%assistant-sidecar-drain-pending-events pending)
    (%assistant-sidecar-publish
     pending
     (%assistant-sidecar-error-event
      (assistant-pending-cell-generation pending)
      reason))
    (%assistant-sidecar-complete pending)
    (%assistant-sidecar-retire-pending state pending)
    (%assistant-sidecar-close-channel
     (assistant-pending-cell-events pending))))

(defun %assistant-sidecar-stop-state (state &key preserve-pending-p preserve-starting-p
                                            (expected-handle nil expected-handle-p)
                                            expected-generation dead-reason)
  (let (pending write-channel handle startup reader writer error-thread stopping-generation)
    (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
      (when (and expected-handle-p
                 (not (and (eq expected-handle (assistant-sidecar-state-handle state))
                           (eql expected-generation
                                (assistant-sidecar-state-startup-generation state)))))
        (return-from %assistant-sidecar-stop-state nil))
      (when dead-reason
        (setf (assistant-sidecar-state-dead-p state) t
              (assistant-sidecar-state-dead-reason state) dead-reason))
      (unless preserve-starting-p
        (setf (assistant-sidecar-state-starting-p state) nil
              (assistant-sidecar-state-startup-generation state)
                (1+ (assistant-sidecar-state-startup-generation state))))
      (setf stopping-generation (assistant-sidecar-state-startup-generation state)
            pending (assistant-sidecar-state-pending state)
            write-channel (assistant-sidecar-state-write-channel state)
            handle (assistant-sidecar-state-handle state)
            startup (assistant-sidecar-state-start-thread state)
            reader (assistant-sidecar-state-reader-thread state)
            writer (assistant-sidecar-state-writer-thread state)
            error-thread (assistant-sidecar-state-error-thread state)))
    (unless preserve-pending-p
      (%assistant-sidecar-terminate-pending
       state pending "assistant sidecar stopped before the pending request completed"))
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
    (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
      (when (and (eq handle (assistant-sidecar-state-handle state))
                 (eql stopping-generation
                      (assistant-sidecar-state-startup-generation state)))
        (setf (assistant-sidecar-state-handle state) nil
              (assistant-sidecar-state-init-p state) nil
              (assistant-sidecar-state-reader-thread state) nil
              (assistant-sidecar-state-writer-thread state) nil
              (assistant-sidecar-state-error-thread state) nil
              (assistant-sidecar-state-write-channel state) nil
              (assistant-sidecar-state-start-thread state) nil)))
    (values t pending)))

(defun %assistant-sidecar-start-thread (state)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (assistant-sidecar-state-start-thread state)))

(defun %assistant-sidecar-set-start-thread (state thread)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (setf (assistant-sidecar-state-start-thread state) thread)))

(defun %assistant-sidecar-generation-current-p (state generation)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (eql generation (assistant-sidecar-state-startup-generation state))))

(defun %assistant-sidecar-set-start-failure (state generation reason)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (when (eql generation (assistant-sidecar-state-startup-generation state))
      (setf (assistant-sidecar-state-starting-p state) nil
            (assistant-sidecar-state-disabled-reason state) reason)
      t)))

(defun %assistant-sidecar-install-threads (state generation handle version
                                             write-channel)
  (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
    (when (eql generation (assistant-sidecar-state-startup-generation state))
      (setf (assistant-sidecar-state-handle state) handle
            (assistant-sidecar-state-version state) version
            (assistant-sidecar-state-dead-p state) nil
            (assistant-sidecar-state-dead-reason state) nil
            (assistant-sidecar-state-write-channel state) write-channel
            (assistant-sidecar-state-reader-thread state)
              (sb-thread:make-thread
               (lambda ()
                 (%assistant-sidecar-reader-loop state handle generation))
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
                  (nshell.infrastructure.acl:sidecar-handle-error handle)))
               :name "nshell assistant sidecar error reader"))
      t)))

(defun %assistant-sidecar-init-handshake (state pending)
  ;; Claude emits its isolation manifest only after receiving user input.
  ;; Bootstrap with no user context, interrupt that turn, and consume its
  ;; terminal response before allowing the queued request onto the stream.
  (%assistant-sidecar-write-item
   state (%make-assistant-write-item
          (assistant-pending-cell-generation pending)
          "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"\"}}"))
  (let ((deadline (+ (get-internal-real-time)
                     (round (* +assistant-sidecar-handshake-timeout-seconds+
                               internal-time-units-per-second))))
        (safe-p nil)
        (interrupted-p nil)
        (finished-p nil))
    (loop
      (unless (%assistant-sidecar-starting-p state)
        (return nil))
      (multiple-value-bind (event present-p closed-p)
          (cl-concurrent-kit:try-recv (assistant-pending-cell-events pending))
        (declare (ignore closed-p))
        (when (and present-p (assistant-model-event-p event))
          (case (assistant-model-event-kind event)
            (:system-init
             (unless (and (not safe-p)
                          (assistant-system-init-safe-p
                           (assistant-model-event-payload event)))
               (return nil))
             (setf safe-p t)
             (%assistant-sidecar-write-item
              state (%make-assistant-write-item
                     (assistant-pending-cell-generation pending)
                     "{\"type\":\"control_request\",\"request_id\":\"nshell-bootstrap-interrupt\",\"request\":{\"subtype\":\"interrupt\"}}")))
            (:control-response
             (let ((response (%assistant-object-field
                              (assistant-model-event-payload event) "response")))
               (unless (and safe-p
                            (equal (%assistant-object-field response "request_id")
                                   "nshell-bootstrap-interrupt")
                            (equal (%assistant-object-field response "subtype")
                                   "success"))
                 (return nil))
               (setf interrupted-p t)))
            (:result
             (unless safe-p (return nil))
             (setf finished-p t))
            ((:stream-error :stream-ended) (return nil))))
        (when (and safe-p interrupted-p finished-p)
          (return t))
        (when (>= (get-internal-real-time) deadline)
          (return nil))
        (unless present-p (sleep 0.01))))))

(defun %assistant-sidecar-start-worker (state pending startup-generation)
  (progn
    (multiple-value-bind (version version-status)
      (let ((cached-version
              (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                (assistant-sidecar-state-version state)))
            (command (assistant-sidecar-state-command state)))
        (if cached-version
            (values cached-version :ok)
            (nshell.infrastructure.acl:run-sidecar-version-cancellable
             command
             (lambda () (not (%assistant-sidecar-starting-p state))))))
    (if (or (not (eq :ok version-status))
            (not (%assistant-sidecar-generation-current-p
                  state startup-generation)))
        (progn
          (%assistant-sidecar-set-start-failure
           state startup-generation (list :version version-status))
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
                (%assistant-sidecar-set-start-failure
                 state startup-generation (list :spawn spawn-status))
                (%assistant-sidecar-publish
                 pending
                 (%assistant-sidecar-error-event
                  (assistant-pending-cell-generation pending)
                  (format nil "assistant sidecar spawn failed: ~a"
                          spawn-status)))
                (%assistant-sidecar-complete pending))
              (if (not (%assistant-sidecar-generation-current-p
                        state startup-generation))
                  (nshell.infrastructure.acl:stop-sidecar handle)
                  (let ((write-channel
                          (cl-concurrent-kit:make-channel :buffer-size 8)))
                    (unless (%assistant-sidecar-install-threads
                             state startup-generation handle version write-channel)
                      (%assistant-sidecar-close-channel write-channel)
                      (return-from %assistant-sidecar-start-worker
                        (nshell.infrastructure.acl:stop-sidecar handle)))
                    (when (%assistant-sidecar-init-handshake state pending)
                      (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                        (when (eql startup-generation
                                   (assistant-sidecar-state-startup-generation state))
                          (setf (assistant-sidecar-state-init-p state) t))))
                    (unless (%assistant-sidecar-generation-current-p
                             state startup-generation)
                      (return-from %assistant-sidecar-start-worker nil))
                    (if (%assistant-sidecar-init-p state)
                    (progn
                      (let ((payload nil))
                        (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                          (setf (assistant-sidecar-state-starting-p state) nil
                                (assistant-sidecar-state-disabled-reason state) nil
                                payload
                                  (shiftf
                                   (assistant-pending-cell-request-payload pending)
                                   nil)))
                      (%assistant-sidecar-publish
                       pending
                       (make-assistant-model-event
                        (assistant-pending-cell-generation pending)
                        :system-init nil))
                        (when payload
                          (%assistant-sidecar-write-item
                           state
                           (%make-assistant-write-item
                            (assistant-pending-cell-generation pending)
                            payload)))))
                    (progn
                      (%assistant-sidecar-set-start-failure
                       state startup-generation :mcp-isolation-failed)
                      (%assistant-sidecar-publish
                       pending
                       (%assistant-sidecar-error-event
                        (assistant-pending-cell-generation pending)
                        "assistant sidecar init handshake failed"))
                      (%assistant-sidecar-complete pending)
                      (%assistant-sidecar-stop-state state
                                                     :preserve-pending-p t)))))))))))

(defun %assistant-sidecar-start (state)
  (let ((startup-generation
          (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
            (cond
              ((assistant-sidecar-state-starting-p state) :already-starting)
              ((and (assistant-sidecar-state-init-p state)
                    (not (assistant-sidecar-state-dead-p state))
                    (assistant-sidecar-state-handle state)
                    (nshell.infrastructure.acl:sidecar-alive-p
                     (assistant-sidecar-state-handle state))) :already-starting)
              ((null (assistant-sidecar-state-command state))
               (setf (assistant-sidecar-state-disabled-reason state)
                     :disabled-by-environment)
               :disabled)
              (t
               (setf (assistant-sidecar-state-starting-p state) t
                     (assistant-sidecar-state-disabled-reason state) nil
                     (assistant-sidecar-state-dead-p state) nil
                     (assistant-sidecar-state-dead-reason state) nil)
               (incf (assistant-sidecar-state-startup-generation state)))))))
    (case startup-generation
      (:already-starting t)
      (:disabled nil)
      (otherwise
       (let ((handle (%assistant-sidecar-handle state))
             (init-p (%assistant-sidecar-init-p state))
             (dead-p (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                       (assistant-sidecar-state-dead-p state))))
         (if (and handle init-p (not dead-p)
                  (nshell.infrastructure.acl:sidecar-alive-p handle))
             (progn
               (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                 (setf (assistant-sidecar-state-starting-p state) nil))
               t)
             (progn
               (let ((handoff-complete-p nil))
                 (unwind-protect
                      (progn
                        (%assistant-sidecar-stop-state state :preserve-starting-p t)
                        (let ((pending
                                (%make-assistant-pending-cell
                                 0
                                 (cl-concurrent-kit:make-channel :buffer-size 128)
                                 (cl-concurrent-kit:make-promise))))
                          (%assistant-sidecar-set-pending state pending)
                          (let ((thread (sb-thread:make-thread
                                         (lambda ()
                                           (unwind-protect
                                                (%assistant-sidecar-start-worker
                                                 state pending startup-generation)
                                             (%assistant-sidecar-set-start-thread
                                              state nil)))
                                         :name "nshell assistant sidecar startup")))
                            (%assistant-sidecar-set-start-thread state thread)
                            (setf handoff-complete-p t)))
                        t)
                   (unless handoff-complete-p
                     (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                       (when (eql startup-generation
                                  (assistant-sidecar-state-startup-generation state))
                         (setf (assistant-sidecar-state-starting-p state) nil)))))))))))))

(defun %assistant-sidecar-request (state generation payload)
  (let ((handle (%assistant-sidecar-handle state))
        (init-p (%assistant-sidecar-init-p state)))
    (unless (and handle
                 init-p
               (not (%assistant-sidecar-dead-p state)))
      (unless (%assistant-sidecar-start state)
        (return-from %assistant-sidecar-request nil)))
    ;; START may replace a dead handle asynchronously.  Refresh the snapshot
    ;; before deciding whether this request belongs to the startup queue.
    (setf handle (%assistant-sidecar-handle state)
          init-p (%assistant-sidecar-init-p state))
    (let ((pending (%assistant-sidecar-current-pending state)))
    (when (and pending (%assistant-sidecar-starting-p state))
      (handler-case
          (let ((line (json-kit:stringify (%assistant-json-value payload))))
            (unless (json-kit:parse line :object-type :alist)
              (return-from %assistant-sidecar-request nil))
            (let ((send-now-p nil))
              (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                (setf (assistant-pending-cell-generation pending) generation
                      (assistant-pending-cell-request-payload pending) line)
                (when (and (assistant-sidecar-state-init-p state)
                           (not (assistant-sidecar-state-starting-p state)))
                  (setf (assistant-pending-cell-request-payload pending) nil
                        send-now-p t)))
              (when send-now-p
                (%assistant-sidecar-write-item
                 state
                 (%make-assistant-write-item generation line))))
            (return-from %assistant-sidecar-request t))
        (error () (return-from %assistant-sidecar-request nil))))
    (when (and pending
               (%assistant-sidecar-init-p state)
               (zerop (assistant-pending-cell-generation pending)))
      (handler-case
          (let ((line (json-kit:stringify (%assistant-json-value payload))))
            (unless (json-kit:parse line :object-type :alist)
              (return-from %assistant-sidecar-request nil))
            (let ((send-now-p nil))
              (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                (setf (assistant-pending-cell-generation pending) generation
                      (assistant-pending-cell-request-payload pending) nil
                      send-now-p t))
              (when send-now-p
                (%assistant-sidecar-write-item
                 state
                 (%make-assistant-write-item generation line)))
              (return-from %assistant-sidecar-request t)))
        (error () (return-from %assistant-sidecar-request nil))))
    (if (and handle
             (%assistant-sidecar-init-p state)
             (not (%assistant-sidecar-dead-p state))
             (null pending))
        (handler-case
            (let* ((object (%assistant-json-value payload))
                   (line (json-kit:stringify object)))
              (unless (json-kit:parse line :object-type :alist)
                (return-from %assistant-sidecar-request nil))
              (let ((new-pending
                      (%make-assistant-pending-cell
                       generation
                       (cl-concurrent-kit:make-channel :buffer-size 128)
                       (cl-concurrent-kit:make-promise))))
                (%assistant-sidecar-set-pending state new-pending)
                (let ((channel
                        (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                          (assistant-sidecar-state-write-channel state))))
                  (if (and channel
                           (cl-concurrent-kit:try-send
                            channel
                            (%make-assistant-write-item generation line)))
                    t
                    (progn
                      (%assistant-sidecar-clear-pending state new-pending)
                      (%assistant-sidecar-close-channel
                       (assistant-pending-cell-events new-pending))
                      nil)))))
          (error () nil))
        nil))))

(defun %assistant-sidecar-poll (state generation)
  (let* ((current (%assistant-sidecar-current-pending state))
         (pending current))
    (when (and pending
               (eql generation (assistant-pending-cell-generation pending))
               (%assistant-sidecar-starting-p state))
      (return-from %assistant-sidecar-poll (values nil nil)))
    (unless (and pending
                 (eql generation (assistant-pending-cell-generation pending)))
      (setf pending
            (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
              (find generation
                    (assistant-sidecar-state-retired-pending state)
                    :key #'assistant-pending-cell-generation
                    :test #'eql))))
    (if (and pending
             (eql generation (assistant-pending-cell-generation pending)))
        (multiple-value-bind (event present-p closed-p)
            (cl-concurrent-kit:try-recv
             (assistant-pending-cell-events pending))
          (declare (ignore closed-p))
          (when (and present-p (assistant-model-event-p event))
            (let ((rejected-p
                    (and (eq (assistant-model-event-kind event) :rate-limit-event)
                         (equal "rejected"
                                (%assistant-object-field
                                 (%assistant-object-field
                                  (assistant-model-event-payload event) "rate_limit_info")
                                 "status")))))
              (when (or rejected-p
                        (member (assistant-model-event-kind event)
                                '(:result :stream-ended :stream-error)))
                (if (eq pending (%assistant-sidecar-current-pending state))
                    (progn
                      ;; A rejected turn can still emit a result.  Retire its
                      ;; process before allowing another request to use it.
                      (when rejected-p
                        (%assistant-sidecar-stop-state state :preserve-pending-p t))
                      (%assistant-sidecar-clear-pending state pending))
                    (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
                      (setf (assistant-sidecar-state-retired-pending state)
                            (delete pending
                                    (assistant-sidecar-state-retired-pending state)
                                    :test #'eq))))
                (when rejected-p
                  (%assistant-sidecar-complete pending))
                (%assistant-sidecar-close-channel
                 (assistant-pending-cell-events pending)))))
          (values event present-p))
        (progn
          (when (and current
                     (> generation (assistant-pending-cell-generation current))
                     (not (%assistant-sidecar-starting-p state)))
            ;; A stopped turn must lose its process, not just its event queue:
            ;; otherwise its late response could be assigned to the next turn.
            (%assistant-sidecar-stop-state state))
          (values nil nil)))))

(defun %assistant-sidecar-stop (state)
  (%assistant-sidecar-stop-state state))

(defun %assistant-sidecar-outcome (ok state)
  (values ok
          (unless ok
            (sb-thread:with-mutex ((assistant-sidecar-state-lock state))
              (assistant-sidecar-state-disabled-reason state)))))

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
