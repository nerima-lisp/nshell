(in-package #:nshell/test)

(describe "repl-tests"
  (it "repl-non-completion-output-clears-rendered-completion-list"
    "A stale completion menu should be erased before the next non-completion redraw."
    (with-repl-test-state
      (setf nshell.presentation::*config*
            (nshell.domain.configuration:default-config)
            nshell.presentation::*completion-rendered-lines* 2
            nshell.presentation::*prompt-rendered-lines* 3
            nshell.presentation::*prompt-rendered-cursor-row* 0)
      (with-repl-input-state (:buffer "g"
                              :cursor-pos 1
                              :completion-index 0)
        (let ((output (capture-process-output-event :suggest-update)))
          (expect 0 :to-equal nshell.presentation::*completion-rendered-lines*)
          (expect (search (esc-sequence "[2K") output) :to-be-truthy)
          (expect (search (esc-sequence "[A") output) :to-be-truthy)))))

  (it "repl-complete-with-no-candidates-clears-stale-completion-session"
    "A failed completion attempt should not keep an old candidate list alive."
    (with-repl-test-state
      (with-repl-input-state (:buffer ""
                              :cursor-pos 0
                              :completion-index 0
                              :completion-base-buffer "g"
                              :completion-base-cursor 1
                              :last-candidates '("git" "grep"))
        (capture-process-output-event :complete)
        (is-input-state nshell.presentation::*input-state*
                        :buffer ""
                        :cursor-pos 0
                        :completion-index -1
                        :completion-base-buffer nil
                        :completion-base-cursor nil
                        :last-candidates nil
                        :suggestion nil))))

  (it "repl-completion-rendering-starts-below-current-prompt-row"
    "Completion rendering should preserve the edit cursor and draw below all prompt rows."
    (with-repl-test-state
      (setf nshell.presentation::*config*
            (nshell.domain.configuration:default-config)
            nshell.presentation::*prompt-rendered-lines* 3
            nshell.presentation::*prompt-rendered-cursor-row* 0)
      (nshell.domain.completion:kb-add-command nshell.presentation::*kb*
                                               "git"
                                               :description "record changes")
      (nshell.domain.completion:kb-add-command nshell.presentation::*kb*
                                               "grep"
                                               :description "search text")
      (with-repl-input-state (:buffer "g"
                              :cursor-pos 1
                              :completion-index 0)
        (let ((output (capture-process-output-event :complete)))
          (expect (search (esc-sequence "7") output) :to-be-truthy)
          (expect (search (format nil "~a~%" (esc-sequence "[2B")) output) :to-be-truthy)
          (expect (search "git" output) :to-be-truthy)
          (expect (search (esc-sequence "8") output) :to-be-truthy)))))

  (it "repl-completion-tab-extends-unambiguous-common-prefix"
    "Fresh completion should first advance the current token to the shared candidate prefix."
    (with-repl-test-state
      (nshell.domain.completion:kb-add-command nshell.presentation::*kb*
                                               "checkout"
                                               :description "switch branch")
      (nshell.domain.completion:kb-add-command nshell.presentation::*kb*
                                               "check-ignore"
                                               :description "debug ignores")
      (with-repl-input-state (:buffer "ch"
                              :cursor-pos 2)
        (let ((output (capture-process-output-event :complete)))
          (is-input-state nshell.presentation::*input-state*
                          :buffer "check"
                          :cursor-pos 5
                          :completion-index -1)
          (expect 2 :to-equal (length (nshell.presentation:input-state-last-candidates
                          nshell.presentation::*input-state*)))
          (expect nshell.presentation::*completion-rendered-lines* :to-be-greater-than 0)
          (expect (search "checkout" output) :to-be-truthy)
          (expect (search "check-ignore" output) :to-be-truthy)))))

  (it "repl-completion-clear-restores-cursor-after-erasing-below-prompt"
    "Completion clearing should erase the saved menu below the prompt without moving the edit cursor."
    (with-repl-test-state
      (setf nshell.presentation::*prompt-rendered-lines* 3
            nshell.presentation::*prompt-rendered-cursor-row* 0
            nshell.presentation::*completion-rendered-lines* 2)
      (let ((output
              (capture-standard-output
                (nshell.presentation::clear-rendered-completions))))
        (expect (search (esc-sequence "7") output) :to-be-truthy)
        (expect (search (esc-sequence "[5B") output) :to-be-truthy)
        (expect (search (esc-sequence "[A") output) :to-be-truthy)
        (expect (search (esc-sequence "8") output) :to-be-truthy)
        (expect 0 :to-equal nshell.presentation::*completion-rendered-lines*))))

  (it "repl-clear-screen-clears-terminal-and-keeps-input-state"
    "Ctrl-L should clear the terminal, reset render bookkeeping, and leave the edit session intact."
    (with-repl-test-state
      (setf nshell.presentation::*prompt-rendered-lines* 2
            nshell.presentation::*prompt-rendered-cursor-row* 1
            nshell.presentation::*completion-rendered-lines* 3)
      ;; Pin the prompt width and terminal size so the post-clear re-render
      ;; produces a deterministic single line regardless of the ambient working
      ;; directory (the default prompt renders the cwd, which is a long path in
      ;; the build sandbox and would otherwise wrap "git status" onto a 2nd row).
      (with-stable-repl-prompt (:width 4 :text "ns> ")
       (with-fixed-terminal-size (24 80)
        (with-repl-input-state (:buffer "git"
                              :cursor-pos 3
                              :completion-index 0
                              :completion-base-buffer "git"
                              :completion-base-cursor 3
                              :last-candidates '("git" "grep")
                              :suggestion " status")
          (let ((output
                (capture-process-output-event :clear-screen)))
          (expect (search (esc-sequence "[2J") output) :to-be-truthy)
          (expect (search (esc-sequence "[1;1H") output) :to-be-truthy)
          (expect 1 :to-equal nshell.presentation::*prompt-rendered-lines*)
          (expect 0 :to-equal nshell.presentation::*prompt-rendered-cursor-row*)
          (expect 0 :to-equal nshell.presentation::*completion-rendered-lines*)
          (is-input-state nshell.presentation::*input-state*
                          :buffer "git"
                          :cursor-pos 3
                          :completion-index 0
                          :completion-base-buffer "git"
                          :completion-base-cursor 3
                          :last-candidates '("git" "grep")
                          :suggestion " status")))))))

  (it "repl-insert-last-history-argument-updates-input-and-undo-stack"
    "The REPL handler resolves Alt-dot against history and records a local undo point."
    (with-repl-history-lines ("git status --short")
      (with-repl-input-state (:buffer "echo " :cursor-pos 5)
        (capture-process-output-event :insert-last-argument)
        (is-input-state nshell.presentation::*input-state*
                        :buffer "echo --short"
                        :cursor-pos 12
                        :last-argument-start 5
                        :last-argument-end 12
                        :last-argument-index 0)
        (multiple-value-bind (undone output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :ctrl-underscore))
          (expect :suggest-update :to-be output)
          (is-input-state undone :buffer "echo " :cursor-pos 5)))))

  (it "repl-insert-last-history-argument-skips-leading-assignments"
    "Alt-dot should ignore leading shell assignments before inserting the last argument."
    (with-repl-history-lines ("A=1 B=2 git status --short")
      (with-repl-input-state (:buffer "echo " :cursor-pos 5)
        (capture-process-output-event :insert-last-argument)
        (is-input-state nshell.presentation::*input-state*
                        :buffer "echo --short"
                        :cursor-pos 12
                        :last-argument-start 5
                        :last-argument-end 12
                        :last-argument-index 0))))

  (it "repl-insert-last-history-argument-preserves-escaped-space-arguments"
    "Alt-dot should insert a logical shell word with escaped spaces unchanged."
    (with-repl-history-lines ("echo my\\ file.txt")
      (with-repl-input-state (:buffer "cp " :cursor-pos 3)
        (capture-process-output-event :insert-last-argument)
        (is-input-state nshell.presentation::*input-state*
                        :buffer "cp my\\ file.txt"
                        :cursor-pos (+ 3 (length "my\\ file.txt"))
                        :last-argument-start 3
                        :last-argument-end (+ 3 (length "my\\ file.txt"))
                        :last-argument-index 0)
        (multiple-value-bind (undone output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :ctrl-underscore))
          (expect :suggest-update :to-be output)
          (is-input-state undone :buffer "cp " :cursor-pos 3)))))

  (it "repl-insert-last-history-argument-cycles-older-arguments"
    "Repeated Alt-dot replaces the previous insertion with older history arguments."
    (with-repl-history-lines ("echo older" "git status --short")
      (with-repl-input-state (:buffer "echo " :cursor-pos 5)
        (capture-process-output-event :insert-last-argument)
        (capture-process-output-event :insert-last-argument)
        (is-input-state nshell.presentation::*input-state*
                        :buffer "echo older"
                        :cursor-pos 10
                        :last-argument-start 5
                        :last-argument-end 10
                        :last-argument-index 1)
        (multiple-value-bind (undone output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :ctrl-underscore))
          (expect :suggest-update :to-be output)
          (is-input-state undone
                          :buffer "echo --short"
                          :cursor-pos 12
                          :last-argument-start nil
                          :last-argument-end nil
                          :last-argument-index nil)))))

  (it "repl-render-prompt-restores-midline-cursor-with-visible-width"
    "Redraw should place the terminal cursor at the logical edit cursor, counting CJK width."
    (with-repl-test-state
      (with-stable-repl-prompt ()
        (with-fixed-terminal-size (24 80)
          (with-repl-render-state (:buffer "echo あbc"
                                   :cursor-pos 5
                                   :suggestion " --help")
            (let ((output (capture-standard-output
                            (nshell.presentation::render-prompt-cont))))
              (expect (search (esc-sequence "[11D") output) :to-be-truthy)))))))

  (it "repl-render-prompt-keeps-cursor-at-eol"
    "Cursor-left rendering should be silent when the edit cursor is at the visible end."
    (expect 0 :to-equal (nshell.presentation::%cursor-tail-visible-width "echo あ" 6 nil nil))
    (expect "" :to-equal (capture-standard-output
                   (nshell.presentation::%move-cursor-to-rendered-position
                    "echo あ"
                    6
                    0
                    nil
                    nil))))

  (it "repl-render-prompt-restores-cursor-across-continuation-lines"
    "Multiline redraw should move up to the logical edit line and restore its absolute column."
    (let ((text (format nil "echo あ~%second")))
      (let ((position (nshell.presentation::%rendered-buffer-position text 6 7)))
        (expect 0 :to-equal (nshell.presentation::rendered-position-row position))
        (expect 14 :to-equal (nshell.presentation::rendered-position-column position)))
      (let ((output (capture-standard-output
                      (nshell.presentation::%move-cursor-to-rendered-position
                       text
                       6
                       7
                       " --help"
                       nil))))
        (expect (search (esc-sequence "[1A") output) :to-be-truthy)
        (expect (search (esc-sequence "[15G") output) :to-be-truthy))))

  (it "repl-rendered-position-wraps-at-terminal-width"
    "Rendered cursor math should include terminal wrapping, not only logical newlines."
    (let ((position (nshell.presentation::%rendered-buffer-position "abcdefgh" 8 4
                                                                    :terminal-width 10)))
      (expect 1 :to-equal (nshell.presentation::rendered-position-row position))
      (expect 2 :to-equal (nshell.presentation::rendered-position-column position)))
    (let ((position (nshell.presentation::%rendered-buffer-position "あいうえ" 4 4
                                                                    :terminal-width 10)))
      (expect 1 :to-equal (nshell.presentation::rendered-position-row position))
      (expect 2 :to-equal (nshell.presentation::rendered-position-column position))))

  (it "repl-complete-renders-a-valid-existing-session"
    "Completion redraw should reuse candidates from a valid existing session."
    (with-repl-test-state
      (with-stable-repl-prompt ()
        (with-fixed-terminal-size (24 80)
          (with-repl-input-state (:buffer "git"
                                  :cursor-pos 3
                                  :completion-index 0
                                  :completion-base-buffer "g"
                                  :completion-base-cursor 1
                                  :last-candidates '("git" "grep"))
            (let ((output (capture-process-output-event :complete)))
              (expect (search "git" output) :to-be-truthy)
              (expect nshell.presentation::*completion-rendered-lines*
                      :to-be-greater-than 0)))))))
)
