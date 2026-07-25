(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-alt-t-participates-in-undo"
    (let ((state (input-state :buffer "echo one two" :cursor-pos 12)))
      (with-reduced-input-state (transposed) (reduce-once state :alt-t)
        (with-reduced-input-state (undone output) (reduce-once transposed :ctrl-underscore)
          (is-input-state undone :buffer "echo one two" :cursor-pos 12)
          (expect :suggest-update :to-be output)))))

  (it "input-state-alt-u-upcases-word-at-cursor"
    (let ((state (completion-session-state
                  :buffer "echo hello world"
                  :cursor-pos 5
                  :completion-index 2
                  :suggestion " ignored")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :alt-u)
          :suggest-update
          (:buffer "echo HELLO world"
           :cursor-pos 10
           :completion-index -1
           :suggestion nil))))

  ;; Every case here applies a single alt-case reduction and checks the
  ;; resulting buffer/cursor; only which key, which case transform, and what
  ;; counts as a word boundary differ per case.
  (it-each (("downcases the next word after the cursor"
             "echo   WORLD tail" 4 :alt-l
             "echo   world tail" 12)
            ("capitalizes a quoted token"
             "echo \"HELLO world\" tail" 5 :alt-c
             "echo \"Hello world\" tail" 18)
            ("treats shell operators as word boundaries"
             "echo one|two" 8 :alt-u
             "echo one|TWO" 12))
      "input-state-alt-case ~A"
      (description buffer cursor key expected-buffer expected-cursor)
    (declare (ignore description))
    (let ((state (input-state :buffer buffer :cursor-pos cursor)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state key)
          :suggest-update
          (:buffer expected-buffer :cursor-pos expected-cursor))))

  (it "input-state-alt-case-noops-without-word"
    (with-expected-noop-input-state-reductions (new-state output)
        :alt-u
        (list (input-state :buffer "" :cursor-pos 0)
              (input-state :buffer "   |" :cursor-pos 4))))

  (it "input-state-alt-u-participates-in-undo"
    (let ((state (input-state :buffer "echo hello" :cursor-pos 5)))
      (with-reduced-input-state (upcased) (reduce-once state :alt-u)
        (with-reduced-input-state (undone output) (reduce-once upcased :ctrl-underscore)
          (is-input-state undone :buffer "echo hello" :cursor-pos 5)
          (expect :suggest-update :to-be output)))))

  (it "input-state-ctrl-underscore-undoes-last-edit"
    (let ((state (apply-key-events-to-input-state
                  (input-state)
                  (list (input-key-event :char #\a)
                        (input-key-event :char #\b)
                        (input-key-event :char #\c)))))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-underscore)
          :suggest-update
          (:buffer "ab" :cursor-pos 2))))

  (it "input-state-alt-r-redoes-undone-edit"
    (let ((state (apply-key-events-to-input-state
                  (input-state)
                  (list (input-key-event :char #\a)
                        (input-key-event :char #\b)
                        (input-key-event :char #\c)))))
      (with-reduced-input-state (undone) (reduce-once state :ctrl-underscore)
        (with-reduced-input-state (redone output) (reduce-once undone :alt-r)
          (is-input-state redone :buffer "abc" :cursor-pos 3)
          (expect :suggest-update :to-be output)))))

  (it "input-state-navigation-is-not-an-undo-step"
    (let ((typed (apply-key-events-to-input-state
                  (input-state)
                  (list (input-key-event :char #\a)
                        (input-key-event :char #\b)
                        (input-key-event :char #\c)))))
      (with-reduced-input-state (moved) (reduce-once typed :ctrl-b)
        (with-reduced-input-state (edited) (reduce-once moved :char #\X)
          (with-reduced-input-state (undone output) (reduce-once edited :ctrl-underscore)
            (is-input-state undone :buffer "abc" :cursor-pos 2)
            (expect :suggest-update :to-be output))))))

  (it "input-state-new-edit-clears-redo-stack"
    (let ((state (apply-key-events-to-input-state
                  (input-state)
                  (list (input-key-event :char #\a)
                        (input-key-event :char #\b)))))
      (with-reduced-input-state (undone) (reduce-once state :ctrl-underscore)
        (with-reduced-input-state (edited) (reduce-once undone :char #\X)
          (with-reduced-input-state (redone output) (reduce-once edited :alt-r)
            (is-input-state redone :buffer "aX" :cursor-pos 2)
            (expect :none :to-be output))))))

  (it "input-state-kill-and-yank-participate-in-undo-redo"
    (let ((state (input-state :buffer "echo one two" :cursor-pos 12)))
      (with-reduced-input-state (killed) (reduce-once state :ctrl-w)
        (with-reduced-input-state (undone undo-output) (reduce-once killed :ctrl-underscore)
          (is-input-state undone :buffer "echo one two" :cursor-pos 12)
          (expect :suggest-update :to-be undo-output)
          (with-reduced-input-state (redone redo-output) (reduce-once undone :alt-r)
            (is-input-state redone :buffer "echo one " :cursor-pos 9)
            (expect :suggest-update :to-be redo-output)))))))
