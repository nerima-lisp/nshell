(in-package #:nshell/test)

(describe "assistant-environment-request-contracts"
  (it "preserves ordinary settings in the actual request and audit payload"
    (cl-weave:expect-assertions 14)
    (with-repl-test-state
      (setf nshell.presentation::*assistant-session-id* "test-session")
      (repl-test-set-env "NSHELL_AI_MAX_STEPS" "1" t)
      (repl-test-set-env "?" "0")
      (repl-test-set-env "status" "0")
      (repl-test-set-env "UNKNOWN_SECRET" "Q" t)
      (add-history-record nshell.presentation::*history*
                          "echo live-approved-65341"
                          :exit-code 0 :duration-ms 1)
      (setf nshell.presentation::*last-command-output* "result 0 step 1 secret Q")
      (with-repl-input-state (:mode :ask-waiting
                             :buffer "live-approved-65341 Q"
                             :cursor-pos 21)
        (host-kit:with-temporary-directory (audit-directory)
          (let* ((audit-path (merge-pathnames "ai-audit.jsonl" audit-directory))
                 (start-count 0)
                 (request-count 0)
                 (request-generation nil)
                 (request-payload nil)
                 (boundary
                   (nshell.feature.assistant:make-assistant-model-boundary
                    :start-fn (lambda () (incf start-count) t)
                    :request-fn (lambda (generation payload)
                                  (incf request-count)
                                  (setf request-generation generation
                                        request-payload payload)
                                  t)
                    :poll-fn (lambda (generation)
                               (declare (ignore generation))
                               (values nil nil))
                    :stop-fn (lambda () t))))
            (setf nshell.feature.assistant:*assistant-boundaries*
                  (nshell.feature.assistant:make-assistant-boundary-context boundary))
            (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                    audit-path))
              (with-temporary-functions
                  (('nshell.infrastructure.acl:get-git-status
                    (lambda (directory)
                      (declare (ignore directory))
                      (values "main" nil)))
                   ('nshell.presentation::render-prompt-cont (lambda () nil))
                   ('nshell.presentation::render-assistant-progress-panel
                    (lambda (started-at) (declare (ignore started-at)) nil)))
                (expect (functionp
                         (nshell.presentation::process-output-event :ask-submit))
                        :to-be-truthy)
                (expect 1 :to-be start-count)
                (expect 1 :to-be request-count)
                (expect 1 :to-be request-generation)
                (let* ((message (cdr (assoc "message" request-payload :test #'string=)))
                       (context (cdr (assoc "context" request-payload :test #'string=)))
                       (names (cdr (assoc "environment-names" context :test #'string=)))
                       (audit (host-kit:read-file-string audit-path)))
                  (expect "live-approved-65341 [REDACTED]" :to-equal
                          (cdr (assoc "content" message :test #'string=)))
                  (expect "echo live-approved-65341" :to-equal
                          (cdr (assoc "command" context :test #'string=)))
                  (expect "result 0 step 1 secret [REDACTED]" :to-equal
                          (cdr (assoc "last-output" context :test #'string=)))
                  (dolist (name '("NSHELL_AI_MAX_STEPS" "?" "status" "UNKNOWN_SECRET"))
                    (expect (member name names :test #'string=) :to-be-truthy))
                  (expect (plusp (length audit)) :to-be-truthy)
                  (expect (search "live-approved-65341" audit) :to-be-truthy)
                  (expect nil :to-be (search "secret Q" audit))))))))))

  (it "keeps one-character unknown secrets redacted on the actual send path"
    (cl-weave:expect-assertions 3)
    (with-repl-test-state
      (repl-test-set-env "NSHELL_AI_MAX_STEPS" "1" t)
      (repl-test-set-env "UNKNOWN_VALUE" "1" t)
      (with-repl-input-state (:mode :ask-waiting
                             :buffer "live-approved-65341" :cursor-pos 19)
        (host-kit:with-temporary-directory (audit-directory)
          (let ((request-count 0)
                (request-payload nil)
                (nshell.feature.assistant:*assistant-audit-file-path-override*
                  (merge-pathnames "ai-audit.jsonl" audit-directory)))
            (setf nshell.feature.assistant:*assistant-boundaries*
                  (nshell.feature.assistant:make-assistant-boundary-context
                   (nshell.feature.assistant:make-assistant-model-boundary
                    :start-fn (lambda () t)
                    :request-fn (lambda (generation payload)
                                  (declare (ignore generation))
                                  (incf request-count)
                                  (setf request-payload payload)
                                  t))))
            (with-temporary-functions
                (('nshell.infrastructure.acl:get-git-status
                  (lambda (directory)
                    (declare (ignore directory)) (values nil nil)))
                 ('nshell.presentation::render-prompt-cont (lambda () nil))
                 ('nshell.presentation::render-assistant-progress-panel
                  (lambda (started-at) (declare (ignore started-at)) nil)))
              (expect (functionp
                       (nshell.presentation::process-output-event :ask-submit))
                      :to-be-truthy)
              (expect 1 :to-be request-count)
              (expect "live-approved-6534[REDACTED]" :to-equal
                      (cdr (assoc "content"
                                  (cdr (assoc "message" request-payload :test #'string=))
                                  :test #'string=))))))))))

(describe "assistant-context-contracts"
  (it "assembles only redacted, bounded context values"
    (let* ((context
             (nshell.feature.assistant:assemble-assistant-context
              :command "printf ghp_12345678901234567890"
              :exit 1
              :duration-ms 123
              :cwd "/Users/example/project"
              :git-status "main dirty"
              :last-output (format nil "old output~%last visible output")
              :last-output-max-bytes 19
              :environment-names '("API_TOKEN=secret-value" "HOME=/Users/example")))
           (payload (nshell.feature.assistant:assistant-context-payload context))
           (printed (with-output-to-string (stream)
                      (write payload :stream stream))))
      (expect 1 :to-be
              (nshell.feature.assistant:assistant-context-exit context))
      (expect 123 :to-be
              (nshell.feature.assistant:assistant-context-duration-ms context))
      (expect "/Users/example/project" :to-equal
              (nshell.feature.assistant:assistant-context-cwd context))
      (expect "last visible output" :to-equal
              (nshell.feature.assistant:assistant-context-last-output context))
      (expect (search "API_TOKEN" printed) :to-be-truthy)
      (expect nil :to-be (search "secret-value" printed))
      (expect nil :to-be (search "ghp_12345678901234567890" printed))))

  (it "drops denylisted context lines before applying the output bound"
    (let ((context
            (nshell.feature.assistant:assemble-assistant-context
             :last-output (format nil "skip /tmp/private.env~%keep this line")
             :last-output-max-bytes 100
             :denylist-paths '("*/private.env"))))
      (expect "keep this line" :to-equal
              (nshell.feature.assistant:assistant-context-last-output context)))))
