(in-package #:nshell/test)

(describe "repl-assistant-progress-tests"
  (it "shows-elapsed-seconds-while-the-model-is-thinking"
    (let ((lines
            (nshell.presentation:assistant-progress-lines
             0
             :current-time
             (* 3/2 internal-time-units-per-second))))
      (expect 1 :to-equal (length lines))
      (expect (search "thinking… 1s" (first lines)) :to-be-truthy)
      (expect (search "⌃C cancel" (first lines)) :to-be-truthy)
      (expect (search "まだ待つ" (first lines)) :to-be-null)))

  (it "offers-a-wait-or-abandon-choice-after-the-observed-delay-window"
    (let ((lines
            (nshell.presentation:assistant-progress-lines
             0
             :current-time
             (* 15 internal-time-units-per-second))))
      (expect (search "thinking… 15s" (first lines)) :to-be-truthy)
      (expect (search "まだ待つ / 諦める" (first lines)) :to-be-truthy)))

  (it "renders-progress-as-a-value-driven-transient-panel"
    (with-repl-test-state
      (with-fixed-terminal-size (12 60)
        (setf nshell.presentation::*prompt-rendered-lines* 1)
        (let ((output
                (capture-standard-output
                  (nshell.presentation:render-assistant-progress-panel
                   0
                   :current-time (* 2 internal-time-units-per-second)
                   :terminal-width 60))))
          (expect (search "thinking… 2s · ⌃C cancel" output)
                  :to-be-truthy)
          (expect 3 :to-equal
                  nshell.presentation::*transient-panel-rendered-lines*))))))
