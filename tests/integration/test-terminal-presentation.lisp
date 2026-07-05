(in-package #:nshell/test)

(in-suite terminal-integration-tests)

(test terminal-enter-on-incomplete-input-continues-buffer
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
      (is (string= (format nil "~a~%" line)
                   (nshell.presentation:input-state-buffer state)))
      (is (= (length (nshell.presentation:input-state-buffer state))
             (nshell.presentation:input-state-cursor-pos state))))))

(test terminal-execute-on-structural-incomplete-input-indents-continuation
  "REPL execution promotes structural incomplete input to an indented continuation."
  (with-repl-test-state
    (dolist (case '(("echo hi |" . "echo hi |~%  ")
                    ("echo hi &&" . "echo hi &&~%  ")
                    ("if true" . "if true~%  ")))
      (destructuring-bind (line . expected-format) case
        (setf nshell.presentation::*input-state*
              (nshell.presentation::make-repl-input-state :buffer line))
        (capture-process-output-event :execute)
        (is (string= (format nil expected-format)
                     (nshell.presentation:input-state-buffer
                      nshell.presentation::*input-state*)))
        (is (= (length (nshell.presentation:input-state-buffer
                        nshell.presentation::*input-state*))
               (nshell.presentation:input-state-cursor-pos
                nshell.presentation::*input-state*)))))))

(test terminal-highlight-uses-parser-diagnostics
  "Presentation highlighting marks parser diagnostics as errors."
  (let* ((spans (nshell.presentation:highlight-line "| echo nope"))
         (first-span (first spans)))
    (is (not (null first-span)))
    (is (eq :error (nshell.presentation:highlight-span-role first-span)))
    (is (= 0 (nshell.presentation:highlight-span-start first-span)))
    (is (= 1 (nshell.presentation:highlight-span-end first-span)))))

(test terminal-highlight-span-constructor-is-internal-boundary
  "Highlight spans are produced by highlight-line rather than public raw construction."
  (is (not (fboundp 'nshell.presentation::make-highlight-span)))
  (is (not (fboundp 'nshell.presentation::highlight-span-p)))
  (is (not (fboundp 'nshell.presentation::copy-highlight-span)))
  (is (fboundp 'nshell.presentation::%make-highlight-span)))

(test terminal-highlight-span-type-is-internal-boundary
  "Highlight spans are opaque presentation values with public projections only."
  (let ((span (first (nshell.presentation:highlight-line "| echo nope"))))
    (is (typep span 'nshell.presentation::%highlight-span))
    (is (not (find-symbol "HIGHLIGHT-SPAN" :nshell.presentation)))))

(test terminal-highlight-span-raw-accessors-stay-internal
  "Highlight span projections stay behind explicit public accessors."
  (let ((span (first (nshell.presentation:highlight-line "| echo nope"))))
    (is (fboundp 'nshell.presentation::%highlight-span-start))
    (is (fboundp 'nshell.presentation::%highlight-span-end))
    (is (fboundp 'nshell.presentation::%highlight-span-role))
    (is (= (nshell.presentation:highlight-span-start span)
           (nshell.presentation::%highlight-span-start span)))
    (is (= (nshell.presentation:highlight-span-end span)
           (nshell.presentation::%highlight-span-end span)))
    (is (eq (nshell.presentation:highlight-span-role span)
            (nshell.presentation::%highlight-span-role span)))))

(test terminal-highlight-uses-public-ansi-boundary
  "Presentation color rendering depends on the terminal ANSI public contract."
  (is (fboundp 'nshell.infrastructure.terminal:ansi-color-code))
  (is (not (null (find-symbol "ANSI-COLOR-CODE"
                              :nshell.infrastructure.terminal)))))

(test terminal-screen-render-roundtrip-with-input-state
  "Decoded input can update presentation state and render through the virtual screen."
  (let* ((state (input-state))
         (events (read-key-events-from-string "abc"))
         (next-state (apply-key-events-to-input-state state events))
         (old (nshell.infrastructure.terminal:make-screen :width 8 :height 1))
         (new (nshell.infrastructure.terminal:make-screen :width 8 :height 1)))
    (is (string= "abc" (nshell.presentation:input-state-buffer next-state)))
    (nshell.infrastructure.terminal:screen-put-line
     new 0 (nshell.presentation:input-state-buffer next-state))
    (let ((output (with-output-to-string (stream)
                    (nshell.infrastructure.terminal:screen-render old new :stream stream))))
      (is (search "a" output))
      (is (search "b" output))
      (is (search "c" output)))))

(test terminal-alt-right-accepts-compact-redirection-suggestion
  "Decoded Meta-F applies shell-aware autosuggestion word acceptance."
  (let* ((events (read-key-events-from-string (esc-sequence "f")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "grep error log"
                  :cursor-pos 14
                  :suggestion " 2>&1 | less")
                 events)))
    (is (string= "grep error log 2>&1"
                 (nshell.presentation:input-state-buffer state)))
    (is (= 19 (nshell.presentation:input-state-cursor-pos state)))
    (is (string= " | less"
                 (nshell.presentation:input-state-suggestion state)))))

(test terminal-ctrl-e-at-eol-accepts-autosuggestion
  "Decoded Ctrl-E accepts the complete autosuggestion tail at line end."
  (let* ((events (read-key-events-from-string (string (code-char 5))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :suggestion " status")
                 events)))
    (is (string= "git status"
                 (nshell.presentation:input-state-buffer state)))
    (is (= 10 (nshell.presentation:input-state-cursor-pos state)))
    (is (null (nshell.presentation:input-state-suggestion state)))))

(test terminal-ctrl-g-cancels-visible-autosuggestion
  "Decoded Ctrl-G dismisses the visible autosuggestion without editing text."
  (let* ((events (read-key-events-from-string (string (code-char 7))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 2
                  :suggestion " status")
                 events)))
    (is (string= "git"
                 (nshell.presentation:input-state-buffer state)))
    (is (= 2 (nshell.presentation:input-state-cursor-pos state)))
    (is (null (nshell.presentation:input-state-suggestion state)))))

(test terminal-history-navigation-refreshes-autosuggestion
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
        (is (eq :history-prev output))
        (setf nshell.presentation::*input-state* next-state)
        (capture-process-output-event output))
      (is-input-state nshell.presentation::*input-state*
                      :buffer "git st"
                      :cursor-pos 6
                      :suggestion "atus"))))
