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
      (with-stable-repl-prompt (:text "PROMPT> ")
        (with-fixed-terminal-size (24 80)
          (with-repl-input-state (:kill-ring '("first" "second"))
            (let* ((output (capture-process-output-event :copy))
                   (clipboard (format nil "~C]52;c;Zmlyc3Q=~C" #\Esc #\Bell))
                   (clipboard-position (search clipboard output))
                   (prompt-position (search "PROMPT> " output)))
              (expect clipboard-position :to-be-truthy)
              (expect prompt-position :to-be-truthy)
              (expect (< clipboard-position prompt-position) :to-be-truthy)))))))

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
                (expect (search "PROMPT> " output) :to-be-truthy)))))))))
