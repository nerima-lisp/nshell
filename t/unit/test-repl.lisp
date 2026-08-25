(in-package #:nshell/test)

(describe "repl-tests"
  (it "repl-entrypoints-are-public"
    "CLI-facing REPL entrypoints should be exported presentation APIs."
    (expect (fboundp 'nshell.presentation:run-repl) :to-be-truthy)
    (expect (fboundp 'nshell.presentation:run-repl-batch) :to-be-truthy)
    (expect (fboundp 'nshell.presentation:run-repl-script) :to-be-truthy))

  (it "repl-batch-returns-last-exit-code"
    "Batch execution should return the last command status for process exit."
    (with-repl-test-state
      (let ((code (nshell.presentation:run-repl-batch :line "false")))
        (expect 1 :to-equal code)
        (expect 1 :to-equal nshell.presentation::*last-exit-code*))))

  (it "repl-copy-output-event-copies-first-kill-ring-selection"
    "The copy output event sends the first kill-ring selection before redrawing the prompt."
    (with-repl-test-state
      (let ((nshell.infrastructure.terminal::*clipboard-host-writer* nil))
        (with-stable-repl-prompt (:text "PROMPT> ")
          (with-fixed-terminal-size (24 80)
            (with-repl-input-state (:kill-ring '("first" "second"))
              (let* ((output (capture-process-output-event :copy))
                     (clipboard (format nil "~C]52;c;Zmlyc3Q=~C" #\Esc #\Bell))
                     (clipboard-position (search clipboard output))
                     (prompt-position (search "PROMPT> " output)))
                (expect clipboard-position :to-be-truthy)
                (expect prompt-position :to-be-truthy)
                (expect (< clipboard-position prompt-position) :to-be-truthy))))))))

  (it "repl-copy-output-event-prefers-host-clipboard"
    "A working host clipboard writer should receive text without emitting OSC 52."
    (with-repl-test-state
      (let ((copied nil))
        (let ((nshell.infrastructure.terminal::*clipboard-host-writer*
                (lambda (text)
                  (setf copied text)
                  t)))
          (with-stable-repl-prompt (:text "PROMPT> ")
            (with-fixed-terminal-size (24 80)
              (with-repl-input-state (:kill-ring '("first"))
                (let ((output (capture-process-output-event :copy)))
                  (expect "first" :to-equal copied)
                  (expect (search (format nil "~C]52;" #\Esc) output)
                          :to-be-null)
                  (expect (search "PROMPT> " output) :to-be-truthy)))))))))

  (it "repl-copy-output-event-falls-back-to-osc52-on-host-failure"
    "A failed host clipboard writer should fall back to the terminal clipboard transport."
    (with-repl-test-state
      (let ((attempts 0))
        (let ((nshell.infrastructure.terminal::*clipboard-host-writer*
                (lambda (text)
                  (declare (ignore text))
                  (incf attempts)
                  nil)))
          (with-stable-repl-prompt (:text "PROMPT> ")
            (with-fixed-terminal-size (24 80)
              (with-repl-input-state (:kill-ring '("first"))
                (let ((output (capture-process-output-event :copy)))
                  (expect 1 :to-equal attempts)
                  (expect (search (format nil "~C]52;" #\Esc) output)
                          :to-be-truthy)
                  (expect (search "PROMPT> " output) :to-be-truthy)))))))))

  (it "read-key-cont-renders-after-pending-terminal-resize"
    "A pending terminal resize redraws without reading another key."
    (with-repl-test-state
      (let ((rendered nil))
        (with-temporary-functions
            (('nshell.infrastructure.acl:consume-terminal-resize-p
              (lambda () t))
             ('nshell.presentation::render-prompt-cont
              (lambda ()
                (setf rendered t))))
          (let ((continuation (nshell.presentation::read-key-cont)))
            (expect (functionp continuation) :to-be-truthy)
            (funcall continuation)
            (expect rendered :to-be-truthy))))))

    (it "read-key-cont-passes-the-sigint-predicate"
    "The REPL passes pending SIGINT detection into terminal input."
    (with-repl-test-state
      (with-repl-input-state (:buffer "" :cursor-pos 0)
        (let ((event (input-key-event :char #\x))
              (reduced-state (input-state :buffer "x" :cursor-pos 1))
              (received-predicate nil)
              (received-reduction nil)
              (processed-output nil))
          (with-temporary-functions
              (('nshell.infrastructure.acl:consume-terminal-resize-p
                (lambda () nil))
               ('nshell.infrastructure.terminal:read-key-event
                (lambda (&key interrupt-predicate)
                  (setf received-predicate interrupt-predicate)
                  event))
               ('nshell.presentation:reduce-input-state
                (lambda (state key-event)
                  (setf received-reduction (list state key-event))
                  (values reduced-state :redraw)))
               ('nshell.presentation::process-output-event
                (lambda (output-event)
                  (setf processed-output output-event)
                  nil)))
            (let ((continuation (nshell.presentation::read-key-cont)))
              (expect (functionp received-predicate) :to-be-truthy)
              (expect (functionp continuation) :to-be-truthy)
              (funcall continuation)
              (expect reduced-state :to-be nshell.presentation::*input-state*)
              (expect event :to-be (second received-reduction))
              (expect :redraw :to-be processed-output)))))))

  (it "read-key-cont-stops-after-end-of-input"
    "End of input stops the REPL when no resize notification is pending."
    (with-repl-test-state
      (with-temporary-functions
          (('nshell.infrastructure.acl:consume-terminal-resize-p
            (lambda () nil))
           ('nshell.infrastructure.terminal:read-key-event
            (lambda (&key interrupt-predicate)
  (declare (ignore interrupt-predicate))
  nil)))
        (expect nil :to-be (nshell.presentation::read-key-cont))
        (expect nil :to-be nshell.presentation::*running*))))

  (it "read-key-cont-renders-after-resize-detected-during-read"
    "A resize detected after an input read still schedules a redraw."
    (with-repl-test-state
      (let ((resize-checks 0)
            (rendered nil))
        (with-temporary-functions
            (('nshell.infrastructure.acl:consume-terminal-resize-p
              (lambda ()
                (= 2 (incf resize-checks))))
             ('nshell.infrastructure.terminal:read-key-event
              (lambda (&key interrupt-predicate)
  (declare (ignore interrupt-predicate))
  nil))
             ('nshell.presentation::render-prompt-cont
              (lambda ()
                (setf rendered t))))
          (let ((continuation (nshell.presentation::read-key-cont)))
            (expect (functionp continuation) :to-be-truthy)
            (expect 2 :to-equal resize-checks)
            (funcall continuation)
            (expect rendered :to-be-truthy))))))

  (it "repl-mouse-event-maps-rendered-buffer-position"
    "Rendered SGR mouse coordinates become buffer-relative mouse events."
    (with-repl-test-state
      (with-repl-input-state (:buffer "abc" :cursor-pos 3)
        (let ((nshell.presentation::*prompt-rendered-prompt-width* 4)
              (nshell.presentation::*prompt-rendered-terminal-width* 10)
              (event (input-key-event
                      :mouse
                      nil
                      7
                      (list :protocol :sgr
                            :event :press
                            :row 1
                            :column 5))))
          (let ((mapped (nshell.presentation::%map-rendered-mouse-event-to-buffer event)))
            (expect :mouse :to-be (nshell.domain.input:key-event-type mapped))
            (expect 7 :to-equal (nshell.domain.input:key-event-number mapped))
            (expect (getf (nshell.domain.input:key-event-data mapped)
                          :buffer-index)
                    :to-equal 0))
          (let ((unmapped (input-key-event
                           :mouse
                           nil
                           8
                           (list :protocol :sgr
                                 :event :press
                                 :row 99
                                 :column 99))))
            (expect unmapped :to-be
                    (nshell.presentation::%map-rendered-mouse-event-to-buffer
                     unmapped)))))))

  (it "repl-copy-output-event-does-nothing-for-empty-kill-ring-selection"
    "An empty kill ring or empty first selection still redraws the prompt without OSC 52."
    (dolist (kill-ring '(nil ("")))
      (with-repl-test-state
        (with-stable-repl-prompt (:text "PROMPT> ")
          (with-fixed-terminal-size (24 80)
            (with-repl-input-state (:kill-ring kill-ring)
              (let ((output (capture-process-output-event :copy)))
                (expect (search (format nil "~C]52;" #\Esc) output)
                        :to-be-null)
                (expect (search "PROMPT> " output) :to-be-truthy))))))))
  (it "repl-output-dispatcher-routes-terminal-events"
    "The output dispatcher routes terminal events to their dedicated handlers."
    (with-temporary-functions
        (((quote nshell.presentation::%process-quit-output-event)
          (lambda () :quit))
         ((quote nshell.presentation::%process-history-next-output-event)
          (lambda () :history-next))
         ((quote nshell.presentation::%process-redraw-output-event)
          (lambda () :redraw))
         ((quote nshell.presentation::%process-default-output-event)
          (lambda () :default)))
      (expect :quit :to-be
              (nshell.presentation::process-output-event :quit))
      (expect :history-next :to-be
              (nshell.presentation::process-output-event :history-next))
      (expect :redraw :to-be
              (nshell.presentation::process-output-event :redraw))
      (expect :default :to-be
              (nshell.presentation::process-output-event :unrecognized))))
  (it "repl-output-event-handlers-execute-terminal-effects"
    "Redraw and default events render a prompt; quit stops the loop."
    (with-repl-test-state
      (with-stable-repl-prompt (:text "PROMPT> ")
        (with-fixed-terminal-size (24 80)
          (with-repl-input-state (:kill-ring nil)
            (let ((redraw-output (capture-process-output-event :redraw))
                  (default-output (capture-process-output-event :unknown)))
              (expect (search "PROMPT> " redraw-output)
                      :to-be-truthy)
              (expect (search "PROMPT> " default-output)
                      :to-be-truthy))
            (expect nil :to-be
                    (nshell.presentation::process-output-event :quit))
            (expect nil :to-be
                    nshell.presentation::*running*))))))
  (it "repl-batch-reads-standard-input-when-command-line-is-omitted"
    "Without a line argument batch mode evaluates source lines from standard input."
    (with-repl-test-state
      (with-input-from-string (*standard-input* (format nil "true~%"))
        (expect 0 :to-equal
                (nshell.presentation:run-repl-batch)))))
  (it "repl-batch-and-script-report-execution-errors"
    "Batch and script entrypoints convert execution failures to exit status one."
    (with-repl-test-state
      (with-temporary-functions
          (((quote nshell.presentation::%execute-with-repl-shell-context)
            (lambda (thunk)
              (declare (ignore thunk))
              (error "forced execution failure"))))
        (let ((batch-error
                (with-output-to-string (*error-output*)
                  (expect 1 :to-equal
                          (nshell.presentation:run-repl-batch :line "true"))))
              (script-error
                (with-output-to-string (*error-output*)
                  (expect 1 :to-equal
                          (nshell.presentation:run-repl-script "ignored")))))
          (expect (search "nshell error: forced execution failure" batch-error)
                  :to-be-truthy)
          (expect (search "nshell: forced execution failure" script-error)
                  :to-be-truthy)))))
)
