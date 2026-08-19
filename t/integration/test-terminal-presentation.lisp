(in-package #:nshell/test)

(describe "terminal-integration-tests"
  (it "terminal-enter-on-incomplete-input-continues-buffer"
    "Decoded Enter can be promoted to multiline continuation after parsing."
    (dolist (line (list "echo \"hi" "echo \\"))
      (let ((state (input-state)))
        (dolist (event (read-key-events-from-string (format nil "~a~%" line)))
          (multiple-value-bind (next-state output)
                (nshell.presentation:reduce-input-state state event)
            (setf state
                    (if (eq output :execute)
                        (with-parsed-command-line
                            (result (nshell.presentation:input-state-buffer next-state))
                          (if (nshell.domain.parsing:parse-result-incomplete result)
                              (nth-value 0
                                         (nshell.presentation:insert-newline-at-cursor
                                          next-state))
                              next-state))
                        next-state))))
        (expect (format nil "~a~%" line) :to-equal (nshell.presentation:input-state-buffer state))
        (expect (length (nshell.presentation:input-state-buffer state)) :to-equal (nshell.presentation:input-state-cursor-pos state)))))

  (it "terminal-execute-on-structural-incomplete-input-indents-continuation"
    "REPL execution promotes structural incomplete input to an indented continuation."
    (with-repl-test-state
      (dolist (line '("echo hi |" "echo hi &&" "if true"))
        (let ((expected (concatenate 'string line (string #\Newline) "  ")))
          (setf nshell.presentation::*input-state*
                (nshell.presentation::make-repl-input-state :buffer line))
          (capture-process-output-event :execute)
          (expect expected :to-equal (nshell.presentation:input-state-buffer
                                      nshell.presentation::*input-state*))
          (expect (length (nshell.presentation:input-state-buffer
                          nshell.presentation::*input-state*)) :to-equal (nshell.presentation:input-state-cursor-pos
                  nshell.presentation::*input-state*))))))

  (it "terminal-highlight-uses-parser-diagnostics"
    "Presentation highlighting marks parser diagnostics as errors."
    (let* ((spans (nshell.highlight:highlight-line "| echo nope"))
           (first-span (first spans)))
      (expect (null first-span) :to-be-falsy)
      (expect :error :to-be (nshell.highlight:highlight-span-role first-span))
      (expect 0 :to-equal (nshell.highlight:highlight-span-start first-span))
      (expect 1 :to-equal (nshell.highlight:highlight-span-end first-span))))

  (it "terminal-highlight-span-constructor-is-internal-boundary"
    "Highlight spans are produced by highlight-line rather than public raw construction."
    (expect (fboundp 'nshell.highlight::make-highlight-span) :to-be-falsy)
    (expect (fboundp 'nshell.highlight::highlight-span-p) :to-be-falsy)
    (expect (fboundp 'nshell.highlight::copy-highlight-span) :to-be-falsy)
    (expect (fboundp 'nshell.highlight::%make-highlight-span) :to-be-truthy))

  (it "terminal-highlight-span-type-is-internal-boundary"
    "Highlight spans are opaque presentation values with public projections only."
    (let ((span (first (nshell.highlight:highlight-line "| echo nope"))))
      (expect span :to-be-type-of 'nshell.highlight::%highlight-span)
      (expect (find-symbol "HIGHLIGHT-SPAN" :nshell.highlight) :to-be-falsy)))

  (it "terminal-highlight-span-raw-accessors-stay-internal"
    "Highlight span projections stay behind explicit public accessors."
    (let ((span (first (nshell.highlight:highlight-line "| echo nope"))))
      (expect (fboundp 'nshell.highlight::%highlight-span-start) :to-be-truthy)
      (expect (fboundp 'nshell.highlight::%highlight-span-end) :to-be-truthy)
      (expect (fboundp 'nshell.highlight::%highlight-span-role) :to-be-truthy)
      (expect (nshell.highlight:highlight-span-start span) :to-equal (nshell.highlight::%highlight-span-start span))
      (expect (nshell.highlight:highlight-span-end span) :to-equal (nshell.highlight::%highlight-span-end span))
      (expect (nshell.highlight:highlight-span-role span) :to-be (nshell.highlight::%highlight-span-role span))))

  (it "terminal-highlight-uses-public-ansi-boundary"
    "Presentation color rendering depends on the terminal ANSI public contract."
    (expect (fboundp 'nshell.infrastructure.terminal:ansi-color-code) :to-be-truthy)
    (expect (null (find-symbol "ANSI-COLOR-CODE"
                                :nshell.infrastructure.terminal)) :to-be-falsy))

  (it "terminal-alt-right-accepts-compact-redirection-suggestion"
    "Decoded Meta-F applies shell-aware autosuggestion word acceptance."
    (let* ((events (read-key-events-from-string (esc-sequence "f")))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "grep error log"
                    :cursor-pos 14
                    :suggestion " 2>&1 | less")
                   events)))
      (expect "grep error log 2>&1" :to-equal (nshell.presentation:input-state-buffer state))
      (expect 19 :to-equal (nshell.presentation:input-state-cursor-pos state))
      (expect " | less" :to-equal (nshell.presentation:input-state-suggestion state))))

  (it "terminal-ctrl-e-at-eol-accepts-autosuggestion"
    "Decoded Ctrl-E accepts the complete autosuggestion tail at line end."
    (let* ((events (read-key-events-from-string (string (code-char 5))))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "git"
                    :cursor-pos 3
                    :suggestion " status")
                   events)))
      (expect "git status" :to-equal (nshell.presentation:input-state-buffer state))
      (expect 10 :to-equal (nshell.presentation:input-state-cursor-pos state))
      (expect (nshell.presentation:input-state-suggestion state) :to-be-null)))

  (it "terminal-ctrl-g-cancels-visible-autosuggestion"
    "Decoded Ctrl-G dismisses the visible autosuggestion without editing text."
    (let* ((events (read-key-events-from-string (string (code-char 7))))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "git"
                    :cursor-pos 2
                    :suggestion " status")
                   events)))
      (expect "git" :to-equal (nshell.presentation:input-state-buffer state))
      (expect 2 :to-equal (nshell.presentation:input-state-cursor-pos state))
      (expect (nshell.presentation:input-state-suggestion state) :to-be-null)))

  (it "terminal-history-navigation-refreshes-autosuggestion"
    "History recall should restore the buffer and recompute its autosuggestion."
    (with-repl-history-lines ("git st")
      (nshell.domain.completion:kb-add-command
       nshell.presentation::*kb*
       "git"
       :subcommands '("status"))
      (with-repl-input-state (:buffer "git" :cursor-pos 3)
        (multiple-value-bind (next-state output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :up))
          (expect :history-prev :to-be output)
          (setf nshell.presentation::*input-state* next-state)
          (capture-process-output-event output))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "git st"
                        :cursor-pos 6
                        :suggestion "atus")))))
