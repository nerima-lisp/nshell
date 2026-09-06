(in-package #:nshell/test)

(defun %assistant-test-fixture-path (name)
  (merge-pathnames
   (format nil "fixtures/assistant/~a.jsonl" name)
   (asdf:system-source-directory (asdf:find-system "nshell/test"))))

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
                              (nshell.feature.assistant:assistant-model-event-payload result)
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
