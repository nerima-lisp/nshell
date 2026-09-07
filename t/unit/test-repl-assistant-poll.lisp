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
