(in-package #:nshell/test)

;;; Vi-mode reducer behavior. ESC only enters vi normal mode when
;;; *VI-MODE-ENABLED* is true. Most tests start from a command-mode fixture.

(describe "input-state-tests"
  (it "vi-escape-enters-command-mode-and-moves-left"
    (with-vi-command-state (cmd (input-state :buffer "echo hi" :cursor-pos 7))
      (is-vi-command-state cmd :cursor-pos 6)))

  (it "vi-escape-is-inert-without-vi-mode"
    (let ((state (input-state :buffer "echo hi" :cursor-pos 7)))
      (with-reduced-input-state (after) (reduce-once state :escape)
        (is-input-state after :mode :insert :cursor-pos 7))))

  (it "vi-hl-motion-and-bounds"
    (with-vi-command-state (cmd (input-state :buffer "abc" :cursor-pos 1))
      ;; ESC moved cursor 1 -> 0; l advances, h retreats, both clamped.
      (with-reduced-input-state (r1) (reduce-once cmd :char #\l)
        (is-input-state r1 :cursor-pos 1)
        (with-reduced-input-state (r2) (reduce-once r1 :char #\l)
          (is-input-state r2 :cursor-pos 2)
          ;; last column for "abc" in command mode is 2; cannot pass it.
          (with-reduced-input-state (r3) (reduce-once r2 :char #\l)
            (is-input-state r3 :cursor-pos 2)
          (with-reduced-input-state (r4) (reduce-once r3 :char #\h)
              (is-input-state r4 :cursor-pos 1)))))))

  (it "vi-line-jumps-0-and-dollar"
    (with-vi-command-state (cmd (input-state :buffer "hello" :cursor-pos 2))
      (with-reduced-input-state (s0) (reduce-once cmd :char #\0)
        (is-input-state s0 :cursor-pos 0))
      (with-reduced-input-state (se) (reduce-once cmd :char #\$)
        (is-input-state se :cursor-pos 4))))

  (it "vi-i-returns-to-insert-mode"
    (with-vi-command-state (cmd (input-state :buffer "abc" :cursor-pos 0))
      (with-reduced-input-state (ins) (reduce-once cmd :char #\i)
        (is-input-state ins :mode :insert))
      ;; A enters insert at end of line.
      (with-reduced-input-state (app) (reduce-once cmd :char #\A)
        (is-input-state app :mode :insert :cursor-pos 3))))

  (it "vi-x-deletes-character-under-cursor"
    (with-vi-command-state (cmd (input-state :buffer "abc" :cursor-pos 0))
      (with-reduced-input-state (del) (reduce-once cmd :char #\x)
        (is-input-state del :buffer "bc" :mode :vi-command))))

  (it "vi-counted-motion-and-delete"
    (with-vi-command-state (cmd (input-state :buffer "abcdef" :cursor-pos 1))
      ;; ESC moved cursor 1 -> 0; 3l advances three columns and 2h retreats two.
      (with-reduced-input-states cmd (((right) :char #\3)
                                      ((right) :char #\l)
                                      ((left) :char #\2)
                                      ((left) :char #\h))
        (is-vi-command-state right :cursor-pos 3)
        (is-vi-command-state left :cursor-pos 1))
      (with-reduced-input-states cmd (((counted) :char #\3)
                                      ((deleted) :char #\x))
        (is-input-state deleted
                        :buffer "def"
                        :cursor-pos 0
                        :mode :vi-command))))

  (it "vi-counted-word-motion-and-operator"
    (with-vi-command-state (cmd (input-state :buffer "one two three four"
                                              :cursor-pos 1))
      (with-reduced-input-states cmd (((counted) :char #\2)
                                      ((moved) :char #\w))
        (is-vi-command-state moved :cursor-pos 8))
      (with-reduced-input-states cmd (((counted) :char #\2)
                                      ((pending) :char #\d)
                                      ((deleted) :char #\w))
        (is-input-state deleted
                        :buffer " three four"
                        :cursor-pos 0
                        :mode :vi-command))))

  (it "vi-dd-clears-line-and-cc-enters-insert"
    (with-vi-command-state (cmd (input-state :buffer "hello world" :cursor-pos 3))
      ;; dd : two keystrokes delete the whole line.
      (with-reduced-input-state (pend) (reduce-once cmd :char #\d)
        (is-input-state pend :mode :vi-d)
        (with-reduced-input-state (cleared) (reduce-once pend :char #\d)
          (is-vi-command-state cleared :buffer "")))
      ;; cc : clear line and drop into insert mode.
      (with-reduced-input-state (cpend) (reduce-once cmd :char #\c)
        (with-reduced-input-state (changed) (reduce-once cpend :char #\c)
          (is-input-state changed :buffer "" :mode :insert)))))

  (it "vi-operator-edit-projects-motion-plan"
    (let* ((state (nshell.presentation::copy-input-state-with
                   (input-state :buffer "one two three" :cursor-pos 4)
                   :mode :vi-d))
           (edit (nshell.presentation::vi-operator-edit-for-motion
                  state #\w :d)))
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-vi-operator-edit)
          :absent (nshell.presentation::make-vi-operator-edit))
      (expect (nshell.presentation::vi-operator-edit-p edit) :to-be-truthy)
      (expect 4 :to-equal (nshell.presentation::vi-operator-edit-start edit))
      (expect 7 :to-equal (nshell.presentation::vi-operator-edit-end edit))
      (expect 4 :to-equal (nshell.presentation::vi-operator-edit-cursor edit))
      (expect :vi-command :to-be (nshell.presentation::vi-operator-edit-end-mode edit))))

  (it "vi-operator-edit-commit-applies-change-end-mode"
    (let* ((state (input-state :buffer "one two" :cursor-pos 4))
           (edit (nshell.presentation::vi-operator-edit-for-motion
                  state #\$ :c)))
      (multiple-value-bind (changed output)
          (nshell.presentation::commit-vi-operator-edit state edit)
        (expect :redraw :to-be output)
        (is-input-state changed
                        :buffer "one "
                        :cursor-pos 4
                        :mode :insert
                        :kill-ring '("two")))))

  (it "vi-D-kills-to-end-of-line"
    (let* ((base (input-state :buffer "hello world" :cursor-pos 6))
           ;; ESC moves cursor 6 -> 5 (the space); place it on 'w' via l.
           (on-w nil))
      (with-vi-command-state (cmd base)
        (setf on-w (reduce-once-state cmd :char #\l))
        (with-reduced-input-state (killed) (reduce-once on-w :char #\D)
          (is-vi-command-state killed :buffer "hello ")))))

  (it "vi-j-k-emit-history-navigation"
    (with-vi-command-state (cmd (input-state :buffer "x" :cursor-pos 0))
      (multiple-value-bind (s out) (reduce-once cmd :char #\k)
        (declare (ignore s))
        (expect :history-prev :to-be out))
      (multiple-value-bind (s out) (reduce-once cmd :char #\j)
        (declare (ignore s))
        (expect :history-next :to-be out))))

  (it "vi-v-enters-visual-mode-with-anchor"
    (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
      (is-vi-visual-state visual
                          :cursor-pos 0
                          :vi-visual-anchor 0)))

  (it "vi-visual-motion-and-escape-clears-anchor"
    (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
      (with-reduced-input-states visual (((counted) :char #\2)
                                         ((moved) :char #\l)
                                         ((escaped) :escape))
        (is-vi-visual-state moved
                            :cursor-pos 2
                            :vi-visual-anchor 0)
        (is-vi-command-state escaped
                             :cursor-pos 2
                             :vi-visual-anchor nil))))

  (it "vi-visual-delete-is-inclusive-and-populates-kill-ring"
    (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
      (with-reduced-input-states visual (((counted) :char #\2)
                                         ((moved) :char #\l)
                                         ((deleted) :char #\d))
        (is-input-state deleted
                        :buffer "def"
                        :cursor-pos 0
                        :mode :vi-command
                        :vi-visual-anchor nil
                        :kill-ring '("abc")))))

  (it "vi-visual-change-enters-insert-mode"
    (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
      (with-reduced-input-states visual (((moved) :char #\l)
                                         ((changed) :char #\c))
        (is-input-state changed
                        :buffer "cdef"
                        :cursor-pos 0
                        :mode :insert
                        :vi-visual-anchor nil
                        :kill-ring '("ab")))))

  (it "vi-visual-yank-preserves-buffer-and-exits"
    (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
      (with-reduced-input-states visual (((counted) :char #\2)
                                         ((moved) :char #\l)
                                         ((yanked copy-output) :char #\y))
        (expect :copy :to-be copy-output)
        (is-input-state yanked
                        :buffer "abcdef"
                        :cursor-pos 0
                        :mode :vi-command
                        :vi-visual-anchor nil
                        :kill-ring '("abc")))))

  (it "vi-visual-o-swaps-anchor-and-cursor"
    (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
      (with-reduced-input-states visual (((counted) :char #\2)
                                         ((moved) :char #\l)
                                         ((swapped) :char #\o))
        (is-vi-visual-state swapped
                            :cursor-pos 0
                            :vi-visual-anchor 2))))

  (it "vi-a-I-C-s-enter-insert-or-change"
    "a appends after cursor, I inserts at line start, C changes to end, s substitutes."
    ;; ESC on cursor-pos 2 moves it to 1 (pos=1 throughout this test).
    (with-vi-command-state (cmd (input-state :buffer "abcdef" :cursor-pos 2))
      ;; a: insert at pos+1 = 2 (one past the char under cursor).
      (with-reduced-input-state (app) (reduce-once cmd :char #\a)
        (is-input-state app :mode :insert :cursor-pos 2))
      ;; I: insert at line start (always column 0).
      (with-reduced-input-state (ins) (reduce-once cmd :char #\I)
        (is-input-state ins :mode :insert :cursor-pos 0))
      ;; C: kill from pos=1 to end, leaving "a", cursor stays at 1.
      (with-reduced-input-state (changed) (reduce-once cmd :char #\C)
        (is-input-state changed :buffer "a" :mode :insert :cursor-pos 1))
      ;; s: kill one char at pos=1 ("b"), leaving "acdef", cursor at 1.
      (with-reduced-input-state (sub) (reduce-once cmd :char #\s)
        (is-input-state sub :buffer "acdef" :mode :insert :cursor-pos 1))))

  (it "vi-e-and-caret-motions"
    "e moves to word-end position; ^ moves unconditionally to column 0."
    (with-vi-command-state (cmd (input-state :buffer "one two three" :cursor-pos 0))
      ;; e: advance to last char of first word (index 2).
      (with-reduced-input-state (end1) (reduce-once cmd :char #\e)
        (is-vi-command-state end1 :cursor-pos 2))
      ;; ^ is always line-start (contrast with 0, which accumulates count when active).
      (with-vi-command-state (mid (input-state :buffer "hello" :cursor-pos 4))
        (with-reduced-input-state (start) (reduce-once mid :char #\^)
          (is-vi-command-state start :cursor-pos 0)))))

  (it "vi-visual-insert-exits-visual-before-entering-insert"
    "i and a in visual mode cancel the selection and enter insert mode."
    (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
      ;; Move right to select "ab" then press i to cancel visual and insert.
      (with-reduced-input-states visual (((moved) :char #\l)
                                         ((inserted) :char #\i))
        (is-input-state inserted :mode :insert :vi-visual-anchor nil))
      ;; a in visual: same cancel, cursor advances by 1.
      (with-reduced-input-states visual (((moved) :char #\l)
                                         ((appended) :char #\a))
        (is-input-state appended :mode :insert :vi-visual-anchor nil))))

  (it "vi-counted-position-applies-step-n-times"
    "vi-counted-position applies the step function COUNT times to the initial position."
    (flet ((cnt (pos count step)
             (nshell.presentation::%vi-counted-position pos count step)))
      (expect 5 :to-equal (cnt 0 5 #'1+))
      (expect 0 :to-equal (cnt 5 5 #'1-))
      (expect 3 :to-equal (cnt 3 0 #'1+))
      (expect 7 :to-equal (cnt 3 2 (lambda (p) (+ p 2))))))

  (it "vi-accumulate-count-builds-multi-digit-repeat-count"
    "vi-accumulate-count prefixes existing count with new digit (like typing 12 = 1 then 2)."
    (flet ((accum (state digit)
             (nshell.presentation::input-state-vi-count
              (nshell.presentation::%vi-accumulate-count state digit))))
      (let ((base (input-state :buffer "")))
        (expect 3 :to-equal (accum base #\3))
        (expect 31 :to-equal (accum (nshell.presentation::%vi-accumulate-count base #\3) #\1))
        (expect 312 :to-equal (accum (nshell.presentation::%vi-accumulate-count
                           (nshell.presentation::%vi-accumulate-count base #\3)
                          #\1)
                         #\2)))))

  (it "vi-input-transition-clears-count-before-commit"
    "Vi reducer output should pass through a typed transition boundary before multiple values."
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 3
                               :mode :vi-command
                               :vi-count 12))
           (transition (nshell.presentation::vi-input-transition-clearing-count
                        state :history-prev)))
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-vi-input-transition)
          :absent (nshell.presentation::make-vi-input-transition))
      (expect (nshell.presentation::vi-input-transition-p transition) :to-be-truthy)
      (expect :history-prev :to-be (nshell.presentation::vi-input-transition-output transition))
      (expect (nshell.presentation::input-state-vi-count
                 (nshell.presentation::vi-input-transition-state transition)) :to-be-null)
      (multiple-value-bind (committed output)
          (nshell.presentation::commit-vi-input-transition transition)
        (expect :history-prev :to-be output)
        (is-vi-command-state committed
                             :buffer "abcdef"
                             :cursor-pos 3)
        (expect (nshell.presentation::input-state-vi-count committed) :to-be-null))))

  (it "vi-visual-selection-projects-inclusive-anchor-range"
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 1
                               :mode :vi-visual
                               :vi-visual-anchor 4))
           (selection (nshell.presentation::vi-visual-selection-for-state state)))
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-vi-visual-selection)
          :absent (nshell.presentation::make-vi-visual-selection))
      (expect (nshell.presentation::vi-visual-selection-p selection) :to-be-truthy)
      (expect 1 :to-equal (nshell.presentation::vi-visual-selection-start selection))
      (expect 5 :to-equal (nshell.presentation::vi-visual-selection-end selection))
      (expect 1 :to-equal (nshell.presentation::vi-visual-selection-cursor selection))))

  (it "vi-visual-selection-kill-commit-uses-selection-cursor"
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 4
                               :mode :vi-visual
                               :vi-visual-anchor 1
                               :kill-ring '("old")
                               :completion-index 1
                               :completion-base-buffer "abcdef"
                               :completion-base-cursor 4
                               :last-candidates '("alpha")
                               :suggestion "tail"))
           (selection (nshell.presentation::vi-visual-selection-for-state state)))
      (multiple-value-bind (committed output)
          (nshell.presentation::commit-vi-visual-kill-selection
           state selection :vi-command)
        (expect :redraw :to-be output)
        (is-vi-command-state committed
                             :buffer "af"
                             :cursor-pos 1
                             :kill-ring '("bcde" "old"))
        (is-completion-session-cleared committed))))

  (it "vi-visual-yank-edit-projects-selection-through-commit"
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 2
                               :mode :vi-visual
                               :vi-visual-anchor 0
                               :kill-ring '("old")
                               :completion-index 1
                               :completion-base-buffer "abc"
                               :completion-base-cursor 1
                               :last-candidates '("alpha")
                               :suggestion "ab"))
           (edit (nshell.presentation::vi-visual-yank-edit-for-range state 0 3 0)))
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-vi-visual-yank-edit)
          :absent (nshell.presentation::make-vi-visual-yank-edit))
      (expect (nshell.presentation::vi-visual-yank-edit-p edit) :to-be-truthy)
      (expect 0 :to-equal (nshell.presentation::vi-visual-yank-edit-cursor edit))
      (expect "abc" :to-equal (nshell.presentation::vi-visual-yank-edit-selected edit))
      (multiple-value-bind (committed output)
          (nshell.presentation::commit-vi-visual-yank-edit state edit)
        (expect :redraw :to-be output)
        (is-vi-command-state committed
                             :buffer "abcdef"
                             :cursor-pos 0
                             :kill-ring '("abc" "old"))
        (is-completion-session-cleared committed))))

  (it "vi-visual-yank-edit-empty-selection-preserves-kill-ring"
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 3
                               :mode :vi-visual
                               :vi-visual-anchor 3
                               :kill-ring '("old")))
           (edit (nshell.presentation::vi-visual-yank-edit-for-range state 3 3 3)))
      (expect "" :to-equal (nshell.presentation::vi-visual-yank-edit-selected edit))
      (multiple-value-bind (committed output)
          (nshell.presentation::commit-vi-visual-yank-edit state edit)
        (expect :redraw :to-be output)
        (is-vi-command-state committed
                             :buffer "abcdef"
                             :cursor-pos 3
                             :kill-ring '("old")))))

  (it "vi-visual-anchor-swap-edit-projects-cursor-and-anchor-through-commit"
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 4
                               :mode :vi-visual
                               :vi-count 2
                               :vi-visual-anchor 1))
           (edit (nshell.presentation::vi-visual-anchor-swap-edit-for-state state)))
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-vi-visual-anchor-swap-edit)
          :absent (nshell.presentation::make-vi-visual-anchor-swap-edit))
      (expect (nshell.presentation::vi-visual-anchor-swap-edit-p edit) :to-be-truthy)
      (expect 4 :to-equal (nshell.presentation::vi-visual-anchor-swap-edit-cursor edit))
      (expect 1 :to-equal (nshell.presentation::vi-visual-anchor-swap-edit-anchor edit))
      (multiple-value-bind (committed output)
          (nshell.presentation::commit-vi-visual-anchor-swap-edit state edit)
        (expect :redraw :to-be output)
        (is-vi-visual-state committed
                            :buffer "abcdef"
                            :cursor-pos 1
                            :vi-visual-anchor 4)
        (expect (nshell.presentation::input-state-vi-count committed) :to-be-null))))

  (it "vi-visual-anchor-swap-edit-uses-cursor-when-anchor-is-missing"
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 3
                               :mode :vi-visual
                               :vi-visual-anchor nil))
           (edit (nshell.presentation::vi-visual-anchor-swap-edit-for-state state)))
      (expect 3 :to-equal (nshell.presentation::vi-visual-anchor-swap-edit-cursor edit))
      (expect 3 :to-equal (nshell.presentation::vi-visual-anchor-swap-edit-anchor edit))
      (multiple-value-bind (committed output)
          (nshell.presentation::commit-vi-visual-anchor-swap-edit state edit)
        (expect :redraw :to-be output)
        (is-vi-visual-state committed
                            :buffer "abcdef"
                            :cursor-pos 3
                            :vi-visual-anchor 3)))))

  (it "vi-operator-motions-cover-word-back-line-start-and-unknown"
    (let* ((state (input-state :buffer "one two three"
                               :cursor-pos 8
                               :mode :vi-command))
           (backward (nshell.presentation::vi-operator-edit-for-motion
                      state #\b :d))
           (line-start (nshell.presentation::vi-operator-edit-for-motion
                        state #\0 :d))
           (dollar (nshell.presentation::vi-operator-edit-for-motion
                    (nshell.presentation::copy-input-state-with state :cursor-pos 0)
                    #\$ :d)))
      (expect 4 :to-equal
              (nshell.presentation::vi-operator-edit-start backward))
      (expect 8 :to-equal
              (nshell.presentation::vi-operator-edit-end backward))
      (expect 0 :to-equal
              (nshell.presentation::vi-operator-edit-start line-start))
      (expect 8 :to-equal
              (nshell.presentation::vi-operator-edit-end line-start))
      (expect 0 :to-equal
              (nshell.presentation::vi-operator-edit-cursor dollar))
      (expect (nshell.presentation::vi-operator-edit-for-motion
               state #\? :d)
              :to-be-null)))

  (it "vi-reducer-covers-visual-exit-eol-edit-and-unknown-events"
    (let ((command-state (input-state :buffer "abc"
                                      :cursor-pos 0
                                      :mode :vi-command))
          (visual-state (input-state :buffer "abc"
                                     :cursor-pos 1
                                     :mode :vi-visual
                                     :vi-visual-anchor 0)))
      (multiple-value-bind (state output)
          (reduce-once command-state :char #\x)
        (is-vi-command-state state :buffer "bc" :cursor-pos 0)
        (expect :redraw :to-be output))
      (multiple-value-bind (state output)
          (reduce-once command-state :char #\?)
        (is-vi-command-state state :buffer "abc" :cursor-pos 0)
        (expect :none :to-be output))
      (let ((eol-state (nshell.presentation::copy-input-state-with
                        command-state :cursor-pos 3)))
        (multiple-value-bind (state output)
            (reduce-once eol-state :char #\x)
          (is-vi-command-state state :buffer "abc" :cursor-pos 3)
          (expect :none :to-be output)))
      (multiple-value-bind (state output)
          (reduce-once visual-state :char #\v)
        (is-vi-command-state state :buffer "abc" :cursor-pos 1)
        (expect :redraw :to-be output))
      (multiple-value-bind (state output)
          (reduce-once visual-state :char #\?)
        (is-vi-visual-state state :buffer "abc" :cursor-pos 1
                            :vi-visual-anchor 0)
        (expect :none :to-be output))
      (multiple-value-bind (state output)
          (nshell.presentation::reduce-vi-input-state
           command-state (input-key-event :char nil))
        (is-vi-command-state state :buffer "abc" :cursor-pos 0)
        (expect :none :to-be output))
      (multiple-value-bind (state output)
          (nshell.presentation::reduce-vi-input-state
           command-state (input-key-event :unknown))
        (is-vi-command-state state :buffer "abc" :cursor-pos 0)
        (expect :none :to-be output))))

  (it "vi-operator-unknown-motion-cancels-to-command-mode"
    (let ((state (input-state :buffer "abc"
                              :cursor-pos 1
                              :mode :vi-d)))
      (multiple-value-bind (new-state output)
          (nshell.presentation::reduce-vi-input-state
           state (input-key-event :char #\?))
        (expect :vi-command :to-be
                (nshell.presentation:input-state-mode new-state))
        (expect :redraw :to-be output))))
