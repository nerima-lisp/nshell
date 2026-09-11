(in-package #:nshell/test)

(describe "ai-builtin-and-usage-tests"
  (it "accumulates-result-usage-and-resets-it"
    (with-repl-test-state
      (nshell.feature.assistant:record-assistant-result-usage
       '( ("num_turns" . 2)
          ("usage" . (("input_tokens" . 11)
                       ("output_tokens" . 7)))
          ("total_cost_usd" . 0.25)))
      (expect 2 :to-equal
              (nshell.feature.assistant:assistant-usage-turns
               nshell.feature.assistant:*assistant-usage*))
      (expect 11 :to-equal
              (nshell.feature.assistant:assistant-usage-input-tokens
               nshell.feature.assistant:*assistant-usage*))
      (expect 7 :to-equal
              (nshell.feature.assistant:assistant-usage-output-tokens
               nshell.feature.assistant:*assistant-usage*))
      (nshell.feature.assistant:reset-assistant-usage)
      (expect 0 :to-equal
              (nshell.feature.assistant:assistant-usage-turns
               nshell.feature.assistant:*assistant-usage*))))

  (it "ai-reset-advances-generation-without-stopping-the-boundary"
    (with-repl-test-state
      (setf nshell.presentation::*assistant-turn-generation* 4)
      (nshell.feature.assistant:record-assistant-result-usage
       '(("num_turns" . 1)))
      (let ((nshell.application:*ai-reset-handler*
              #'nshell.presentation::reset-ai-session))
        (with-builtins-context (context)
          (multiple-value-bind (output code)
              (call-builtin context "ai" '("reset"))
            (expect 0 :to-equal code)
            (expect (search "conversation reset" output) :to-be-truthy)
            (expect 5 :to-equal
                    nshell.presentation::*assistant-turn-generation*)
            (expect 0 :to-equal
                    (nshell.feature.assistant:assistant-usage-turns
                     nshell.feature.assistant:*assistant-usage*)))))))

  (it "ai-status-does-not-start-the-sidecar-in-a-batch-session"
    (with-repl-test-state
      ;; LET* so the start-fn closure captures this binding rather than a free
      ;; variable: with a parallel LET the assertion below could never fail.
      (let* ((started-p nil)
             (boundary
              (nshell.feature.assistant:make-assistant-model-boundary
               :start-fn (lambda () (setf started-p t) t)
               :request-fn (lambda (generation payload)
                             (declare (ignore generation payload))
                             t)
               :poll-fn (lambda (generation)
                          (declare (ignore generation))
                          (values nil nil))
                :stop-fn (lambda () t))))
        (setf nshell.feature.assistant:*assistant-boundaries*
              (nshell.feature.assistant:make-assistant-boundary-context
               boundary))
        (with-builtins-context (context)
          (with-temporary-function
              ('nshell.infrastructure.terminal:interactive-terminal-p
               (lambda (&optional fd)
                 (declare (ignore fd))
                 nil))
            (multiple-value-bind (output code)
                (call-builtin context "ai" '("status"))
              (expect 0 :to-equal code)
              (expect (search "non-interactive" output) :to-be-truthy)
              (expect nil :to-be started-p)))))))

  (it "ai-set-overrides-the-effective-environment-setting"
    (with-repl-test-state
      (let* ((name "NSHELL_AI_MAX_STEPS")
             (old-value (host-kit:getenv name)))
        (unwind-protect
             (progn
               (sb-posix:setenv name "2" 1)
               (expect 2 :to-equal
                       (nshell.feature.assistant:assistant-setting-value
                        :max-steps))
               (with-builtins-context (context)
                 (multiple-value-bind (output code)
                     (call-builtin context "ai" '("set" "max-steps" "4"))
                   (expect 0 :to-equal code)
                   (expect (search "max-steps set to 4" output) :to-be-truthy))
                 (expect 4 :to-equal
                         (nshell.feature.assistant:assistant-setting-value
                          :max-steps)))))
          (if old-value
              (sb-posix:setenv name old-value 1)
              (sb-posix:unsetenv name)))))

  (it "usage-segment-includes-the-configured-budget"
    (with-repl-test-state
      (nshell.feature.assistant:set-assistant-setting :budget "1.50")
      (nshell.feature.assistant:record-assistant-result-usage
       '(("total_cost_usd" . 0.25)))
      (expect (nshell.feature.assistant:assistant-usage-short-text)
              :to-equal "1t 0/0 tokens budget $0.25/$1.50")))

  (it "ai-log-prints-only-the-requested-audit-tail"
    (with-repl-test-state
      (with-temporary-output-file (path :prefix "nshell-ai-audit-")
        (with-open-file (stream path :direction :output
                                :if-does-not-exist :create)
          (write-line "{\"payload\":1}" stream)
          (write-line "{\"payload\":2}" stream)
          (write-line "{\"payload\":3}" stream))
        (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                path))
          (with-builtins-context (context)
            (multiple-value-bind (output code)
                (call-builtin context "ai" '("log" "2"))
              (expect 0 :to-equal code)
              (expect nil :to-be (search "payload\":1" output))
              (expect (search "payload\":2" output) :to-be-truthy)
              (expect (search "payload\":3" output) :to-be-truthy)))))))

  (it "ai-rejects-unknown-subcommands-and-extra-arguments"
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (call-builtin context "ai" '("unknown"))
        (expect 2 :to-equal code)
        (expect (search "usage" output) :to-be-truthy))
      (expect 2 :to-equal
              (nth-value 1 (call-builtin context "ai" '("status" "extra")))))))
