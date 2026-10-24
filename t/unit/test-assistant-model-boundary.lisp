(in-package #:nshell/test)

(describe "assistant-sidecar-payload-regressions"
  (dolist (phase '(:starting :initialized :ready))
    (let ((phase phase))
      (it (format nil "serializes-the-real-user-payload-in-~A" phase)
        (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
               (channel (cl-concurrent-kit:make-channel :buffer-size 8))
               (pending (unless (eq phase :ready)
                          (nshell.feature.assistant::%make-assistant-pending-cell
                           0 (cl-concurrent-kit:make-channel :buffer-size 8)
                           (cl-concurrent-kit:make-promise))))
               (payload (nshell.feature.assistant:make-assistant-user-payload
                         "Propose pwd."
                         :context (nshell.feature.assistant:make-assistant-context
                                   :command "pwd" :exit 0 :cwd "/fixture"
                                   :environment-names '("PATH"))))
               (line nil))
          (setf (nshell.feature.assistant::assistant-sidecar-state-pending state) pending
                (nshell.feature.assistant::assistant-sidecar-state-starting-p state)
                  (eq phase :starting)
                (nshell.feature.assistant::assistant-sidecar-state-init-p state)
                  (not (eq phase :starting))
                (nshell.feature.assistant::assistant-sidecar-state-handle state) :fixture
                (nshell.feature.assistant::assistant-sidecar-state-write-channel state) channel)
          (with-temporary-functions
              (('nshell.feature.assistant::%assistant-sidecar-dead-p
                (lambda (current) (declare (ignore current)) nil))
               ('nshell.feature.assistant::%assistant-sidecar-start
                (lambda (current) (declare (ignore current)) t))
               ('nshell.feature.assistant::%assistant-sidecar-write-item
                (lambda (current item)
                  (declare (ignore current))
                  (setf line (nshell.feature.assistant::assistant-write-item-line item)))))
            (expect t :to-be
                    (nshell.feature.assistant::%assistant-sidecar-request state 41 payload)))
          (cond ((eq phase :starting)
                 (expect nil :to-be line)
                 (setf line (nshell.feature.assistant::assistant-pending-cell-request-payload
                             pending)))
                ((eq phase :ready)
                 (multiple-value-bind (item present-p) (cl-concurrent-kit:try-recv channel)
                   (expect t :to-be present-p)
                   (setf line (nshell.feature.assistant::assistant-write-item-line item)))))
          (let* ((object (json-kit:parse line :object-type :alist :array-type :list))
                 (message (cdr (assoc "message" object :test #'string=)))
                 (context (cdr (assoc "context" object :test #'string=))))
            (expect "user" :to-equal (cdr (assoc "role" message :test #'string=)))
            (expect "Propose pwd." :to-equal (cdr (assoc "content" message :test #'string=)))
            (expect "/fixture" :to-equal (cdr (assoc "cwd" context :test #'string=)))
            (expect '("PATH") :to-equal
                    (cdr (assoc "environment-names" context :test #'string=)))))))))

(describe "assistant-sidecar-cancel-regressions"
  (it "stops-a-stale-active-request-before-accepting-another"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (pending (nshell.feature.assistant::%make-assistant-pending-cell
                     1 (cl-concurrent-kit:make-channel :buffer-size 8)
                     (cl-concurrent-kit:make-promise)))
           (stopped nil))
      (setf (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
      (with-temporary-function
          ('nshell.feature.assistant::%assistant-sidecar-stop-state
           (lambda (current &rest options)
             (declare (ignore options))
             (setf stopped t)
             (nshell.feature.assistant::%assistant-sidecar-clear-pending current pending)))
        (multiple-value-bind (event present-p)
            (nshell.feature.assistant::%assistant-sidecar-poll state 2)
          (expect nil :to-be event)
          (expect nil :to-be present-p)))
      (expect t :to-be stopped)
      (expect nil :to-be
              (nshell.feature.assistant::%assistant-sidecar-current-pending state))))
  (it "does-not-cancel-a-new-request-while-polling-a-retired-request"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (current (nshell.feature.assistant::%make-assistant-pending-cell
                     2 (cl-concurrent-kit:make-channel :buffer-size 8)
                     (cl-concurrent-kit:make-promise)))
           (retired (nshell.feature.assistant::%make-assistant-pending-cell
                     1 (cl-concurrent-kit:make-channel :buffer-size 8)
                     (cl-concurrent-kit:make-promise))))
      (setf (nshell.feature.assistant::assistant-sidecar-state-pending state) current
            (nshell.feature.assistant::assistant-sidecar-state-retired-pending state)
              (list retired))
      (cl-concurrent-kit:send
       (nshell.feature.assistant::assistant-pending-cell-events retired)
       (nshell.feature.assistant:make-assistant-model-error-event 1 "cancelled"))
      (multiple-value-bind (event present-p)
          (nshell.feature.assistant::%assistant-sidecar-poll state 1)
        (expect t :to-be present-p)
        (expect :stream-error :to-be
                (nshell.feature.assistant:assistant-model-event-kind event)))
      (expect current :to-be
              (nshell.feature.assistant::%assistant-sidecar-current-pending state)))))

(defun %assistant-stop-sidecar (handle)
  (funcall (symbol-function 'nshell.infrastructure.acl:stop-sidecar) handle))

(defun %assistant-test-sidecar-script (&optional one-shot-p received-path unsafe-init)
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-sidecar-~D.sh"
                       (get-internal-real-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (%assistant-test-write-bootstrap-fixture stream unsafe-init)
      (when received-path
        (write-line
         (format nil "  printf '%s\\n' \"$line\" >> '~a'"
                 (namestring received-path))
         stream))
      (dolist (line
                '("  printf '%s\\n' '{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}}'"
                  "  printf '%s\\n' '{\"type\":\"result\",\"subtype\":\"success\",\"structured_output\":{\"command\":\"pwd\",\"reason\":\"fixture\",\"risk\":\"low\"}}'"))
        (write-line line stream))
      (when one-shot-p
        (write-line "  exit 0" stream))
      (write-line "done" stream))
    (sb-posix:chmod (namestring path) #o700)
    path))

(defun %assistant-test-write-bootstrap-fixture (stream &optional unsafe-init)
  (dolist (line
            '("#!/bin/sh"
              "if [ \"$1\" = \"--version\" ]; then"
              "  printf '%s\\n' 'test-version'"
              "  exit 0"
              "fi"
              "request_count=0"
              "while IFS= read -r line"
              "do"
              "  case \"$line\" in"
              "    *'\"request_id\":\"nshell-bootstrap-interrupt\"'*)"
              "      printf '%s\\n' '{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"nshell-bootstrap-interrupt\",\"response\":{\"still_queued\":[]}}}'"
              "      printf '%s\\n' '{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[]}}'"
              "      printf '%s\\n' '{\"type\":\"result\",\"subtype\":\"error_during_execution\",\"is_error\":true}'"
              "      continue ;;"
              "    *'\"content\":\"\"'*)"))
    (write-line line stream))
  (when unsafe-init
    (write-line (format nil "      printf '%s\\n' '~a'" unsafe-init) stream))
  (dolist (line
            '("      printf '%s\\n' '{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"StructuredOutput\"],\"mcp_servers\":[]}'"
              "      continue ;;"
              "  esac"))
    (write-line line stream)))

(defun %assistant-test-rate-sidecar-script ()
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-rate-~D.sh" (get-internal-real-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (%assistant-test-write-bootstrap-fixture stream)
      (dolist (line
                '("  request_count=$((request_count + 1))"
                  "  printf '%s\\n' '{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"allowed\"}}'"
                  "  printf '%s\\n' \"{\\\"type\\\":\\\"result\\\",\\\"subtype\\\":\\\"success\\\",\\\"structured_output\\\":{\\\"command\\\":\\\"pwd\\\",\\\"reason\\\":\\\"request-$request_count\\\",\\\"risk\\\":\\\"low\\\"}}\""
                  "done"))
        (write-line line stream)))
    (sb-posix:chmod (namestring path) #o700)
    path))

(defun %assistant-test-rejecting-sidecar-script ()
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-rejecting-sidecar-~D.sh"
                       (get-universal-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (dolist (line
                '("#!/bin/sh"
                  "if [ \"$1\" = \"--version\" ]; then"
                  "  printf '%s\\n' 'test-version'"
                  "  exit 0"
                  "fi"
                  "printf '%s\\n' '{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"Bash\"],\"mcp_servers\":[]}'"
                  "while :"
                  "do"
                  "  sleep 1"
                  "done"))
        (write-line line stream)))
    (sb-posix:chmod (namestring path) #o700)
    path))

(defun %assistant-test-pending-sidecar-script ()
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-pending-sidecar-~D.sh"
                       (get-universal-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (%assistant-test-write-bootstrap-fixture stream)
      (dolist (line
                '("  while :; do sleep 1; done"
                  "done"))
        (write-line line stream)))
    (sb-posix:chmod (namestring path) #o700)
    path))

(defun %assistant-test-hanging-version-sidecar-script ()
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-hanging-version-~D.sh"
                       (get-universal-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (dolist (line '("#!/bin/sh"
                      "while :; do sleep 1; done"))
        (write-line line stream)))
    (sb-posix:chmod (namestring path) #o700)
    path))

(defun %assistant-test-term-ignoring-sidecar-script ()
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-term-ignoring-~D.sh"
                       (get-universal-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (dolist (line '("#!/bin/sh"
                      "trap '' TERM"
                      "while :; do sleep 1; done"))
        (write-line line stream)))
    (sb-posix:chmod (namestring path) #o700)
    path))

(defun %assistant-test-failing-version-sidecar-script ()
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-failing-version-~D.sh"
                       (get-universal-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (dolist (line '("#!/bin/sh"
                      "printf '%s\\n' 'version probe stdout'"
                      "printf '%s\\n' 'version probe stderr' >&2"
                      "exit 17"))
        (write-line line stream)))
    (sb-posix:chmod (namestring path) #o700)
    path))

(defun %assistant-test-live-thread-named-p (name)
  (some (lambda (thread)
          (and (equal name (sb-thread:thread-name thread))
               (sb-thread:thread-alive-p thread)))
        (sb-thread:list-all-threads)))

(defmacro %assistant-test-with-sidecar-cleanup (context &body body)
  `(let ((nshell.feature.assistant:*assistant-boundaries* ,context))
     (unwind-protect
          (progn ,@body)
       (ignore-errors
         (nshell.feature.assistant:assistant-model-stop))
       (let ((deadline (+ (get-internal-real-time)
                          (round (* 2 internal-time-units-per-second)))))
         (dolist (name '("nshell assistant sidecar startup"
                         "nshell assistant sidecar reader"
                         "nshell assistant sidecar writer"
                         "nshell assistant sidecar error reader"))
           (loop while (and (%assistant-test-live-thread-named-p name)
                            (< (get-internal-real-time) deadline))
                 do (sleep 0.01)))))))

(defun %assistant-test-await-state (state &optional (timeout-seconds 12))
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second))))
        (status nil))
    (loop while (< (get-internal-real-time) deadline)
          do (setf status (nshell.feature.assistant:assistant-model-status))
             (when (eq state (getf status :state))
               (return status))
             (sleep 0.05))
    status))

(defun %assistant-test-terminal-event-description (event)
  (let* ((kind (nshell.feature.assistant:assistant-model-event-kind event))
         (payload (nshell.feature.assistant:assistant-model-event-payload event))
         (message (or (cdr (assoc "message" payload :test #'string=))
                      (cdr (assoc "reason" payload :test #'string=)))))
    (format nil "kind=~S message=~S payload=~S" kind message payload)))

(defun %assistant-test-init-sequence (unsafe-init)
  (let* ((script (%assistant-test-sidecar-script nil nil unsafe-init))
         (state (nshell.feature.assistant::%make-assistant-sidecar-state
                 (namestring script) nil))
         (events (cl-concurrent-kit:make-channel :buffer-size 128))
         (completion (cl-concurrent-kit:make-promise))
         (pending (nshell.feature.assistant::%make-assistant-pending-cell
                   0 events completion))
         (write-item (symbol-function
                      'nshell.feature.assistant::%assistant-sidecar-write-item))
         (install-threads (symbol-function
                           'nshell.feature.assistant::%assistant-sidecar-install-threads))
         (forwarded nil)
         (threads nil))
    (unwind-protect
         (progn
           (setf (nshell.feature.assistant::assistant-sidecar-state-starting-p state) t
                 (nshell.feature.assistant::assistant-sidecar-state-startup-generation state) 1
                 (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
           (expect t :to-be
                   (nshell.feature.assistant::%assistant-sidecar-request
                    state 41
                    (nshell.feature.assistant:make-assistant-user-payload "init-sequence")))
           ;; Run the gate synchronously, but keep the real process and IO threads.
           (with-temporary-function
               ('nshell.feature.assistant::%assistant-sidecar-write-item
                (lambda (current item)
                  (let* ((line (nshell.feature.assistant::assistant-write-item-line item))
                         (object (json-kit:parse line :object-type :alist))
                         (message (cdr (assoc "message" object :test #'string=)))
                         (content (cdr (assoc "content" message :test #'string=))))
                    (when (and (stringp content) (plusp (length content)))
                      (push line forwarded)))
                  (funcall write-item current item)))
             (with-temporary-function
                 ('nshell.feature.assistant::%assistant-sidecar-install-threads
                  (lambda (current generation handle version channel)
                    (prog1 (funcall install-threads current generation handle version channel)
                      (setf threads
                            (list (nshell.feature.assistant::assistant-sidecar-state-reader-thread current)
                                  (nshell.feature.assistant::assistant-sidecar-state-writer-thread current)
                                  (nshell.feature.assistant::assistant-sidecar-state-error-thread current))))))
               (nshell.feature.assistant::%assistant-sidecar-start-worker
                state pending 1)))
           (if unsafe-init
               (progn
                 (expect :mcp-isolation-failed :to-be
                         (nshell.feature.assistant::assistant-sidecar-state-disabled-reason state))
                 (expect nil :to-be forwarded)
                 (expect nil :to-be
                         (nshell.feature.assistant::assistant-sidecar-state-init-p state)))
               (progn
                 (expect nil :to-be
                         (nshell.feature.assistant::assistant-sidecar-state-disabled-reason state))
                 (expect t :to-be
                         (nshell.feature.assistant::assistant-sidecar-state-init-p state))
                 (expect 1 :to-be (length forwarded))
                 (expect "init-sequence" :to-equal
                         (cdr (assoc "content"
                                     (cdr (assoc "message"
                                                 (json-kit:parse (first forwarded) :object-type :alist)
                                                 :test #'string=))
                                     :test #'string=)))))
           (let ((terminal nil))
             (loop repeat 8
                   until terminal
                   do (multiple-value-bind (event present-p)
                          (cl-concurrent-kit:recv
                           events :timeout (cl-date-kit:duration-of-seconds 2))
                        (expect t :to-be present-p)
                        (expect 41 :to-be
                                (nshell.feature.assistant:assistant-model-event-generation event))
                        (when (member
                               (nshell.feature.assistant:assistant-model-event-kind event)
                               '(:result :stream-error :stream-ended))
                          (setf terminal event))))
             (expect (if unsafe-init :stream-error :result) :to-be
                     (nshell.feature.assistant:assistant-model-event-kind terminal))
             (when unsafe-init
               (expect "assistant sidecar init handshake failed" :to-equal
                       (cdr (assoc "message"
                                   (nshell.feature.assistant:assistant-model-event-payload terminal)
                                   :test #'string=)))))
           (expect t :to-be
                   (cl-concurrent-kit:await
                    completion :timeout (cl-date-kit:duration-of-seconds 2)))
           (expect t :to-be (cl-concurrent-kit:promise-settled-p completion))
           (expect nil :to-be
                   (nshell.feature.assistant::assistant-sidecar-state-starting-p state))
           (unless unsafe-init
             (nshell.feature.assistant::%assistant-sidecar-stop-state state))
           (dolist (accessor
                     '(nshell.feature.assistant::assistant-sidecar-state-handle
                       nshell.feature.assistant::assistant-sidecar-state-reader-thread
                       nshell.feature.assistant::assistant-sidecar-state-writer-thread
                       nshell.feature.assistant::assistant-sidecar-state-error-thread
                       nshell.feature.assistant::assistant-sidecar-state-start-thread
                       nshell.feature.assistant::assistant-sidecar-state-write-channel))
             (expect nil :to-be (funcall accessor state)))
           (dolist (thread threads)
             (when thread
               (expect nil :to-be (sb-thread:thread-alive-p thread)))))
      (nshell.feature.assistant::%assistant-sidecar-stop-state state)
      (nshell.feature.assistant::%assistant-sidecar-close-channel events)
      (when (probe-file script)
        (delete-file script)))))

(defun %assistant-test-async-init-sequence (unsafe-init)
  (with-temporary-output-file (received-path :prefix "nshell-assistant-init-received-")
    (with-open-file (stream received-path :direction :output :if-exists :supersede)
      (declare (ignore stream)))
    (let* ((script (%assistant-test-sidecar-script t received-path unsafe-init))
           (state (nshell.feature.assistant::%make-assistant-sidecar-state
                   (namestring script) nil))
           (installed (cl-concurrent-kit:make-channel :buffer-size 1))
           (release (cl-concurrent-kit:make-channel :buffer-size 1))
           (install-threads (symbol-function
                             'nshell.feature.assistant::%assistant-sidecar-install-threads))
           (pending nil)
           (handle nil)
           (write-channel nil)
           (threads nil))
      (unwind-protect
           (with-temporary-function
               ('nshell.feature.assistant::%assistant-sidecar-install-threads
                (lambda (current generation current-handle version channel)
                  (let ((ok (funcall install-threads current generation
                                     current-handle version channel)))
                    (when ok
                      (setf handle current-handle
                            write-channel channel
                            threads
                            (list (nshell.feature.assistant::assistant-sidecar-state-reader-thread current)
                                  (nshell.feature.assistant::assistant-sidecar-state-writer-thread current)
                                  (nshell.feature.assistant::assistant-sidecar-state-error-thread current)))
                      ;; Hold the real startup gate until the real request is queued.
                      (cl-concurrent-kit:send installed t)
                      (cl-concurrent-kit:recv
                       release :timeout (cl-date-kit:duration-of-seconds 2)))
                    ok)))
             (unwind-protect
                  (progn
                    (expect t :to-be (nshell.feature.assistant::%assistant-sidecar-start state))
                    (multiple-value-bind (value present-p)
                        (cl-concurrent-kit:recv
                         installed :timeout (cl-date-kit:duration-of-seconds 2))
                      (expect t :to-be present-p)
                      (expect t :to-be value))
                    (push (nshell.feature.assistant::assistant-sidecar-state-start-thread state)
                          threads)
                    (setf pending (nshell.feature.assistant::%assistant-sidecar-current-pending state))
                    (expect t :to-be
                            (nshell.feature.assistant::%assistant-sidecar-request
                             state 41
                             (nshell.feature.assistant:make-assistant-user-payload
                              "async-init-sequence"
                              :context (nshell.feature.assistant:make-assistant-context
                                        :command "pwd" :exit 0 :cwd "/fixture"
                                        :environment-names '("PATH")))))
                    (expect 41 :to-be
                            (nshell.feature.assistant::assistant-pending-cell-generation pending))
                    (multiple-value-bind (event present-p)
                        (nshell.feature.assistant::%assistant-sidecar-poll state 41)
                      (expect nil :to-be event)
                      (expect nil :to-be present-p))
                    (cl-concurrent-kit:send release t)
                    (expect t :to-be
                            (cl-concurrent-kit:await
                             (nshell.feature.assistant::assistant-pending-cell-completion pending)
                             :timeout (cl-date-kit:duration-of-seconds 2)))
                    (dolist (thread threads)
                      (expect t :to-be (not (null thread)))
                      (multiple-value-bind (value problem)
                          (sb-thread:join-thread thread :timeout 2 :default nil)
                        (declare (ignore value))
                        (expect nil :to-be (eq :timeout problem)))
                      (expect nil :to-be (sb-thread:thread-alive-p thread)))
                    (let ((received (uiop:read-file-lines received-path)))
                      (expect (if unsafe-init 0 1) :to-be (length received))
                      (unless unsafe-init
                        (let* ((object (json-kit:parse (first received)
                                                     :object-type :alist :array-type :list))
                               (message (cdr (assoc "message" object :test #'string=)))
                               (context (cdr (assoc "context" object :test #'string=))))
                          (expect "user" :to-equal
                                  (cdr (assoc "role" message :test #'string=)))
                          (expect "async-init-sequence" :to-equal
                                  (cdr (assoc "content" message :test #'string=)))
                          (expect "/fixture" :to-equal
                                  (cdr (assoc "cwd" context :test #'string=)))
                          (expect '("PATH") :to-equal
                                  (cdr (assoc "environment-names" context :test #'string=))))))
                    (let ((terminal nil))
                      (loop repeat 8
                            until terminal
                            do (multiple-value-bind (event present-p)
                                   (nshell.feature.assistant::%assistant-sidecar-poll state 41)
                                 (expect t :to-be present-p)
                                 (when (member (nshell.feature.assistant:assistant-model-event-kind event)
                                               '(:result :stream-error :stream-ended))
                                   (setf terminal event))))
                      (expect (if unsafe-init :stream-error :result) :to-be
                              (nshell.feature.assistant:assistant-model-event-kind terminal))
                      (expect 41 :to-be
                              (nshell.feature.assistant:assistant-model-event-generation terminal))
                      (when unsafe-init
                        (expect "assistant sidecar init handshake failed" :to-equal
                                (cdr (assoc "message"
                                            (nshell.feature.assistant:assistant-model-event-payload terminal)
                                            :test #'string=)))))
                    ;; All assertions precede the explicit stop in unwind cleanup.
                    (expect (if unsafe-init :mcp-isolation-failed nil) :to-be
                            (nshell.feature.assistant::assistant-sidecar-state-disabled-reason state))
                    (dolist (accessor
                              '(nshell.feature.assistant::assistant-sidecar-state-pending
                                nshell.feature.assistant::assistant-sidecar-state-retired-pending
                                nshell.feature.assistant::assistant-sidecar-state-handle
                                nshell.feature.assistant::assistant-sidecar-state-init-p
                                nshell.feature.assistant::assistant-sidecar-state-starting-p
                                nshell.feature.assistant::assistant-sidecar-state-start-thread
                                nshell.feature.assistant::assistant-sidecar-state-reader-thread
                                nshell.feature.assistant::assistant-sidecar-state-writer-thread
                                nshell.feature.assistant::assistant-sidecar-state-error-thread
                                nshell.feature.assistant::assistant-sidecar-state-write-channel))
                      (expect nil :to-be (funcall accessor state)))
                    (expect t :to-be
                            (cl-concurrent-kit:promise-settled-p
                             (nshell.feature.assistant::assistant-pending-cell-completion pending)))
                    (expect t :to-be
                            (cl-concurrent-kit:channel-closed-p
                             (nshell.feature.assistant::assistant-pending-cell-events pending)))
                    (expect t :to-be (cl-concurrent-kit:channel-closed-p write-channel))
                    (expect nil :to-be
                            (sb-ext:process-alive-p
                             (nshell.infrastructure.acl:sidecar-handle-process handle))))
               (cl-concurrent-kit:try-send release t)
               (nshell.feature.assistant::%assistant-sidecar-stop-state state)))
        (nshell.feature.assistant::%assistant-sidecar-close-channel installed)
        (nshell.feature.assistant::%assistant-sidecar-close-channel release)
        (when pending
          (nshell.feature.assistant::%assistant-sidecar-close-channel
           (nshell.feature.assistant::assistant-pending-cell-events pending)))
        (when (probe-file script)
          (delete-file script))))))

(describe "assistant-model-init-sequence"
  (it "rejects-unsafe-init-before-a-later-safe-init"
    (dolist (unsafe-init
              '("{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"Bash\"],\"mcp_servers\":[]}"
                "{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"StructuredOutput\"],\"mcp_servers\":[{\"name\":\"unexpected\"}]}"
                "{\"type\":\"system\",\"subtype\":\"init\"}"))
      (%assistant-test-init-sequence unsafe-init)))
  (it "accepts-safe-init-and-forwards-the-queued-request"
    (%assistant-test-init-sequence nil))
  (it "rejects-init-missing-only-tools-before-a-later-safe-init"
    (%assistant-test-async-init-sequence
     "{\"type\":\"system\",\"subtype\":\"init\",\"mcp_servers\":[]}"))
  (it "rejects-init-missing-only-mcp-servers-before-a-later-safe-init"
    (%assistant-test-async-init-sequence
     "{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"StructuredOutput\"]}"))
  (it "cleans-up-rejected-async-startup-through-normal-terminal-poll"
    (dolist (unsafe-init
              '("{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"Bash\"],\"mcp_servers\":[]}"
                "{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"StructuredOutput\"],\"mcp_servers\":[{\"name\":\"unexpected\"}]}"
                "{\"type\":\"system\",\"subtype\":\"init\"}"))
      (%assistant-test-async-init-sequence unsafe-init)))
  (it "receives-one-valid-request-and-cleans-up-through-normal-terminal-poll"
    (%assistant-test-async-init-sequence nil)))

(describe "assistant-model-boundary-contracts"
  (it "replays-a-sanitized-stream-json-fixture-through-the-injected-boundary"
    (with-temporary-output-file (fixture-path :prefix "nshell-assistant-fixture-")
      (write-test-lines
       fixture-path
       '("{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[],\"mcp_servers\":[],\"model\":\"fixture\",\"claude_code_version\":\"fixture\"}"
         "{\"type\":\"assistant\",\"message\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"fixture response\"}]}}"
         "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"allowed\"}}"
         "{\"type\":\"result\",\"subtype\":\"success\",\"num_turns\":1,\"duration_ms\":5,\"duration_api_ms\":5,\"total_cost_usd\":0.0,\"usage\":{\"input_tokens\":4,\"output_tokens\":4},\"result\":\"{\\\"command\\\":\\\"pwd\\\",\\\"reason\\\":\\\"fixture\\\",\\\"risk\\\":\\\"low\\\"}\",\"structured_output\":{\"command\":\"pwd\",\"reason\":\"fixture\",\"risk\":\"low\"}}"))
      (multiple-value-bind (boundary error-message)
          (nshell.feature.assistant:make-assistant-fixture-boundary fixture-path)
        (expect nil :to-be error-message)
        (let ((nshell.feature.assistant:*assistant-boundaries*
                (nshell.feature.assistant:make-assistant-boundary-context boundary)))
          (expect :ok :to-be
                  (nshell.feature.assistant:assistant-boundary-status
                   (nshell.feature.assistant:assistant-model-start)))
          (let ((init-result (nshell.feature.assistant:assistant-model-poll 0)))
            (expect :event :to-be
                    (nshell.feature.assistant:assistant-boundary-status init-result))
            (let ((event (nshell.feature.assistant:assistant-boundary-value init-result)))
              (expect :system-init :to-be
                      (nshell.feature.assistant:assistant-model-event-kind event))
              (expect 0 :to-be
                      (nshell.feature.assistant:assistant-model-event-generation event))))
          (expect :ok :to-be
                  (nshell.feature.assistant:assistant-boundary-status
                   (nshell.feature.assistant:assistant-model-request
                    1 '(("message" . "hello")))))
          (let ((kinds nil)
                (result nil))
            (loop for polled = (nshell.feature.assistant:assistant-model-poll 1)
                  while (eq :event
                            (nshell.feature.assistant:assistant-boundary-status polled))
                  do (let ((event (nshell.feature.assistant:assistant-boundary-value polled)))
                       (push (nshell.feature.assistant:assistant-model-event-kind event)
                             kinds)
                       (when (eq :result
                                 (nshell.feature.assistant:assistant-model-event-kind event))
                         (setf result event))))
            (expect '(:result :rate-limit-event :assistant) :to-equal kinds)
            (expect 1 :to-be
                    (nshell.feature.assistant:assistant-model-event-generation result))
            (expect "pwd" :to-equal
                    (cdr (assoc "command"
                                (cdr (assoc "structured_output"
                                            (nshell.feature.assistant:assistant-model-event-payload result)
                                            :test #'string=))
                                :test #'string=))))))))

  (it "marks-a-fixture-without-a-result-as-stream-ended"
    (with-temporary-output-file (fixture-path :prefix "nshell-assistant-fixture-")
      (write-test-lines
       fixture-path
       '("{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[],\"mcp_servers\":[],\"model\":\"fixture\",\"claude_code_version\":\"fixture\"}"
         "{\"type\":\"assistant\",\"message\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"partial fixture response\"}]}}"))
      (multiple-value-bind (boundary error-message)
          (nshell.feature.assistant:make-assistant-fixture-boundary fixture-path)
        (expect nil :to-be error-message)
        (let ((nshell.feature.assistant:*assistant-boundaries*
                (nshell.feature.assistant:make-assistant-boundary-context boundary)))
          (nshell.feature.assistant:assistant-model-start)
          (nshell.feature.assistant:assistant-model-poll 0)
          (nshell.feature.assistant:assistant-model-request 7 nil)
          (let ((kinds nil))
            (loop for polled = (nshell.feature.assistant:assistant-model-poll 7)
                  while (eq :event
                            (nshell.feature.assistant:assistant-boundary-status polled))
                  do (push
                      (nshell.feature.assistant:assistant-model-event-kind
                       (nshell.feature.assistant:assistant-boundary-value polled))
                      kinds))
            (expect :stream-ended :to-be (first kinds))))))))

  (it "terminates-an-unknown-fixture-event"
    (with-temporary-output-file (fixture-path :prefix "nshell-assistant-unknown-")
      (write-test-lines
       fixture-path
       '("{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[],\"mcp_servers\":[]}"
         "{\"type\":\"future_event\"}"))
      (multiple-value-bind (boundary error-message)
          (nshell.feature.assistant:make-assistant-fixture-boundary fixture-path)
        (expect nil :to-be error-message)
        (let ((nshell.feature.assistant:*assistant-boundaries*
                (nshell.feature.assistant:make-assistant-boundary-context boundary)))
          (nshell.feature.assistant:assistant-model-start)
          (nshell.feature.assistant:assistant-model-poll 0)
          (nshell.feature.assistant:assistant-model-request 1 nil)
          (let ((event-result (nshell.feature.assistant:assistant-model-poll 1)))
            (expect :event :to-be
                    (nshell.feature.assistant:assistant-boundary-status event-result))
            (expect :stream-error :to-be
                    (nshell.feature.assistant:assistant-model-event-kind
                     (nshell.feature.assistant:assistant-boundary-value event-result))))))))

  (it "accepts-only-structured-output-tools-and-empty-mcp-servers"
    (expect t :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system")
               ("subtype" . "init")
               ("tools")
               ("mcp_servers"))))
    (expect t :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system")
               ("subtype" . "init")
               ("tools" "StructuredOutput")
               ("mcp_servers"))))
    (expect nil :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system")
               ("subtype" . "init")
               ("tools" "StructuredOutput" "Bash")
               ("mcp_servers"))))
    (expect nil :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system")
               ("subtype" . "init")
               ("tools" "Bash")
               ("mcp_servers"))))
    (expect nil :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system")
               ("subtype" . "init")
               ("tools" "StructuredOutput")
               ("mcp_servers" "git"))))
    (expect nil :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system") ("subtype" . "init")))))

  (it "reports-a-failure-status-when-start-or-request-returns-nil"
    (let ((boundary (nshell.feature.assistant:make-assistant-model-boundary
                     :start-fn (lambda () nil)
                     :request-fn (lambda (generation payload) nil)
                     :poll-fn (lambda (generation) (values nil nil))
                     :stop-fn (lambda () t))))
      (expect :unavailable :to-be
              (nshell.feature.assistant:assistant-boundary-status
               (nshell.feature.assistant:assistant-boundary-start boundary)))
      (expect :unavailable :to-be
              (nshell.feature.assistant:assistant-boundary-status
               (nshell.feature.assistant:assistant-boundary-request boundary 1 nil)))))

  (it "builds-a-sidecar-command-with-strict-mcp-isolation"
    (let ((arguments (nshell.feature.assistant:assistant-sidecar-command-arguments)))
      (expect (member "--strict-mcp-config" arguments :test #'string=)
              :to-be-truthy)
      (expect (not (null (member "--append-system-prompt" arguments
                                 :test #'string=)))
              :to-be t)
      (expect (not (null (member "--json-schema" arguments :test #'string=)))
              :to-be t)
      (expect nil :to-be (member "--safe-mode" arguments :test #'string=))
      (let ((effort (member "--effort" arguments :test #'string=)))
        (expect t :to-be (not (null effort)))
        (expect "low" :to-equal (second effort)))
      (expect nil :to-be (member "--model" arguments :test #'string=)))
    (let ((arguments (nshell.feature.assistant:assistant-sidecar-command-arguments
                      '(:model "sonnet"))))
      (expect "sonnet" :to-equal
              (second (member "--model" arguments :test #'string=)))
      (expect "low" :to-equal
              (second (member "--effort" arguments :test #'string=)))))

  (it "captures-pending-generation-with-reader-pending-state"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state
                   nil nil))
           (handle (gensym "HANDLE-"))
           (pending (nshell.feature.assistant::%make-assistant-pending-cell
                     17 nil nil)))
      (setf (nshell.feature.assistant::assistant-sidecar-state-handle state)
            handle
            (nshell.feature.assistant::assistant-sidecar-state-pending state)
            pending)
      (multiple-value-bind (actual actual-generation)
          (nshell.feature.assistant::%assistant-sidecar-reader-pending
           state handle 0)
        (expect t :to-be (eq pending actual))
        (expect 17 :to-be actual-generation))))

  (it "handles-reader-eof-after-poll-clears-pending"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (handle (nshell.infrastructure.acl::%make-sidecar-handle
                    nil nil nil (make-string-input-stream "") nil :stopped))
           (pending (nshell.feature.assistant::%make-assistant-pending-cell
                     17 (cl-concurrent-kit:make-channel :buffer-size 2)
                     (cl-concurrent-kit:make-promise))))
      (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) handle
            (nshell.feature.assistant::assistant-sidecar-state-init-p state) t
            (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
      (nshell.feature.assistant::%assistant-sidecar-publish
       pending (nshell.feature.assistant::make-assistant-model-event 17 :result nil))
      (multiple-value-bind (event present-p)
          (nshell.feature.assistant::%assistant-sidecar-poll state 17)
        (expect t :to-be present-p)
        (expect :result :to-be
                (nshell.feature.assistant:assistant-model-event-kind event)))
      (expect nil :to-be
              (nshell.feature.assistant::assistant-sidecar-state-pending state))
      (nshell.feature.assistant::%assistant-sidecar-reader-loop state handle 0)
      (expect t :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-p state))
      (expect :reader-eof :to-be
              (nshell.feature.assistant::assistant-sidecar-state-dead-reason state))
      (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))))

  (it "keeps-idle-reader-through-values-until-eof"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (stream (make-string-input-stream
                    (format nil "{\"type\":\"system\"}~%{\"type\":\"system\"}~%")))
           (handle (nshell.infrastructure.acl::%make-sidecar-handle
                    nil nil nil stream nil :stopped)))
      (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) handle)
      (nshell.feature.assistant::%assistant-sidecar-reader-loop state handle 0)
      (expect :eof :to-be (read-char stream nil :eof))
      (expect t :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-p state))
      (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))))

  (it "ignores-reader-eof-from-stale-handle-or-generation"
    (dolist (stale-part '(:handle :generation))
      (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
             (handle (nshell.infrastructure.acl::%make-sidecar-handle
                      nil nil nil (make-string-input-stream "") nil :stopped))
             (active (if (eq stale-part :handle) (gensym "ACTIVE-") handle))
             (generation (if (eq stale-part :generation) 1 0))
             (pending (nshell.feature.assistant::%make-assistant-pending-cell 17 nil nil)))
        (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) active
              (nshell.feature.assistant::assistant-sidecar-state-startup-generation state) generation
              (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
        (nshell.feature.assistant::%assistant-sidecar-reader-loop state handle 0)
        (expect active :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))
        (expect generation :to-be
                (nshell.feature.assistant::assistant-sidecar-state-startup-generation state))
        (expect pending :to-be (nshell.feature.assistant::assistant-sidecar-state-pending state))
        (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-p state)))))

  (it "rechecks-reader-identity-after-eof-read"
    (dolist (changed-part '(:handle :generation))
      (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
             (handle (nshell.infrastructure.acl::%make-sidecar-handle
                      nil nil nil (make-string-input-stream "") nil :stopped))
             (active (if (eq changed-part :handle)
                         (nshell.infrastructure.acl::%make-sidecar-handle
                          nil nil nil (make-string-input-stream "") nil :stopped)
                         handle))
             (generation (if (eq changed-part :generation) 1 0))
             (pending (nshell.feature.assistant::%make-assistant-pending-cell
                       17 (cl-concurrent-kit:make-channel :buffer-size 2)
                       (cl-concurrent-kit:make-promise))))
        (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) handle
              (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
        (with-temporary-function
            ('nshell.feature.assistant::%assistant-read-json-value
             (lambda (stream)
               (declare (ignore stream))
               (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) active
                     (nshell.feature.assistant::assistant-sidecar-state-startup-generation state)
                     generation)
               (values nil :eof nil)))
          (nshell.feature.assistant::%assistant-sidecar-reader-loop state handle 0))
        (expect active :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))
        (expect generation :to-be
                (nshell.feature.assistant::assistant-sidecar-state-startup-generation state))
        (expect pending :to-be (nshell.feature.assistant::assistant-sidecar-state-pending state))
        (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-p state))
        (expect nil :to-be
                (cl-concurrent-kit:promise-settled-p
                 (nshell.feature.assistant::assistant-pending-cell-completion pending)))
        (cl-concurrent-kit:close-channel
         (nshell.feature.assistant::assistant-pending-cell-events pending)))))

  (it "settles-request-accepted-while-reader-reads-eof"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (handle (nshell.infrastructure.acl::%make-sidecar-handle
                    nil nil nil (make-string-input-stream "") nil :stopped))
           (writes (cl-concurrent-kit:make-channel :buffer-size 2))
           (pending nil)
           (accepted-p nil)
           (queued-generation nil)
           (read-calls 0))
      (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) handle
            (nshell.feature.assistant::assistant-sidecar-state-init-p state) t
            (nshell.feature.assistant::assistant-sidecar-state-write-channel state) writes)
      (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-pending state))
      (unwind-protect
           (progn
             (with-temporary-function
                   ('nshell.feature.assistant::%assistant-read-json-value
                    (lambda (stream)
                      (declare (ignore stream))
                      (incf read-calls)
                      (setf accepted-p
                            (with-temporary-function
                                ('nshell.infrastructure.acl:sidecar-alive-p
                                 (lambda (candidate)
                                   (expect handle :to-be candidate)
                                   t))
                              (nshell.feature.assistant::%assistant-sidecar-request
                               state 17 '(("type" . "user") ("message" . "pwd"))))
                            pending (nshell.feature.assistant::assistant-sidecar-state-pending state))
                      (multiple-value-bind (item present-p)
                          (cl-concurrent-kit:try-recv writes)
                        (when present-p
                          (setf queued-generation
                                (nshell.feature.assistant::assistant-write-item-generation item))))
                      (values nil :eof nil)))
                 (nshell.feature.assistant::%assistant-sidecar-reader-loop state handle 0))
             (expect 1 :to-be read-calls)
             (expect t :to-be accepted-p)
             (expect 17 :to-be queued-generation)
             (expect t :to-be
                     (and pending
                          (cl-concurrent-kit:promise-settled-p
                           (nshell.feature.assistant::assistant-pending-cell-completion pending))))
             (multiple-value-bind (event present-p)
                 (nshell.feature.assistant::%assistant-sidecar-poll state 17)
               (expect t :to-be present-p)
               (when present-p
                 (expect :stream-error :to-be
                         (nshell.feature.assistant::assistant-model-event-kind event))
                 (expect 17 :to-be
                         (nshell.feature.assistant::assistant-model-event-generation event))))
             (expect t :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-p state))
             (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state)))
        (cl-concurrent-kit:close-channel writes)
        (when pending
          (cl-concurrent-kit:close-channel
           (nshell.feature.assistant::assistant-pending-cell-events pending))))))

  (it "preserves-new-reader-identity-during-eof-cleanup"
    (dolist (changed-part '(:handle :generation))
      (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
             (handle (nshell.infrastructure.acl::%make-sidecar-handle
                      nil nil nil (make-string-input-stream "") nil :stopped))
             (active (if (eq changed-part :handle)
                         (nshell.infrastructure.acl::%make-sidecar-handle
                          nil nil nil (make-string-input-stream "") nil :stopped)
                         handle))
             (generation (if (eq changed-part :generation) 2 1))
             (writes (cl-concurrent-kit:make-channel :buffer-size 2))
             (thread sb-thread:*current-thread*)
             (pending (nshell.feature.assistant::%make-assistant-pending-cell
                       17 (cl-concurrent-kit:make-channel :buffer-size 2)
                       (cl-concurrent-kit:make-promise))))
        (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) handle
              (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
        (with-temporary-function
            ('nshell.infrastructure.acl:stop-sidecar
             (lambda (stopped)
               (expect handle :to-be stopped)
               (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) active
                     (nshell.feature.assistant::assistant-sidecar-state-startup-generation state) generation
                     (nshell.feature.assistant::assistant-sidecar-state-init-p state) t
                     (nshell.feature.assistant::assistant-sidecar-state-dead-p state) nil
                     (nshell.feature.assistant::assistant-sidecar-state-write-channel state) writes
                     (nshell.feature.assistant::assistant-sidecar-state-reader-thread state) thread
                     (nshell.feature.assistant::assistant-sidecar-state-writer-thread state) thread
                     (nshell.feature.assistant::assistant-sidecar-state-error-thread state) thread
                     (nshell.feature.assistant::assistant-sidecar-state-start-thread state) thread)))
          (nshell.feature.assistant::%assistant-sidecar-reader-loop state handle 0))
        (expect active :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))
        (expect generation :to-be
                (nshell.feature.assistant::assistant-sidecar-state-startup-generation state))
        (expect t :to-be (nshell.feature.assistant::assistant-sidecar-state-init-p state))
        (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-p state))
        (expect writes :to-be
                (nshell.feature.assistant::assistant-sidecar-state-write-channel state))
        (expect thread :to-be
                (nshell.feature.assistant::assistant-sidecar-state-reader-thread state))
        (expect thread :to-be
                (nshell.feature.assistant::assistant-sidecar-state-writer-thread state))
        (expect thread :to-be
                (nshell.feature.assistant::assistant-sidecar-state-error-thread state))
        (expect thread :to-be
                (nshell.feature.assistant::assistant-sidecar-state-start-thread state))
        (expect t :to-be (cl-concurrent-kit:try-send writes :replacement))
        (cl-concurrent-kit:close-channel writes)
        (cl-concurrent-kit:close-channel
         (nshell.feature.assistant::assistant-pending-cell-events pending)))))

  (it "clears-starting-state-when-startup-handoff-fails"
    (let ((state (nshell.feature.assistant::%make-assistant-sidecar-state
                  "/bin/false" nil))
          (stop-calls 0))
      (unwind-protect
           (with-temporary-function
               ('nshell.feature.assistant::%assistant-sidecar-stop-state
                (lambda (state &key preserve-pending-p preserve-starting-p)
                  (declare (ignore state preserve-pending-p preserve-starting-p))
                  (incf stop-calls)
                  (when (= stop-calls 1)
                    (error "injected startup handoff failure"))))
             (expect t :to-be
                     (handler-case
                         (progn
                           (nshell.feature.assistant::%assistant-sidecar-start state)
                           nil)
                       (error () t)))
             (expect nil :to-be
                     (nshell.feature.assistant::%assistant-sidecar-starting-p state))
             (expect t :to-be
                     (nshell.feature.assistant::%assistant-sidecar-start state))
             (expect 2 :to-be stop-calls))
        (ignore-errors
          (nshell.feature.assistant::%assistant-sidecar-stop-state state)))))

  (it "disables-sidecar-when-requested-by-environment"
    (let ((old-value (host-kit:getenv "NSHELL_AI_DISABLE")))
      (unwind-protect
           (progn
             (sb-posix:setenv "NSHELL_AI_DISABLE" "1" 1)
             (let* ((boundary (nshell.feature.assistant:make-assistant-sidecar-boundary
                               :command "/bin/false"))
                    (nshell.feature.assistant:*assistant-boundaries*
                      (nshell.feature.assistant:make-assistant-boundary-context boundary))
                    (result (nshell.feature.assistant:assistant-model-start)))
               (expect :unavailable :to-be
                       (nshell.feature.assistant:assistant-boundary-status result))
               (expect :unavailable :to-be
                       (getf (nshell.feature.assistant:assistant-model-status)
                             :state))
               (expect "NSHELL_AI_DISABLE is set" :to-equal
                       (getf (nshell.feature.assistant:assistant-model-status)
                             :reason))))
        (if old-value
            (sb-posix:setenv "NSHELL_AI_DISABLE" old-value 1)
            (sb-posix:unsetenv "NSHELL_AI_DISABLE")))))

  (it "times-out-a-sidecar-that-hangs-during-version-probe"
    (let ((script (%assistant-test-hanging-version-sidecar-script))
          (context nil))
      (unwind-protect
           (let* ((boundary (nshell.feature.assistant:make-assistant-sidecar-boundary
                             :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context boundary)))
                  (result (nshell.feature.assistant:assistant-model-start))
                  (status nil))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status result))
             (setf status (%assistant-test-await-state :unavailable))
             (expect :unavailable :to-be (getf status :state))
             (expect t :to-be (stringp (getf status :reason)))
             (expect nil :to-be
                     (search (string #\Newline) (getf status :reason)))
             (nshell.feature.assistant:assistant-model-stop))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script)))))

  (it "reports-version-probe-output-when-the-sidecar-exits-with-an-error"
    (let ((script (%assistant-test-failing-version-sidecar-script))
          (context nil))
      (unwind-protect
           (let* ((boundary (nshell.feature.assistant:make-assistant-sidecar-boundary
                             :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context boundary)))
                  (result (nshell.feature.assistant:assistant-model-start))
                  (status nil)
                  (reason nil))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status result))
             (setf status (%assistant-test-await-state :unavailable)
                   reason (getf status :reason))
             (expect :unavailable :to-be (getf status :state))
             (expect (search "version probe stdout" reason) :to-be-truthy)
             (expect (search "version probe stderr" reason) :to-be-truthy)
             (expect (search "17" reason)
                     :to-be-truthy)
             (nshell.feature.assistant:assistant-model-stop))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script)))))

  (it "starts-sidecar-in-its-own-group-without-shell-registration"
    (let ((foreground-pgid nshell.infrastructure.acl::*foreground-pgid*)
          (registry-count (hash-table-count nshell.presentation::*proc-registry*)))
      (multiple-value-bind (handle status)
          (nshell.infrastructure.acl:spawn-sidecar
           "cat" nil :input :stream :output :stream :error :stream)
        (unwind-protect
             (progn
               (expect :started :to-be status)
               (let ((pid (nshell.infrastructure.acl:sidecar-handle-pgid handle)))
                 (expect (plusp pid) :to-be-truthy)
                 (expect pid :to-be (sb-posix:getpgid pid)))
               (expect foreground-pgid :to-be nshell.infrastructure.acl::*foreground-pgid*)
               (expect registry-count :to-be
                       (hash-table-count nshell.presentation::*proc-registry*)))
          (when handle
            (%assistant-stop-sidecar handle))))))

  (it "streams-sidecar-values-through-reader-and-writer-threads"
    (let ((script (%assistant-test-sidecar-script))
          (context nil))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context
                           boundary)))
                  (start (nshell.feature.assistant:assistant-model-start)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status start))
             (expect t :to-be
                     (nshell.feature.assistant:assistant-boundary-value start))
             (expect :ready :to-be
                     (getf (%assistant-test-await-state :ready) :state))
             (let ((request
                     (nshell.feature.assistant:assistant-model-request
                      7 '(("message" . "hello")))))
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status request)))
             (let ((result nil))
               (loop repeat 100
                     until result
                     do (let ((polled (nshell.feature.assistant:assistant-model-poll 7)))
                          (when (eq :event
                                    (nshell.feature.assistant:assistant-boundary-status
                                     polled))
                            (let ((event
                                    (nshell.feature.assistant:assistant-boundary-value
                                     polled)))
                              (when (eq :result
                                        (nshell.feature.assistant:assistant-model-event-kind
                                         event))
                                (setf result event))))
                          (unless result
                            (sleep 0.01))))
               (expect :result :to-be
                       (nshell.feature.assistant:assistant-model-event-kind result))
               (expect 7 :to-be
                       (nshell.feature.assistant:assistant-model-event-generation result)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-stop))))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script)))))

  (it "discards-a-stale-sidecar-pending-before-the-next-request"
    (with-temporary-output-file (received-path :prefix "nshell-assistant-received-")
      (let ((script (%assistant-test-sidecar-script nil received-path))
            (context nil))
        (unwind-protect
             (let* ((boundary
                      (nshell.feature.assistant:make-assistant-sidecar-boundary
                       :command (namestring script)))
                    (nshell.feature.assistant:*assistant-boundaries*
                      (setf context
                            (nshell.feature.assistant:make-assistant-boundary-context
                             boundary))))
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-start)))
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-request
                         1 '(("message" . "stale")))))
               (expect :empty :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-poll 2)))
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-request
                         2 '(("message" . "fresh")))))
               (let ((deadline (+ (get-internal-real-time)
                                  (round (* 2 internal-time-units-per-second))))
                     (received ""))
                 (loop while (and (not (search "fresh" received))
                                  (< (get-internal-real-time) deadline))
                       do (setf received
                                 (if (probe-file received-path)
                                     (uiop:read-file-string received-path)
                                     ""))
                          (sleep 0.01))
                 (expect nil :to-be (search "stale" received))
                 (expect (search "fresh" received) :to-be-truthy))
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-stop))))
          (%assistant-test-with-sidecar-cleanup context)
          (when (probe-file script)
            (delete-file script))))))

  (it "kills-a-sidecar-that-ignores-sigterm"
    (let ((script (%assistant-test-term-ignoring-sidecar-script))
          (handle nil))
      (unwind-protect
           (multiple-value-bind (started-handle status)
               (nshell.infrastructure.acl:spawn-sidecar
                (namestring script) nil
                :input :stream :output :stream :error :stream)
             (setf handle started-handle)
             (expect :started :to-be status)
             (expect t :to-be
                     (nshell.infrastructure.acl:process-alive-p
                      (nshell.infrastructure.acl::sidecar-handle-process handle)))
             (expect t :to-be (%assistant-stop-sidecar handle))
             (expect nil :to-be
                     (nshell.infrastructure.acl:process-alive-p
                      (nshell.infrastructure.acl::sidecar-handle-process handle))))
        (when handle
          (%assistant-stop-sidecar handle))
        (when (probe-file script)
          (delete-file script)))))

  (it "respawns-sidecar-after-reader-detects-process-death"
    (let ((script (%assistant-test-sidecar-script t))
          (context nil))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context
                           boundary)))
                  (start (nshell.feature.assistant:assistant-model-start)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status start))
             (expect :ready :to-be
                     (getf (%assistant-test-await-state :ready) :state))
             (flet ((await-result (generation)
                      (let ((request
                              (nshell.feature.assistant:assistant-model-request
                               generation '(("message" . "hello")))))
                        (expect :ok :to-be
                                (nshell.feature.assistant:assistant-boundary-status
                                 request)))
                      (let ((result nil)
                            (failure nil))
                        (loop repeat 1200
                              until (or result failure)
                              do (let ((polled
                                         (nshell.feature.assistant:assistant-model-poll
                                          generation)))
                                   (when (eq :event
                                             (nshell.feature.assistant:assistant-boundary-status
                                              polled))
                                     (let ((event
                                             (nshell.feature.assistant:assistant-boundary-value
                                              polled)))
                                       (let ((kind
                                               (nshell.feature.assistant:assistant-model-event-kind
                                                event)))
                                         (cond
                                           ((eq :result kind)
                                            (setf result event))
                                           ((member kind
                                                    '(:stream-error :stream-ended
                                                      :rate-limit-event))
                                            (setf failure
                                                  (format nil
                                                          "assistant model ended before result: ~A"
                                                          (%assistant-test-terminal-event-description
                                                           event))))))))
                                   (unless (or result failure)
                                     (sleep 0.01))))
                        (cond
                          (failure
                           (expect nil :to-be failure))
                          (result
                           (expect generation :to-be
                                   (nshell.feature.assistant:assistant-model-event-generation
                                    result)))
                          (t
                           (expect nil :to-be
                                   "assistant model result did not arrive: no event received"))))))
               (await-result 1)
               (expect :dead :to-be
                       (getf (%assistant-test-await-state :dead) :state))
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-start)))
               (await-result 2)
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-stop))))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script))))))

(defun %assistant-test-await-sidecar-ready (state)
  (loop repeat 200
        until (and (nshell.feature.assistant::assistant-sidecar-state-init-p state)
                   (not (nshell.feature.assistant::assistant-sidecar-state-starting-p state)))
        do (sleep 0.01))
  (expect t :to-be (nshell.feature.assistant::assistant-sidecar-state-init-p state))
  (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-starting-p state))
  (let ((init-event nil))
    (loop repeat 200
          until init-event
          do (multiple-value-bind (event present-p)
                 (nshell.feature.assistant::%assistant-sidecar-poll state 0)
               (when present-p (setf init-event event))
               (unless init-event (sleep 0.01))))
    (expect :system-init :to-be
            (nshell.feature.assistant:assistant-model-event-kind init-event))
    (expect 0 :to-be
            (nshell.feature.assistant:assistant-model-event-generation init-event))))

(defun %assistant-test-await-sidecar-result (state generation &key allowed-rate-p)
  (let ((pending (nshell.feature.assistant::%assistant-sidecar-current-pending state))
        (rate-count 0)
        (result nil))
    (loop repeat 200
          until result
          do (multiple-value-bind (event present-p)
                 (nshell.feature.assistant::%assistant-sidecar-poll state generation)
               (when present-p
                 (expect generation :to-be
                         (nshell.feature.assistant:assistant-model-event-generation event))
                 (case (nshell.feature.assistant:assistant-model-event-kind event)
                   (:rate-limit-event
                    (incf rate-count)
                    (expect "allowed" :to-equal
                            (cdr (assoc "status"
                                        (cdr (assoc "rate_limit_info"
                                                    (nshell.feature.assistant:assistant-model-event-payload event)
                                                    :test #'string=))
                                        :test #'string=)))
                    (expect pending :to-be
                            (nshell.feature.assistant::%assistant-sidecar-current-pending state)))
                   (:result (setf result event))
                   ((:stream-error :stream-ended)
                    (expect :result :to-be
                            (nshell.feature.assistant:assistant-model-event-kind event)))))
               (unless result (sleep 0.01))))
    (expect (if allowed-rate-p 1 0) :to-be rate-count)
    (expect :result :to-be (nshell.feature.assistant:assistant-model-event-kind result))
    (expect "success" :to-equal
            (cdr (assoc "subtype"
                        (nshell.feature.assistant:assistant-model-event-payload result)
                        :test #'string=)))
    (expect nil :to-be (nshell.feature.assistant::%assistant-sidecar-current-pending state))
    result))

(describe "assistant-sidecar-lifecycle-regressions"
  (it "stops-rejected-turn-before-releasing-pending-and-isolates-late-results"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (handle (nshell.infrastructure.acl:spawn-sidecar
                    "sleep" '("30") :input :stream :output :stream :error :stream))
           (pending (nshell.feature.assistant::%make-assistant-pending-cell
                     91 (cl-concurrent-kit:make-channel :buffer-size 4)
                     (cl-concurrent-kit:make-promise)))
           (rejected (nshell.feature.assistant::make-assistant-model-event
                      91 :rate-limit-event
                      '(("rate_limit_info" . (("status" . "rejected"))))))
           (late (nshell.feature.assistant::make-assistant-model-event 91 :result nil))
           (writes (cl-concurrent-kit:make-channel :buffer-size 2)))
      (unwind-protect
           (progn
             (expect t :to-be (nshell.infrastructure.acl:sidecar-alive-p handle))
             (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) handle
                   (nshell.feature.assistant::assistant-sidecar-state-init-p state) t
                   (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
             (nshell.feature.assistant::%assistant-sidecar-publish pending rejected)
             (nshell.feature.assistant::%assistant-sidecar-publish pending late)
             (multiple-value-bind (event present-p)
                 (nshell.feature.assistant::%assistant-sidecar-poll state 91)
               (expect t :to-be present-p)
               (expect rejected :to-be event))
             (expect nil :to-be (nshell.infrastructure.acl:sidecar-alive-p handle))
             (expect :stopped :to-be (nshell.infrastructure.acl:sidecar-handle-cleanup-state handle))
             (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))
             (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-init-p state))
             (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-pending state))
             (expect t :to-be (cl-concurrent-kit:promise-settled-p
                              (nshell.feature.assistant::assistant-pending-cell-completion pending)))
             ;; Install a ready successor without a provider or shell restart.
             (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) :successor
                   (nshell.feature.assistant::assistant-sidecar-state-init-p state) t
                   (nshell.feature.assistant::assistant-sidecar-state-write-channel state) writes)
             (with-temporary-function
                 ('nshell.infrastructure.acl:sidecar-alive-p
                  (lambda (candidate) (eq candidate :successor)))
               (expect t :to-be (nshell.feature.assistant::%assistant-sidecar-request
                                state 92 '(("type" . "user") ("message" . "next")))))
             (nshell.feature.assistant::%assistant-sidecar-publish pending late)
             (multiple-value-bind (event present-p)
                 (nshell.feature.assistant::%assistant-sidecar-poll state 92)
               (expect nil :to-be event)
               (expect nil :to-be present-p))
             (expect 92 :to-be (nshell.feature.assistant::assistant-pending-cell-generation
                               (nshell.feature.assistant::assistant-sidecar-state-pending state)))
             (expect nil :to-be (cl-concurrent-kit:promise-settled-p
                                (nshell.feature.assistant::assistant-pending-cell-completion
                                 (nshell.feature.assistant::assistant-sidecar-state-pending state)))))
        (nshell.infrastructure.acl:stop-sidecar handle)
        (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) nil)
        (nshell.feature.assistant::%assistant-sidecar-stop-state state)
        (cl-concurrent-kit:close-channel writes)
        (cl-concurrent-kit:close-channel
         (nshell.feature.assistant::assistant-pending-cell-events pending)))))
  (it "publishes-startup-error-for-request-generation"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (pending (nshell.feature.assistant::%make-assistant-pending-cell
                     0 (cl-concurrent-kit:make-channel :buffer-size 2)
                     (cl-concurrent-kit:make-promise)))
           (publication-entered (cl-concurrent-kit:make-channel :buffer-size 1))
           (allow-publication (cl-concurrent-kit:make-channel :buffer-size 1))
           (publish (symbol-function 'nshell.feature.assistant::%assistant-sidecar-publish))
           (event-before-publication nil)
           (worker nil)
           (publication-released-p nil))
      (setf (nshell.feature.assistant::assistant-sidecar-state-startup-generation state) 1
            (nshell.feature.assistant::assistant-sidecar-state-starting-p state) t
            (nshell.feature.assistant::assistant-sidecar-state-handle state) :fixture
            (nshell.feature.assistant::assistant-sidecar-state-init-p state) t
            (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
      (unwind-protect
           (with-temporary-functions
               (('nshell.infrastructure.acl:run-sidecar-version-cancellable
                 (lambda (command cancelled-p)
                   (declare (ignore command cancelled-p))
                   (values nil :command-not-found)))
                ('nshell.feature.assistant::%assistant-sidecar-publish
                 (lambda (cell event)
                   (setf event-before-publication event)
                   (cl-concurrent-kit:send publication-entered t)
                   (cl-concurrent-kit:recv
                    allow-publication :timeout (cl-date-kit:duration-of-seconds 2))
                   (funcall publish cell event)))
                ('nshell.feature.assistant::%assistant-sidecar-write-item
                 (lambda (current item)
                   (declare (ignore current item))
                   t)))
             (unwind-protect
                  (progn
                    (setf worker
                          (sb-thread:make-thread
                           (lambda ()
                             (nshell.feature.assistant::%assistant-sidecar-start-worker
                              state pending 1))))
                    (multiple-value-bind (value present-p)
                        (cl-concurrent-kit:recv
                         publication-entered :timeout (cl-date-kit:duration-of-seconds 2))
                      (expect t :to-be present-p)
                      (expect t :to-be value))
                    (expect 0 :to-be
                            (nshell.feature.assistant:assistant-model-event-generation
                             event-before-publication))
                    (expect t :to-be
                            (with-temporary-function
                                ('nshell.feature.assistant::%assistant-sidecar-dead-p
                                 (lambda (current)
                                   (declare (ignore current))
                                   nil))
                              (nshell.feature.assistant::%assistant-sidecar-request
                               state 57
                               (nshell.feature.assistant:make-assistant-user-payload "race"))))
                    (expect 57 :to-be
                            (nshell.feature.assistant::assistant-pending-cell-generation pending))
                    (cl-concurrent-kit:send allow-publication t)
                    (setf publication-released-p t)
                    (sb-thread:join-thread worker :timeout 2 :default :timed-out)
                    (expect nil :to-be (sb-thread:thread-alive-p worker))
                    (multiple-value-bind (event present-p)
                        (nshell.feature.assistant::%assistant-sidecar-poll state 57)
                      (expect t :to-be present-p)
                      (expect :stream-error :to-be
                              (nshell.feature.assistant:assistant-model-event-kind event))
                      (progn
                        (expect
                         (nshell.feature.assistant:assistant-model-event-generation event)
                         :to-be 57)
                        (expect
                         (nshell.feature.assistant::%assistant-object-field
                          (nshell.feature.assistant:assistant-model-event-payload
                           event-before-publication)
                          "message")
                         :to-equal
                         (nshell.feature.assistant::%assistant-object-field
                          (nshell.feature.assistant:assistant-model-event-payload event)
                          "message"))))
                    (expect t :to-be
                            (cl-concurrent-kit:promise-settled-p
                             (nshell.feature.assistant::assistant-pending-cell-completion pending))))
               (unless publication-released-p
                 (cl-concurrent-kit:send allow-publication t))
               (when worker
                 (sb-thread:join-thread worker :timeout 2 :default nil))))
        (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) nil
              (nshell.feature.assistant::assistant-sidecar-state-init-p state) nil
              (nshell.feature.assistant::assistant-sidecar-state-pending state) nil)
        (cl-concurrent-kit:close-channel publication-entered)
        (cl-concurrent-kit:close-channel allow-publication)
        (cl-concurrent-kit:close-channel
         (nshell.feature.assistant::assistant-pending-cell-events pending)))))

  (it "keeps-allowed-and-warning-rate-events-pending"
    (dolist (status '("allowed" "allowed_warning"))
      (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
             (pending (nshell.feature.assistant::%make-assistant-pending-cell
                       91 (cl-concurrent-kit:make-channel :buffer-size 2)
                       (cl-concurrent-kit:make-promise)))
             (event (nshell.feature.assistant::make-assistant-model-event
                     91 :rate-limit-event `(("rate_limit_info" . (("status" . ,status)))))))
        (unwind-protect
             (progn
               (setf (nshell.feature.assistant::assistant-sidecar-state-pending state) pending)
               (nshell.feature.assistant::%assistant-sidecar-publish pending event)
               (multiple-value-bind (polled present-p)
                   (nshell.feature.assistant::%assistant-sidecar-poll state 91)
                 (expect t :to-be present-p)
                 (expect event :to-be polled))
               (expect pending :to-be (nshell.feature.assistant::assistant-sidecar-state-pending state))
               (expect nil :to-be (cl-concurrent-kit:promise-settled-p
                                  (nshell.feature.assistant::assistant-pending-cell-completion pending))))
          (nshell.feature.assistant::%assistant-sidecar-stop-state state)))))

  (it "bounds-eof-cleanup-when-child-closes-stdout-but-keeps-running"
    (let* ((state (nshell.feature.assistant::%make-assistant-sidecar-state nil nil))
           (handle (nshell.infrastructure.acl:spawn-sidecar
                    "/bin/sh" '("-c" "exec 1>&-; exec sleep 30")
                    :input :stream :output :stream :error :stream))
           (pending (nshell.feature.assistant::%make-assistant-pending-cell
                     93 (cl-concurrent-kit:make-channel :buffer-size 2)
                     (cl-concurrent-kit:make-promise)))
           (reader nil))
      (unwind-protect
           (progn
             (expect t :to-be (nshell.infrastructure.acl:sidecar-alive-p handle))
             (setf (nshell.feature.assistant::assistant-sidecar-state-handle state) handle
                   (nshell.feature.assistant::assistant-sidecar-state-init-p state) t
                   (nshell.feature.assistant::assistant-sidecar-state-pending state) pending
                   reader (sb-thread:make-thread
                           (lambda ()
                             (nshell.feature.assistant::%assistant-sidecar-reader-loop state handle 0))))
             (sb-thread:join-thread reader :timeout 2 :default :timed-out)
             (expect nil :to-be (sb-thread:thread-alive-p reader))
             (expect nil :to-be (nshell.infrastructure.acl:sidecar-alive-p handle))
             (expect t :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-p state))
             (expect :reader-eof :to-be (nshell.feature.assistant::assistant-sidecar-state-dead-reason state))
             (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-init-p state))
             (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))
             (expect t :to-be (cl-concurrent-kit:promise-settled-p
                              (nshell.feature.assistant::assistant-pending-cell-completion pending)))
             (multiple-value-bind (event present-p)
                 (nshell.feature.assistant::%assistant-sidecar-poll state 93)
               (expect t :to-be present-p)
               (expect :stream-error :to-be (nshell.feature.assistant:assistant-model-event-kind event)))
             (expect nil :to-be (nshell.feature.assistant::assistant-sidecar-state-pending state)))
        (nshell.infrastructure.acl:stop-sidecar handle)
        (when reader
          (sb-thread:join-thread reader :timeout 2 :default nil))
        (nshell.feature.assistant::%assistant-sidecar-stop-state state)
        (cl-concurrent-kit:close-channel
         (nshell.feature.assistant::assistant-pending-cell-events pending)))))

  (it "keeps-the-ready-reader-generation-when-start-is-repeated"
    (let* ((script (%assistant-test-sidecar-script))
           (state (nshell.feature.assistant::%make-assistant-sidecar-state
                   (namestring script) nil)))
      (unwind-protect
           (progn
             (expect t :to-be (nshell.feature.assistant::%assistant-sidecar-start state))
             (%assistant-test-await-sidecar-ready state)
             (let ((generation (nshell.feature.assistant::assistant-sidecar-state-startup-generation state))
                   (handle (nshell.feature.assistant::assistant-sidecar-state-handle state))
                   (reader (nshell.feature.assistant::assistant-sidecar-state-reader-thread state)))
               (expect t :to-be (nshell.feature.assistant::%assistant-sidecar-start state))
               (expect generation :to-be
                       (nshell.feature.assistant::assistant-sidecar-state-startup-generation state))
               (expect handle :to-be (nshell.feature.assistant::assistant-sidecar-state-handle state))
               (expect reader :to-be
                       (nshell.feature.assistant::assistant-sidecar-state-reader-thread state))
               (expect t :to-be (sb-thread:thread-alive-p reader))
               (expect t :to-be
                       (nshell.feature.assistant::%assistant-sidecar-request
                        state 71 (nshell.feature.assistant:make-assistant-user-payload "ready-restart")))
               (%assistant-test-await-sidecar-result state 71)))
        (nshell.feature.assistant::%assistant-sidecar-stop-state state)
        (when (probe-file script) (delete-file script)))))

  (it "keeps-allowed-rate-events-nonterminal-across-two-requests"
    (let* ((script (%assistant-test-rate-sidecar-script))
           (state (nshell.feature.assistant::%make-assistant-sidecar-state
                   (namestring script) nil)))
      (unwind-protect
           (progn
             (expect t :to-be (nshell.feature.assistant::%assistant-sidecar-start state))
             (%assistant-test-await-sidecar-ready state)
             (loop for generation in '(81 82)
                   for request-number from 1
                   do (expect t :to-be
                              (nshell.feature.assistant::%assistant-sidecar-request
                               state generation
                               (nshell.feature.assistant:make-assistant-user-payload
                                (format nil "request-~D" request-number))))
                      (let ((result (%assistant-test-await-sidecar-result
                                     state generation :allowed-rate-p t)))
                        (expect (format nil "request-~D" request-number) :to-equal
                                (cdr (assoc "reason"
                                            (cdr (assoc "structured_output"
                                                        (nshell.feature.assistant:assistant-model-event-payload result)
                                                        :test #'string=))
                                            :test #'string=))))))
        (nshell.feature.assistant::%assistant-sidecar-stop-state state)
        (when (probe-file script) (delete-file script))))))

  (it "does-not-let-poll-consume-the-startup-handshake"
    (let ((script (%assistant-test-sidecar-script))
          (context nil))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context
                           boundary))))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-start)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-request
                       1 '(("message" . "handshake-race")))))
             (let* ((result nil)
                    (deadline
                      (+ (get-internal-real-time)
                         (round
                          (* (1+ nshell.feature.assistant::+assistant-sidecar-handshake-timeout-seconds+)
                             internal-time-units-per-second)))))
               (loop while (and (null result)
                                (< (get-internal-real-time) deadline))
                     do (let* ((polled
                                 (nshell.feature.assistant:assistant-model-poll 1))
                               (status
                                 (nshell.feature.assistant:assistant-boundary-status
                                  polled)))
                          (when (eq :event status)
                            (let ((event
                                    (nshell.feature.assistant:assistant-boundary-value
                                     polled)))
                              (when (eq :result
                                        (nshell.feature.assistant:assistant-model-event-kind
                                         event))
                                (setf result event))))
                          (unless result
                            (sleep 0))))
               (expect :result :to-be
                       (nshell.feature.assistant:assistant-model-event-kind result)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-stop))))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script)))))

  (it "publishes-a-reasoned-terminal-event-before-stop-closes-pending"
    (let ((script (%assistant-test-pending-sidecar-script))
          (context nil))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context
                           boundary))))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-start)))
             (expect :ready :to-be
                     (getf (%assistant-test-await-state :ready) :state))
             (expect :event :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-poll 0)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-request
                       31 '(("message" . "stop-pending")))))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-stop)))
             (let* ((polled (nshell.feature.assistant:assistant-model-poll 31))
                    (event (nshell.feature.assistant:assistant-boundary-value polled)))
               (expect :event :to-be
                       (nshell.feature.assistant:assistant-boundary-status polled))
               (expect :stream-error :to-be
                       (nshell.feature.assistant:assistant-model-event-kind event))
               (expect "assistant sidecar stopped before the pending request completed"
                       :to-equal
                       (cdr (assoc "message"
                                   (nshell.feature.assistant:assistant-model-event-payload
                                    event)
                                   :test #'string=)))))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script)))))

  (it "publishes-a-reasoned-terminal-event-before-respawn-replaces-pending"
    (let ((script (%assistant-test-sidecar-script t))
          (context nil))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context
                           boundary))))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-start)))
             (expect :ready :to-be
                     (getf (%assistant-test-await-state :ready) :state))
             (expect :event :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-poll 0)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-request
                       32 '(("message" . "respawn-pending")))))
             (expect :dead :to-be
                     (getf (%assistant-test-await-state :dead) :state))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-start)))
             (let ((error-event nil))
               (loop repeat 8
                     until error-event
                     do (let ((polled (nshell.feature.assistant:assistant-model-poll 32)))
                          (when (eq :event
                                    (nshell.feature.assistant:assistant-boundary-status
                                     polled))
                            (let ((event
                                    (nshell.feature.assistant:assistant-boundary-value polled)))
                              (when (eq :stream-error
                                        (nshell.feature.assistant:assistant-model-event-kind
                                         event))
                                (setf error-event event))))))
                 (expect :stream-error :to-be
                         (nshell.feature.assistant:assistant-model-event-kind
                          error-event)))
             (nshell.feature.assistant:assistant-model-stop))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script)))))

(describe "assistant-sidecar-reader-stop-race"
  (it "stops-cleanly-when-init-gate-rejects-a-live-reader"
    (let ((script (%assistant-test-rejecting-sidecar-script))
          (context nil))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (setf context
                          (nshell.feature.assistant:make-assistant-boundary-context
                           boundary)))
                  (start (nshell.feature.assistant:assistant-model-start)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status start))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-request
                       1 '(("message" . "queued-before-handshake")))))
             (expect :unavailable :to-be
                     (getf (%assistant-test-await-state :unavailable) :state))
             (let ((error-event nil))
               (loop repeat 240
                     until error-event
                     do (let ((polled (nshell.feature.assistant:assistant-model-poll 1)))
                          (when (eq :event
                                    (nshell.feature.assistant:assistant-boundary-status
                                     polled))
                            (let ((event
                                    (nshell.feature.assistant:assistant-boundary-value
                                     polled)))
                              (when (eq :stream-error
                                        (nshell.feature.assistant:assistant-model-event-kind
                                         event))
                                (setf error-event event))))
                          (unless error-event
                            (sleep 0.01))))
               (expect :stream-error :to-be
                       (nshell.feature.assistant:assistant-model-event-kind
                        error-event)))
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-stop)))
             (expect nil :to-be
                     (%assistant-test-live-thread-named-p
                      "nshell assistant sidecar reader")))
        (%assistant-test-with-sidecar-cleanup context)
        (when (probe-file script)
          (delete-file script))))))
