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

(describe "fr-004-explain-panel-contracts"
  (it "shows-explain-result-in-a-panel-without-replacing-the-edit-buffer"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "keep this input"
                              :cursor-pos 15)
        (let ((panel nil))
          (setf nshell.presentation::*assistant-request-kind* :explain)
          (with-temporary-functions
              (('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (nshell.presentation::%handle-ask-model-event
             (nshell.feature.assistant::make-assistant-model-event
              1 :result
              '(("explanation" . "説明本文をここに表示")
                ("structured_output" .
                 (("next_steps" . ("ls"))))))))
          (expect (search "説明本文をここに表示" (first panel)) :to-be-truthy)
          (expect "keep this input"
                  :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))
          (expect nil :to-be
                  (search "説明本文をここに表示"
                          (nshell.presentation:input-state-buffer
                           nshell.presentation::*input-state*)))))))

  (it "gates-tab-candidates-by-classify-ast-and-proposal-origin"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "original input"
                              :cursor-pos 14)
        (let ((panel nil)
              (classification-count 0)
              (original-classify
                (symbol-function 'nshell.feature.assistant:classify-ast)))
          (setf nshell.presentation::*assistant-request-kind* :explain)
          (with-temporary-functions
              (('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil))
               ('nshell.feature.assistant:classify-ast
                (lambda (ast)
                  (incf classification-count)
                  (funcall original-classify ast))))
            (nshell.presentation::%handle-ask-model-event
             (nshell.feature.assistant::make-assistant-model-event
              1 :result
              '(("explanation" . "説明")
                ("structured_output" .
                 (("next_steps" . ("ls" "rm file" "rm -rf /")))))))
            (nshell.presentation::%process-explain-panel-event
             (input-key-event :tab))
            (expect "ls"
                    :to-equal
                    (nshell.presentation:input-state-buffer
                     nshell.presentation::*input-state*))
            (expect :proposal :to-be
                    nshell.presentation::*assistant-command-origin*)
            (expect t :to-be
                    nshell.presentation::*assistant-command-confirmed-p*)
            (nshell.presentation::%process-explain-panel-event
             (input-key-event :tab))
            (expect "rm file"
                    :to-equal
                    (nshell.presentation:input-state-buffer
                     nshell.presentation::*input-state*))
            (expect :proposal :to-be
                    nshell.presentation::*assistant-command-origin*)
            (expect nil :to-be
                    nshell.presentation::*assistant-command-confirmed-p*)
            (nshell.presentation::%process-explain-panel-event
             (input-key-event :tab))
            (expect "rm file"
                    :to-equal
                    (nshell.presentation:input-state-buffer
                     nshell.presentation::*input-state*))
            (expect nil :to-be
                    (search "rm -rf /"
                            (nshell.presentation:input-state-buffer
                             nshell.presentation::*input-state*)))
            (expect (search "block" (first panel)) :to-be-truthy)
            (expect 3 :to-be classification-count)))))))

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

(describe "command-not-found-fallback-tests"
  (it "sends-the-missing-command-line-to-ask-with-one-key"
    (with-repl-test-state
      (with-temporary-output-file (audit-path)
        (let* ((start-count 0)
               (request-payload nil)
               (boundary
                 (nshell.feature.assistant:make-assistant-model-boundary
                  :start-fn (lambda () (incf start-count) t)
                  :request-fn (lambda (generation payload)
                                (declare (ignore generation))
                                (setf request-payload payload)
                                t)
                  :poll-fn (lambda (generation)
                             (declare (ignore generation))
                             (values nil nil))
                  :stop-fn (lambda () t))))
          (setf nshell.feature.assistant:*assistant-boundaries*
                (nshell.feature.assistant:make-assistant-boundary-context
                 boundary)
                nshell.presentation::*command-not-found-fallback-text*
                  "mystery command")
          (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                  audit-path))
            (with-temporary-functions
                (('nshell.infrastructure.acl:get-git-status
                  (lambda (directory)
                    (declare (ignore directory))
                    (values nil nil)))
                 ('nshell.presentation::render-prompt-cont
                  (lambda () nil))
                 ('nshell.presentation::render-assistant-progress-panel
                 (lambda (started-at)
                    (declare (ignore started-at))
                    nil)))
              (let ((event (input-key-event :ctrl-right-bracket)))
                (nshell.presentation::%process-command-not-found-fallback-event
                 event)))
            (let ((message (cdr (assoc "message" request-payload
                                       :test #'string=))))
              (expect "mystery command" :to-equal
                      (cdr (assoc "content" message :test #'string=))))
            (expect nil :to-be
                    nshell.presentation::*command-not-found-fallback-text*)
            (expect :ask-waiting :to-be
                    (nshell.presentation:input-state-mode
                     nshell.presentation::*input-state*)) )))))

  (it "clears-the-fallback-and-does-not-record-the-line-for-other-keys"
    (with-repl-test-state
      (setf nshell.presentation::*command-not-found-fallback-text*
              "mystery command")
      (with-repl-input-state (:buffer "" :cursor-pos 0)
        (with-temporary-functions
            (('nshell.presentation::refresh-current-input-state-suggestion
              (lambda (&optional text)
                (declare (ignore text))
                nil)))
          (nshell.presentation::%process-command-not-found-fallback-event
           (input-key-event :char #\x))
        (expect nil :to-be
                nshell.presentation::*command-not-found-fallback-text*)
        (expect "x" :to-equal
                (nshell.presentation:input-state-buffer
                 nshell.presentation::*input-state*))
        (expect nil :to-be
                (history-kit:history-entries nshell.presentation::*history*)))))))

(describe "repl-explain-tests"
  (it "uses-one-key-to-submit-explain-and-routes-other-keys-to-editing"
    (with-repl-test-state
      (let ((submitted-p nil))
        (with-repl-input-state (:mode :insert :buffer "" :cursor-pos 0)
          (setf nshell.presentation::*failure-explain-available-p* t)
          (with-temporary-functions
              (('nshell.presentation::%process-ask-submit-output-event
                (lambda () (setf submitted-p t))))
            (nshell.presentation::%process-failure-explain-event
             (input-key-event :ctrl-right-bracket)))
          (expect submitted-p :to-be-truthy)
          (expect :explain :to-be nshell.presentation::*assistant-request-kind*)
          (expect :ask-waiting :to-be
                  (nshell.presentation:input-state-mode
                   nshell.presentation::*input-state*)))
        (with-repl-input-state (:mode :insert :buffer "" :cursor-pos 0)
          (setf nshell.presentation::*failure-explain-available-p* t)
          (nshell.presentation::%process-failure-explain-event
           (input-key-event :char #\x))
          (expect nil :to-be
                  nshell.presentation::*failure-explain-available-p*)
          (expect "x" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))))))

  (it "renders-explain-text-without-replacing-the-edit-buffer"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "keep this"
                              :cursor-pos 9)
        (let ((panel nil)
              (event
                (nshell.feature.assistant::make-assistant-model-event
                 1 :result
                 '(("text" . "The command failed because the file is missing.")
                   ("next_steps" .
                    ((("command" . "ls"))
                     (("command" . "rm -rf /"))))))))
          (setf nshell.presentation::*assistant-request-kind* :explain)
          (with-temporary-functions
              (('nshell.presentation::render-prompt-cont
                (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content))))
            (nshell.presentation::%handle-ask-model-event event))
          (expect "keep this" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))
          (expect :insert :to-be
                  (nshell.presentation:input-state-mode
                   nshell.presentation::*input-state*))
          (expect (search "The command failed" (first panel)) :to-be-truthy)
          (expect (search "1. ls" (third panel)) :to-be-truthy)))))

  (it "reads-explain-text-from-content-blocks"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting :buffer "keep" :cursor-pos 4)
        (let ((panel nil))
          (setf nshell.presentation::*assistant-request-kind* :explain)
          (with-temporary-functions
              (('nshell.presentation::render-prompt-cont
                (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content))))
            (nshell.presentation::%handle-ask-model-event
             (nshell.feature.assistant::make-assistant-model-event
              1 :result
              '(("content" . ((("text" . "content block explanation"))))))))
          (expect (search "content block explanation" (first panel))
                  :to-be-truthy)))))

  (it "sends-only-redacted-explain-context-to-the-model-and-audit"
    (with-repl-test-state
      (repl-test-set-env "API_TOKEN" "secret-value" t)
      (setf nshell.presentation::*last-exit-code* 7
            nshell.presentation::*last-command-duration-ms* 42
            nshell.presentation::*last-command-output*
              "failed sk-12345678901234567890 secret-value")
      (add-history-record nshell.presentation::*history*
                          "deploy sk-12345678901234567890"
                          :exit-code 7
                          :duration-ms 42)
      (with-repl-input-state (:mode :ask-waiting :buffer "" :cursor-pos 0)
        (with-temporary-output-file (audit-path)
          (let* ((request-payload nil)
                (boundary
                  (nshell.feature.assistant:make-assistant-model-boundary
                   :start-fn (lambda () t)
                   :request-fn (lambda (generation payload)
                                 (declare (ignore generation))
                                 (setf request-payload payload)
                                 t)
                   :poll-fn (lambda (generation)
                              (declare (ignore generation))
                              (values nil nil))
                   :stop-fn (lambda () t))))
            (setf nshell.presentation::*assistant-request-kind* :explain
                  nshell.feature.assistant:*assistant-boundaries*
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
                (nshell.presentation::process-output-event :ask-submit))
              (let* ((context (cdr (assoc "context" request-payload
                                           :test #'string=)))
                     (last-output (cdr (assoc "last-output" context
                                               :test #'string=)))
                     (printed (with-output-to-string (stream)
                                (write request-payload :stream stream)))
                     (audit (host-kit:read-file-string audit-path)))
                (expect "failed [REDACTED] [REDACTED]"
                        :to-equal last-output)
                (expect nil :to-be (search "secret-value" printed))
                (expect nil :to-be
                        (search "sk-12345678901234567890" printed))
                (expect nil :to-be (search "secret-value" audit))
                (expect nil :to-be
                        (search "sk-12345678901234567890" audit)))))))))

  (it "gates-tab-candidates-with-classify-ast-and-rejects-blocked-commands"
    (with-repl-test-state
      (with-repl-input-state (:mode :insert :buffer "keep" :cursor-pos 4)
        (setf nshell.presentation::*assistant-explain-candidates* '("ls")
              nshell.presentation::*assistant-explain-candidate-index* 0)
        (with-temporary-function
            ('nshell.presentation::render-transient-panel
             (lambda (content &rest arguments)
               (declare (ignore content arguments))))
          (nshell.presentation::%process-explain-panel-event
           (input-key-event :tab)))
        (expect "ls" :to-equal
                (nshell.presentation:input-state-buffer
                 nshell.presentation::*input-state*))
        (expect :proposal :to-be nshell.presentation::*assistant-command-origin*)
        (expect t :to-be nshell.presentation::*assistant-command-confirmed-p*))
      (with-repl-input-state (:mode :insert :buffer "keep" :cursor-pos 4)
        (setf nshell.presentation::*assistant-explain-candidates* '("rm -rf /")
              nshell.presentation::*assistant-explain-candidate-index* 0)
        (with-temporary-function
            ('nshell.presentation::render-transient-panel
             (lambda (content &rest arguments)
               (declare (ignore content arguments))))
          (nshell.presentation::%process-explain-panel-event
           (input-key-event :tab)))
        (expect "keep" :to-equal
                (nshell.presentation:input-state-buffer
                 nshell.presentation::*input-state*))
        (expect :proposal :to-be nshell.presentation::*assistant-command-origin*)))))
