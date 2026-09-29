(in-package #:nshell/test)

(defun %assistant-stop-sidecar (handle)
  (funcall (symbol-function 'nshell.infrastructure.acl:stop-sidecar) handle))

(defun %assistant-test-sidecar-script (&optional one-shot-p)
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-sidecar-~D.sh"
                       (get-internal-real-time))
               (uiop:temporary-directory))))
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (dolist (line
                '("#!/bin/sh"
                  "if [ \"$1\" = \"--version\" ]; then"
                  "  printf '%s\\n' 'test-version'"
                  "  exit 0"
                  "fi"
                  "printf '%s\\n' '{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"StructuredOutput\"],\"mcp_servers\":[]}'"
                  "while IFS= read -r line"
                  "do"
                  "  printf '%s\\n' '{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}}'"
                  "  printf '%s\\n' '{\"type\":\"result\",\"subtype\":\"success\",\"structured_output\":{\"command\":\"pwd\",\"reason\":\"fixture\",\"risk\":\"low\"}}'"))
        (write-line line stream))
      (when one-shot-p
        (write-line "  exit 0" stream))
      (write-line "done" stream))
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
      (dolist (line
                '("#!/bin/sh"
                  "if [ \"$1\" = \"--version\" ]; then"
                  "  printf '%s\\n' 'test-version'"
                  "  exit 0"
                  "fi"
                  "printf '%s\\n' '{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"StructuredOutput\"],\"mcp_servers\":[]}'"
                  "while IFS= read -r line"
                  "do"
                  "  while :; do sleep 1; done"
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

(defmacro %assistant-test-with-sidecar-cleanup (&body body)
  `(unwind-protect
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
               do (sleep 0.01))))))

(defun %assistant-test-await-state (state &optional (limit 240))
  (loop repeat limit
        for status = (nshell.feature.assistant:assistant-model-status)
        do (if (eq state (getf status :state))
               (return status)
               (sleep 0.05))))

(defun %assistant-test-terminal-event-description (event)
  (let* ((kind (nshell.feature.assistant:assistant-model-event-kind event))
         (payload (nshell.feature.assistant:assistant-model-event-payload event))
         (message (or (cdr (assoc "message" payload :test #'string=))
                      (cdr (assoc "reason" payload :test #'string=)))))
    (format nil "kind=~S message=~S payload=~S" kind message payload)))

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
    (let ((script (%assistant-test-hanging-version-sidecar-script)))
      (unwind-protect
           (let* ((boundary (nshell.feature.assistant:make-assistant-sidecar-boundary
                             :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context boundary))
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
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script)))))

  (it "reports-version-probe-output-when-the-sidecar-exits-with-an-error"
    (let ((script (%assistant-test-failing-version-sidecar-script)))
      (unwind-protect
           (let* ((boundary (nshell.feature.assistant:make-assistant-sidecar-boundary
                             :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context boundary))
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
        (%assistant-test-with-sidecar-cleanup)
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
    (let ((script (%assistant-test-sidecar-script)))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary))
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
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script)))))

  (it "discards-a-stale-sidecar-pending-before-the-next-request"
    (let ((script (%assistant-test-sidecar-script)))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary)))
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
             (expect :ok :to-be
                     (nshell.feature.assistant:assistant-boundary-status
                      (nshell.feature.assistant:assistant-model-stop))))
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script)))))

  (it "respawns-sidecar-after-reader-detects-process-death"
    (let ((script (%assistant-test-sidecar-script t)))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary))
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
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script))))))

  (it "does-not-let-poll-consume-the-startup-handshake"
    (let ((script (%assistant-test-sidecar-script)))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary)))
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
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script)))))

  (it "publishes-a-reasoned-terminal-event-before-stop-closes-pending"
    (let ((script (%assistant-test-pending-sidecar-script)))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary)))
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
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script)))))

  (it "publishes-a-reasoned-terminal-event-before-respawn-replaces-pending"
    (let ((script (%assistant-test-sidecar-script t)))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary)))
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
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script)))))

(describe "assistant-sidecar-reader-stop-race"
  (it "stops-cleanly-when-init-gate-rejects-a-live-reader"
    (let ((script (%assistant-test-rejecting-sidecar-script)))
      (unwind-protect
           (let* ((boundary
                    (nshell.feature.assistant:make-assistant-sidecar-boundary
                     :command (namestring script)))
                  (nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary))
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
        (%assistant-test-with-sidecar-cleanup)
        (when (probe-file script)
          (delete-file script))))))
