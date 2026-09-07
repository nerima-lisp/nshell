(in-package #:nshell/test)

(defun %assistant-test-fixture-path (name)
  (merge-pathnames
   (format nil "t/fixtures/assistant/~a.jsonl" name)
   (asdf:system-source-directory (asdf:find-system "nshell/test"))))

(defun %assistant-stop-sidecar (handle)
  (funcall (symbol-function 'nshell.infrastructure.acl:stop-sidecar) handle))

(defun %assistant-test-sidecar-script (&optional one-shot-p)
  (let ((path (merge-pathnames
               (format nil "nshell-assistant-sidecar-~D.sh" (get-universal-time))
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

(describe "assistant-model-boundary-contracts"
  (it "replays-a-sanitized-stream-json-fixture-through-the-injected-boundary"
    (multiple-value-bind (boundary error-message)
        (nshell.feature.assistant:make-assistant-fixture-boundary
         (%assistant-test-fixture-path "normal"))
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
                              :test #'string=)))))))

  (it "marks-a-fixture-without-a-result-as-stream-ended"
    (multiple-value-bind (boundary error-message)
        (nshell.feature.assistant:make-assistant-fixture-boundary
         (%assistant-test-fixture-path "interrupted"))
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
          (expect :stream-ended :to-be (first kinds)))))))

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
      (expect nil :to-be (member "--safe-mode" arguments :test #'string=))))

  (it "starts-sidecar-in-its-own-group-without-shell-registration"
    (let ((foreground-pgid nshell.infrastructure.acl::*foreground-pgid*)
          (registry-count (hash-table-count nshell.presentation::*proc-registry*)))
      (multiple-value-bind (handle status)
          (nshell.infrastructure.acl:spawn-sidecar
           "/bin/cat" nil :input :stream :output :stream :error :stream)
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
             (flet ((await-result (generation)
                      (let ((request
                              (nshell.feature.assistant:assistant-model-request
                               generation '(("message" . "hello")))))
                        (expect :ok :to-be
                                (nshell.feature.assistant:assistant-boundary-status
                                 request)))
                      (let ((result nil))
                        (loop repeat 100
                              until result
                              do (let ((polled
                                         (nshell.feature.assistant:assistant-model-poll
                                          generation)))
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
                                (nshell.feature.assistant:assistant-model-event-kind
                                 result))
                        (expect generation :to-be
                                (nshell.feature.assistant:assistant-model-event-generation
                                 result)))))
               (await-result 1)
               (sleep 0.1)
               (await-result 2)
               (expect :ok :to-be
                       (nshell.feature.assistant:assistant-boundary-status
                        (nshell.feature.assistant:assistant-model-stop))))
        (when (probe-file script)
          (delete-file script))))))
