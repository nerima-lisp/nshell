(in-package #:nshell/test)

(describe "repl-assistant-poll-tests"
  (it "delivers-a-current-generation-model-event-through-the-repl-loop"
    (with-repl-test-state
      (let* ((event
               (nshell.feature.assistant::make-assistant-model-event
                7 :assistant '("text" . "current")))
             (polled-generation nil)
             (handled-event nil)
             (read-count 0))
        (setf nshell.presentation::*assistant-turn-generation* 7
              nshell.presentation::*assistant-model-event-handler*
                (lambda (handled)
                  (setf handled-event handled)))
        (with-temporary-functions
            (('nshell.infrastructure.acl:consume-terminal-resize-p
              (lambda () nil))
             ('nshell.feature.assistant:assistant-model-poll
              (lambda (generation)
                (setf polled-generation generation)
                (if (= 1 (incf read-count))
                    (list :status :event :value event)
                    (list :status :empty))))
             ('nshell.infrastructure.terminal:read-key-event
              (lambda (&key interrupt-predicate)
                (funcall interrupt-predicate)))
             ('nshell.presentation::render-prompt-cont
              (lambda () nil)))
          (let ((continuation (nshell.presentation::read-key-cont)))
            (expect (functionp continuation) :to-be-truthy)
            (funcall continuation)
            (expect 7 :to-equal polled-generation)
            (expect event :to-be handled-event)
            (expect event :to-be nshell.presentation::*last-assistant-model-event*))))))

  (it "discards-a-stale-model-event-before-processing-the-next-key"
    (with-repl-test-state
      (with-repl-input-state (:buffer "" :cursor-pos 0)
        (let* ((stale
                 (nshell.feature.assistant::make-assistant-model-event
                  1 :result '("command" . "old")))
               (polled-generation nil)
               (reduced-event nil)
               (processed-output nil))
          (setf nshell.presentation::*assistant-turn-generation* 2)
          (with-temporary-functions
              (('nshell.infrastructure.acl:consume-terminal-resize-p
                (lambda () nil))
               ('nshell.feature.assistant:assistant-model-poll
                (lambda (generation)
                  (setf polled-generation generation)
                  (list :status :event :value stale)))
               ('nshell.infrastructure.terminal:read-key-event
                (lambda (&key interrupt-predicate)
                  (expect nil :to-be (funcall interrupt-predicate))
                  (input-key-event :char #\x)))
               ('nshell.presentation:reduce-input-state
                (lambda (state event)
                  (declare (ignore state))
                  (setf reduced-event event)
                  (values (input-state :buffer "x" :cursor-pos 1) :redraw)))
               ('nshell.presentation::process-output-event
                (lambda (output-event)
                  (setf processed-output output-event))))
            (let ((continuation (nshell.presentation::read-key-cont)))
              (expect (functionp continuation) :to-be-truthy)
              (funcall continuation)
              (expect 2 :to-equal polled-generation)
              (expect :char :to-be
                      (nshell.domain.input:key-event-type reduced-event))
              (expect :redraw :to-be processed-output)
              (expect nil :to-be
                      nshell.presentation::*last-assistant-model-event*)))))))

  (it "forwards-a-non-signal-interrupt-event-without-changing-signal-input"
    (let ((event
            (nshell.feature.assistant::make-assistant-model-event
             4 :assistant nil)))
      (with-input-from-string (*standard-input* "x")
        (let ((first-p t))
          (let ((read-event
                  (nshell.infrastructure.terminal:read-key-event
                   :interrupt-predicate
                   (lambda ()
                     (when first-p
                       (setf first-p nil)
                       event)))))
            (expect event :to-be read-event)))))))

(describe "repl-assistant-cancel-tests"
  (it "keeps-the-sidecar-on-the-first-cancel-and-restarts-it-on-the-second"
    (with-repl-test-state
      (with-repl-input-state (:mode :ask-waiting
                              :buffer "question"
                              :cursor-pos 8)
        (let* ((clock 0)
              (start-count 0)
              (stop-count 0)
              (boundary
                (nshell.feature.assistant:make-assistant-model-boundary
                 :start-fn (lambda () (incf start-count) t)
                 :request-fn (lambda (generation payload)
                               (declare (ignore generation payload))
                               t)
                 :poll-fn (lambda (generation)
                            (declare (ignore generation))
                            (values nil nil))
                 :stop-fn (lambda () (incf stop-count) t))))
          (setf nshell.feature.assistant:*assistant-boundaries*
                (nshell.feature.assistant:make-assistant-boundary-context
                 boundary))
          (with-temporary-functions
              (('nshell.presentation::boundary-monotonic
                (lambda () clock))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (let ((continuation
                    (nshell.presentation::process-output-event
                     :ask-cancel-turn)))
              (when continuation (funcall continuation)))
            (expect 0 :to-be stop-count)
            (expect 0 :to-be start-count)
            (expect 1 :to-be nshell.presentation::*assistant-turn-generation*)
            (expect 0 :to-be nshell.presentation::*assistant-last-cancel-at*)
            (setf clock internal-time-units-per-second)
            (let ((continuation
                    (nshell.presentation::process-output-event
                     :ask-cancel-turn)))
              (when continuation (funcall continuation)))
            (expect 1 :to-be stop-count)
            (expect 1 :to-be start-count)
            (expect 2 :to-be nshell.presentation::*assistant-turn-generation*)
            (expect :insert :to-be
                    (nshell.presentation:input-state-mode
                     nshell.presentation::*input-state*))
            (expect nil :to-be nshell.presentation::*assistant-last-cancel-at*))))))

  (it "recognizes-the-second-control-c-as-a-cancel-turn-event"
    (with-repl-test-state
      (with-repl-input-state (:mode :insert :buffer "" :cursor-pos 0)
        (setf nshell.presentation::*assistant-last-cancel-at* 0)
        (with-temporary-functions
            (('nshell.presentation::boundary-monotonic
              (lambda () internal-time-units-per-second))
             ('nshell.infrastructure.acl:consume-terminal-resize-p
              (lambda () nil))
             ('nshell.feature.assistant:assistant-model-poll
              (lambda (generation)
                (declare (ignore generation))
                (list :status :empty)))
             ('nshell.infrastructure.terminal:read-key-event
              (lambda (&key interrupt-predicate)
                (declare (ignore interrupt-predicate))
                (input-key-event :ctrl-c)))
             ('nshell.presentation::process-output-event
              (lambda (output-event)
                (expect :ask-cancel-turn :to-be output-event)))
             ('nshell.presentation::render-prompt-cont
              (lambda () nil)))
          (let ((continuation (nshell.presentation::read-key-cont)))
            (expect (functionp continuation) :to-be-truthy)
            (funcall continuation)))))))
