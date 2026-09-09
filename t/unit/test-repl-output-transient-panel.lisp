(in-package #:nshell/test)

(describe "repl-output-transient-panel-tests"
  (it "renders-a-value-panel-with-terminal-bounded-height"
    (with-repl-test-state
      (with-stable-repl-prompt (:text "PROMPT> " :width 8)
        (with-fixed-terminal-size (6 24)
          (let ((output
                  (capture-standard-output
                    (setf nshell.presentation::*prompt-rendered-lines* 1)
                    (nshell.presentation:render-transient-panel
                     '("first" "second" "third" "fourth"))))
                (lines 0))
            (loop for character across output
                  when (char= character #\Newline)
                    do (incf lines))
            (expect 5 :to-equal lines)
            (expect (search "┌──────────────────────┐" output)
                    :to-be-truthy)
            (expect (search "│ …" output)
                    :to-be-truthy)
            (expect (search "fourth" output)
                    :to-be-truthy)
            (expect 4 :to-equal
                    nshell.presentation::*transient-panel-rendered-lines*))))))

  (it "updates-and-clears-the-rendered-panel"
    (with-repl-test-state
      (with-stable-repl-prompt (:text "PROMPT> " :width 8)
        (with-fixed-terminal-size (24 30)
          (setf nshell.presentation::*prompt-rendered-lines* 1)
          (capture-standard-output
            (nshell.presentation:render-transient-panel '("old")))
          (let ((output
                  (capture-standard-output
                    (nshell.presentation:update-transient-panel '("new")))))
            (expect (search "old" output) :to-be-null)
            (expect (search "new" output) :to-be-truthy)
            (expect 3 :to-equal
                    nshell.presentation::*transient-panel-rendered-lines*)
            (let ((clear-output
                    (capture-standard-output
                      (nshell.presentation:clear-rendered-transient-panel))))
              (expect (search "new" clear-output) :to-be-null)
              (expect 0 :to-equal
                      nshell.presentation::*transient-panel-rendered-lines*)))))))

  (it "leaves-no-panel-when-the-prompt-consumes-the-terminal-height"
    (with-repl-test-state
      (with-fixed-terminal-size (2 20)
        (setf nshell.presentation::*prompt-rendered-lines* 1)
        (let ((output
                (capture-standard-output
                  (nshell.presentation:render-transient-panel '("hidden")))))
          (expect "" :to-equal output)
          (expect 0 :to-equal
                  nshell.presentation::*transient-panel-rendered-lines*)))))

  (it "clears-the-panel-before-redrawing-the-prompt"
    (with-repl-test-state
      (with-stable-repl-prompt (:text "PROMPT> " :width 8)
        (with-fixed-terminal-size (24 30)
          (with-repl-input-state (:buffer "" :cursor-pos 0)
            (setf nshell.presentation::*prompt-rendered-lines* 1)
            (capture-standard-output
              (nshell.presentation:render-transient-panel '("stale")))
            (let ((output
                    (capture-standard-output
                      (nshell.presentation::render-prompt-cont))))
              (expect (search "PROMPT> " output) :to-be-truthy)
              (expect 0 :to-equal
                      nshell.presentation::*transient-panel-rendered-lines*)))))))

  (it "redraws-the-panel-after-a-terminal-resize"
    (with-repl-test-state
      (with-stable-repl-prompt (:text "PROMPT> " :width 8)
        (with-fixed-terminal-size (24 30)
          (with-repl-input-state (:buffer "" :cursor-pos 0)
            (setf nshell.presentation::*prompt-rendered-lines* 1)
            (capture-standard-output
              (nshell.presentation:render-transient-panel '("resized")))
            (let ((output
                    (with-temporary-function
                        ('nshell.infrastructure.acl:consume-terminal-resize-p
                         (lambda () t))
                      (capture-standard-output
                        (let ((continuation
                                (nshell.presentation::read-key-cont)))
                          (funcall continuation))))))
              (expect (search "PROMPT> " output) :to-be-truthy)
              (expect (search "resized" output) :to-be-truthy)
              (expect 3 :to-equal
                      nshell.presentation::*transient-panel-rendered-lines*))))))))
