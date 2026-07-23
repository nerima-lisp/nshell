(in-package #:nshell/test)

(describe "repl-tests"
  (it "repl-rendered-position-normalizes-long-prompt-width"
    "Prompt width should contribute terminal-wrapped rows before input cursor math starts."
    (let ((position (nshell.presentation::%rendered-buffer-position "" 0 12
                                                                    :terminal-width 10)))
      (expect 1 :to-equal (nshell.presentation::rendered-position-row position))
      (expect 2 :to-equal (nshell.presentation::rendered-position-column position)))
    (let ((position (nshell.presentation::%rendered-buffer-position "abc" 3 12
                                                                    :terminal-width 10)))
      (expect 1 :to-equal (nshell.presentation::rendered-position-row position))
      (expect 5 :to-equal (nshell.presentation::rendered-position-column position)))
    (expect 2 :to-equal (nshell.presentation::%rendered-buffer-line-count
            ""
            :terminal-width 10
            :prompt-width 12))
    (expect 3 :to-equal (nshell.presentation::%rendered-buffer-line-count
            "abcdefghi"
            :terminal-width 10
            :prompt-width 12)))

  (it "repl-rendered-position-accessors-stay-behind-public-projections"
    "Rendered position storage readers and predicates should stay internal to presentation rendering."
    (let ((position (nshell.presentation::%rendered-buffer-position "abc" 3 12
                                                                    :terminal-width 10)))
      (expect (nshell.presentation::%rendered-position-p position) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::rendered-position-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::%rendered-position-row) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%rendered-position-column) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::make-rendered-position) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::%make-rendered-position) :to-be-truthy)
      (expect (nshell.presentation::rendered-position-row position) :to-equal (nshell.presentation::%rendered-position-row position))
      (expect (nshell.presentation::rendered-position-column position) :to-equal (nshell.presentation::%rendered-position-column position))))

  (it "repl-rendered-line-count-includes-wrapped-suggestion"
    "Prompt clearing should track terminal rows introduced by autosuggestion wrapping."
    (expect 2 :to-equal (nshell.presentation::%rendered-buffer-line-count
            "abc"
            :suggestion "defgh"
            :terminal-width 10
            :prompt-width 4)))

  (it "repl-render-prompt-tracks-terminal-wrapped-lines"
    "Prompt redraw state should include physical rows from terminal wrapping."
    (with-repl-test-state
      (with-stable-repl-prompt ()
        (with-repl-render-state (:buffer "abcdefg"
                                 :cursor-pos 7
                                 :suggestion "hi")
          (with-fixed-terminal-size (24 10)
            (capture-standard-output
              (nshell.presentation::render-prompt-cont))
            (expect 2 :to-equal nshell.presentation::*prompt-rendered-lines*)
            (expect 1 :to-equal nshell.presentation::*prompt-rendered-cursor-row*))))))

  (it "repl-render-prompt-clears-stale-continuation-lines-before-redraw"
    "A shorter redraw should erase continuation lines left by the previous prompt render."
    (with-repl-test-state
      (setf nshell.presentation::*prompt-rendered-lines* 3
            nshell.presentation::*prompt-rendered-cursor-row* 1)
      (let ((output (capture-standard-output
                      (nshell.presentation::clear-rendered-prompt))))
        (expect (search (esc-sequence "[1B") output) :to-be-truthy)
        (expect 3 :to-equal (loop with needle = (esc-sequence "[2K")
                     for start = 0 then (+ position (length needle))
                     for position = (search needle output :start2 start)
                     while position
                     count position))
        (expect 0 :to-equal nshell.presentation::*prompt-rendered-lines*)
        (expect 0 :to-equal nshell.presentation::*prompt-rendered-cursor-row*))))

  (it "repl-render-prompt-tracks-multiline-render-state"
    "Prompt redraw records enough state to clear a later redraw from the logical cursor row."
    (with-repl-test-state
      (with-stable-repl-prompt ()
        (with-repl-render-state (:buffer (format nil "one~%two")
                                 :cursor-pos 2)
          (with-fixed-terminal-size (24 80)
            (capture-standard-output
              (nshell.presentation::render-prompt-cont))
            (expect 2 :to-equal nshell.presentation::*prompt-rendered-lines*)
            (expect 0 :to-equal nshell.presentation::*prompt-rendered-cursor-row*))))))

  (it "repl-render-prompt-tracks-search-suffix-render-state"
    "Search mode redraw should account for the rendered history suffix in both cursor math and line counts."
    (with-repl-test-state
      (with-stable-repl-prompt ()
        (with-fixed-terminal-size (24 10)
          (with-repl-render-state (:buffer "abc"
                                   :cursor-pos 3
                                   :mode :search
                                   :search-query "git"
                                   :search-original-buffer "abc"
                                   :search-original-cursor 3
                                   :search-index 0)
            (let ((output (capture-standard-output
                            (nshell.presentation::render-prompt-cont))))
              (expect (search "history: git" output) :to-be-truthy)
              (expect (search (esc-sequence "[1A") output) :to-be-truthy)
              (expect (search (esc-sequence "[8G") output) :to-be-truthy)
              (expect 2 :to-equal nshell.presentation::*prompt-rendered-lines*)
              (expect 0 :to-equal nshell.presentation::*prompt-rendered-cursor-row*)))))))

  (it "repl-rendered-position-includes-wrapped-suggestion-and-search-suffix"
    "Cursor restoration should include both wrapped autosuggestion text and the history suffix."
    (expect 3 :to-equal (nshell.presentation::%rendered-buffer-line-count
            "abc"
            :suggestion "defgh"
            :search-suffix " history: git"
            :terminal-width 10
            :prompt-width 0))
    (expect (format nil "~C[2A~C[4G" #\Esc #\Esc) :to-equal (capture-standard-output
           (nshell.presentation::%move-cursor-to-rendered-position
            "abc"
            3
            0
            "defgh"
            " history: git"
            :terminal-width 10)))))
