(in-package #:nshell/test)

(describe "repl-ask-request-tests"
  (it "starts-the-model-and-sends-the-natural-language-payload"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "show changed files"
                              :cursor-pos 18)
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
          (with-temporary-functions
              (('nshell.presentation::render-prompt-cont
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
              (expect :ask-waiting :to-be
                      (nshell.presentation:input-state-mode
                       nshell.presentation::*input-state*))))))))

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
