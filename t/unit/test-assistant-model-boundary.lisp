(in-package #:nshell/test)

(defun %assistant-test-fixture-path (name)
  (merge-pathnames
   (format nil "t/fixtures/assistant/~a.jsonl" name)
   (asdf:system-source-directory (asdf:find-system "nshell/test"))))

(defun %assistant-stop-sidecar (handle)
  (funcall (symbol-function 'nshell.infrastructure.acl:stop-sidecar) handle))

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

  (it "accepts-only-an-empty-tool-and-mcp-init"
    (expect (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system")
               ("subtype" . "init")
               ("tools")
               ("mcp_servers")))
            :to-be-truthy)
    (expect nil :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system")
               ("subtype" . "init")
               ("tools" . ("shell"))
               ("mcp_servers"))))
    (expect nil :to-be
            (nshell.feature.assistant:assistant-system-init-safe-p
             '(("type" . "system") ("subtype" . "init")))))

  (it "builds-a-sidecar-command-with-strict-mcp-isolation"
    (let ((arguments (nshell.feature.assistant:assistant-sidecar-command-arguments)))
      (expect (member "--strict-mcp-config" arguments :test #'string=)
              :to-be-truthy)
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
