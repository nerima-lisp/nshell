(in-package #:nshell/test)
(in-suite repl-tests)

(test repl-rendered-position-normalizes-long-prompt-width
  "Prompt width should contribute terminal-wrapped rows before input cursor math starts."
  (let ((position (nshell.presentation::%rendered-buffer-position "" 0 12
                                                                  :terminal-width 10)))
    (is (= 1 (nshell.presentation::rendered-position-row position)))
    (is (= 2 (nshell.presentation::rendered-position-column position))))
  (let ((position (nshell.presentation::%rendered-buffer-position "abc" 3 12
                                                                  :terminal-width 10)))
    (is (= 1 (nshell.presentation::rendered-position-row position)))
    (is (= 5 (nshell.presentation::rendered-position-column position))))
  (is (= 2
         (nshell.presentation::%rendered-buffer-line-count
          ""
          :terminal-width 10
          :prompt-width 12)))
  (is (= 3
         (nshell.presentation::%rendered-buffer-line-count
          "abcdefghi"
          :terminal-width 10
          :prompt-width 12))))

(test repl-rendered-position-accessors-stay-behind-public-projections
  "Rendered position storage readers and predicates should stay internal to presentation rendering."
  (let ((position (nshell.presentation::%rendered-buffer-position "abc" 3 12
                                                                  :terminal-width 10)))
    (is (nshell.presentation::%rendered-position-p position))
    (is (not (fboundp 'nshell.presentation::rendered-position-p)))
    (is (fboundp 'nshell.presentation::%rendered-position-row))
    (is (fboundp 'nshell.presentation::%rendered-position-column))
    (is (not (fboundp 'nshell.presentation::make-rendered-position)))
    (is (fboundp 'nshell.presentation::%make-rendered-position))
    (is (= (nshell.presentation::rendered-position-row position)
           (nshell.presentation::%rendered-position-row position)))
    (is (= (nshell.presentation::rendered-position-column position)
           (nshell.presentation::%rendered-position-column position)))))

(test repl-rendered-line-count-includes-wrapped-suggestion
  "Prompt clearing should track terminal rows introduced by autosuggestion wrapping."
  (is (= 2
         (nshell.presentation::%rendered-buffer-line-count
          "abc"
          :suggestion "defgh"
          :terminal-width 10
          :prompt-width 4))))

(test repl-render-prompt-tracks-terminal-wrapped-lines
  "Prompt redraw state should include physical rows from terminal wrapping."
  (with-repl-test-state
    (with-stable-repl-prompt ()
      (with-repl-render-state (:buffer "abcdefg"
                               :cursor-pos 7
                               :suggestion "hi")
        (with-fixed-terminal-size (24 10)
          (capture-standard-output
            (nshell.presentation::render-prompt-cont))
          (is (= 2 nshell.presentation::*prompt-rendered-lines*))
          (is (= 1 nshell.presentation::*prompt-rendered-cursor-row*)))))))

(test repl-render-prompt-clears-stale-continuation-lines-before-redraw
  "A shorter redraw should erase continuation lines left by the previous prompt render."
  (with-repl-test-state
    (setf nshell.presentation::*prompt-rendered-lines* 3
          nshell.presentation::*prompt-rendered-cursor-row* 1)
    (let ((output (capture-standard-output
                    (nshell.presentation::clear-rendered-prompt))))
      (is (search (esc-sequence "[1B") output))
      (is (= 3
             (loop with needle = (esc-sequence "[2K")
                   for start = 0 then (+ position (length needle))
                   for position = (search needle output :start2 start)
                   while position
                   count position)))
      (is (= 0 nshell.presentation::*prompt-rendered-lines*))
      (is (= 0 nshell.presentation::*prompt-rendered-cursor-row*)))))

(test repl-render-prompt-tracks-multiline-render-state
  "Prompt redraw records enough state to clear a later redraw from the logical cursor row."
  (with-repl-test-state
    (with-stable-repl-prompt ()
      (with-repl-render-state (:buffer (format nil "one~%two")
                               :cursor-pos 2)
        (with-fixed-terminal-size (24 80)
          (capture-standard-output
            (nshell.presentation::render-prompt-cont))
          (is (= 2 nshell.presentation::*prompt-rendered-lines*))
          (is (= 0 nshell.presentation::*prompt-rendered-cursor-row*)))))))

(test repl-render-prompt-tracks-search-suffix-render-state
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
            (is (search "history: git" output))
            (is (search (esc-sequence "[1A") output))
            (is (search (esc-sequence "[8G") output))
            (is (= 2 nshell.presentation::*prompt-rendered-lines*))
            (is (= 0 nshell.presentation::*prompt-rendered-cursor-row*))))))))

(test repl-rendered-position-includes-wrapped-suggestion-and-search-suffix
  "Cursor restoration should include both wrapped autosuggestion text and the history suffix."
  (is (= 3
         (nshell.presentation::%rendered-buffer-line-count
          "abc"
          :suggestion "defgh"
          :search-suffix " history: git"
          :terminal-width 10
          :prompt-width 0)))
  (is (string=
       (format nil "~C[2A~C[4G" #\Esc #\Esc)
       (capture-standard-output
         (nshell.presentation::%move-cursor-to-rendered-position
          "abc"
          3
          0
          "defgh"
          " history: git"
          :terminal-width 10)))))
