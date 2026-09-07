(in-package #:nshell/test)

(describe "repl-ask-request-tests"
  (it "starts-the-model-and-sends-the-natural-language-payload"
    (with-repl-test-state
      (repl-test-set-env "API_TOKEN" "secret-value" t)
      (add-history-record nshell.presentation::*history*
                          "printf sk-12345678901234567890"
                          :exit-code 0
                          :duration-ms 37)
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "show changed files"
                              :cursor-pos 18)
        (with-temporary-output-file (audit-path)
          (let* ((start-count 0)
                 (request-generation nil)
                 (request-payload nil)
                 (boundary
                   (nshell.feature.assistant:make-assistant-model-boundary
                    :start-fn (lambda ()
                                (incf start-count)
                                t)
                    :request-fn (lambda (generation payload)
                                  (setf request-generation generation
                                        request-payload payload)
                                  t)
                    :poll-fn (lambda (generation)
                               (declare (ignore generation))
                               (values nil nil))
                    :stop-fn (lambda ()
                               t))))
            (setf nshell.feature.assistant:*assistant-boundaries*
                  (nshell.feature.assistant:make-assistant-boundary-context
                   boundary))
            (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                    audit-path))
              (with-temporary-functions
                  (('nshell.infrastructure.acl:get-git-status
                    (lambda (directory)
                      (declare (ignore directory))
                      (values "main" nil)))
                   ('nshell.presentation::render-prompt-cont
                    (lambda () nil))
                   ('nshell.presentation::render-assistant-progress-panel
                    (lambda (started-at)
                      (declare (ignore started-at))
                      nil)))
                (let ((continuation
                        (nshell.presentation::process-output-event :ask-submit)))
                  (expect (functionp continuation) :to-be-truthy)
                  (expect 1 :to-be start-count)
                  (expect 1 :to-be request-generation)
                  (expect "user" :to-equal
                          (cdr (assoc "type" request-payload :test #'string=)))
                  (let ((message (cdr (assoc "message" request-payload
                                              :test #'string=))))
                    (expect "user" :to-equal
                            (cdr (assoc "role" message :test #'string=)))
                    (expect "show changed files" :to-equal
                            (cdr (assoc "content" message :test #'string=))))
                  (let* ((context (cdr (assoc "context" request-payload
                                              :test #'string=)))
                         (environment-names
                           (cdr (assoc "environment-names" context
                                       :test #'string=)))
                         (printed (with-output-to-string (stream)
                                    (write request-payload :stream stream)))
                         (audit (host-kit:read-file-string audit-path)))
                    (expect (find "API_TOKEN" environment-names
                                  :test #'string=)
                            :to-be-truthy)
                    (expect nil :to-be (search "secret-value" printed))
                    (expect nil :to-be
                            (search "sk-12345678901234567890" printed))
                    (expect nil :to-be (search "secret-value" audit))
                    (expect nil :to-be
                            (search "sk-12345678901234567890" audit)))
                  (expect :ask-waiting :to-be
                          (nshell.presentation:input-state-mode
                           nshell.presentation::*input-state*))))))))))

  (it "renders-the-ask-suffix-and-includes-it-in-prompt-geometry"
    (with-repl-test-state
      (with-stable-repl-prompt (:text "PROMPT> " :width 8)
        (with-fixed-terminal-size (24 80)
          (with-repl-input-state (:mode :ask
                                  :buffer "hello"
                                  :cursor-pos 5)
            (let ((output
                    (capture-standard-output
                      (nshell.presentation::render-prompt-cont))))
              (expect (search "ask>" output) :to-be-truthy)
              (expect 13 :to-be
                      nshell.presentation::*prompt-rendered-prompt-width*)))))))

  (it "returns-to-insert-mode-after-a-terminal-model-event"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "question"
                              :cursor-pos 8)
        (let ((event
                (nshell.feature.assistant::make-assistant-model-event
                 1 :result nil)))
          (setf nshell.presentation::*assistant-turn-generation* 1
                nshell.presentation::*assistant-turn-started-at* 0
                nshell.presentation::*assistant-model-event-handler*
                  #'nshell.presentation::%handle-ask-model-event)
          (with-temporary-function
              ('nshell.presentation::render-prompt-cont
               (lambda () nil))
            (funcall nshell.presentation::*assistant-model-event-handler* event))
          (expect :insert :to-be
                  (nshell.presentation:input-state-mode
                   nshell.presentation::*input-state*))
          (expect nil :to-be
                  nshell.presentation::*assistant-model-event-handler*)
          (expect nil :to-be
                  nshell.presentation::*assistant-turn-started-at*))))))

(describe "repl-ask-proposal-tests"
  (it "installs-a-safe-result-and-keeps-one-undo-step"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "question"
                              :cursor-pos 8)
        (let ((event
                (nshell.feature.assistant::make-assistant-model-event
                 1 :result
                  '(("structured_output" .
                     (("command" . "ls"))))))
              (panel nil))
          (with-temporary-functions
              (('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (nshell.presentation::%handle-ask-model-event event))
          (expect :insert :to-be
                  (nshell.presentation:input-state-mode
                   nshell.presentation::*input-state*))
          (expect "ls" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))
          (expect :proposal :to-be
                  nshell.presentation::*assistant-command-origin*)
          (expect t :to-be
                  nshell.presentation::*assistant-command-confirmed-p*)
          (multiple-value-bind (restored output)
              (nshell.presentation::undo-input-state
               nshell.presentation::*input-state*)
            (declare (ignore output))
            (expect "question" :to-equal
                    (nshell.presentation:input-state-buffer restored)))
          (expect (search "safe" (first panel)) :to-be-truthy)))))

  (it "installs-a-confirm-result-without-marking-it-confirmed"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "question"
                              :cursor-pos 8)
        (let ((event
                (nshell.feature.assistant::make-assistant-model-event
                 1 :result
                  '(("structured_output" .
                     (("command" . "rm file"))))))
              (panel nil))
          (with-temporary-functions
              (('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (nshell.presentation::%handle-ask-model-event event))
          (expect "rm file" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))
          (expect nil :to-be
                  nshell.presentation::*assistant-command-confirmed-p*)
          (expect (search "confirm" (first panel)) :to-be-truthy)))))

  (it "does-not-install-a-blocked-result-in-the-buffer"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "question"
                              :cursor-pos 8)
        (let ((event
                (nshell.feature.assistant::make-assistant-model-event
                 1 :result
                  '(("structured_output" .
                     (("command" . "rm -rf /"))))))
              (panel nil))
          (with-temporary-functions
              (('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (nshell.presentation::%handle-ask-model-event event))
          (expect "" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))
          (expect :typed :to-be
                  nshell.presentation::*assistant-command-origin*)
          (expect (search "block" (first panel)) :to-be-truthy)))))

  (it "does-not-install-a-parse-error-result-in-the-buffer"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "question"
                              :cursor-pos 8)
        (let ((event
                (nshell.feature.assistant::make-assistant-model-event
                 1 :result
                  '(("structured_output" .
                     (("command" . "unterminated '"))))))
              (panel nil))
          (with-temporary-functions
              (('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (nshell.presentation::%handle-ask-model-event event))
          (expect "" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))
          (expect (search "解釈できない提案" (first panel)) :to-be-truthy))))))

(describe "repl-ask-confirmation-tests"
  (it "does-not-execute-a-confirm-proposal-before-the-second-enter"
    (with-repl-test-state
      (let ((nshell.presentation::*history-persistence-enabled-p* nil)
            (execute-count 0)
            (panel nil))
        (with-repl-input-state (:mode :insert
                                :buffer "rm file"
                                :cursor-pos 7)
          (let ((nshell.presentation::*assistant-command-origin* :proposal)
                (nshell.presentation::*assistant-command-confirmed-p* nil))
            (with-temporary-functions
                (('nshell.presentation::execute-ast
                  (lambda (ast)
                    (declare (ignore ast))
                    (incf execute-count)
                    0))
                 ('nshell.presentation::render-transient-panel
                  (lambda (content &rest arguments)
                    (declare (ignore arguments))
                    (setf panel content)))
                 ('nshell.presentation::render-prompt-cont
                  (lambda () nil)))
              (capture-process-output-event :execute)
              (expect 0 :to-be execute-count)
              (expect t :to-be
                      nshell.presentation::*assistant-command-confirmed-p*)
              (expect (search "confirmation" (first panel)) :to-be-truthy)
              (capture-process-output-event :execute)
              (expect 1 :to-be execute-count))))))))
