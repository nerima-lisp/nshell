(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-alt-s-toggles-sudo-prefix"
    (let ((state (completion-session-state
                  :buffer "apt update"
                  :cursor-pos 3
                  :completion-index 2
                  :suggestion " && apt upgrade")))
      (with-expected-input-state-reduction (prefixed prefixed-output)
          state
          (reduce-once state :alt-s)
          :suggest-update
          (:buffer "sudo apt update"
           :cursor-pos 8
           :completion-index -1
           :suggestion nil)
        (with-expected-input-state-reduction (unprefixed unprefixed-output)
            prefixed
            (reduce-once prefixed :alt-s)
            :suggest-update
            (:buffer "apt update" :cursor-pos 3)))))

  (it "input-state-alt-s-removes-bare-sudo-prefix"
    (let ((state (input-state
                  :buffer "sudo"
                  :cursor-pos 4)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :alt-s)
          :suggest-update
          (:buffer "" :cursor-pos 0))))

  (it "input-state-alt-s-projects-prefix-cases-through-reducer"
    (dolist (scenario '(("apt update" 3 "sudo apt update" 8)
                        ("sudo apt update" 3 "apt update" 0)
                        ("sudo" 4 "" 0)))
      (destructuring-bind (buffer cursor-pos expected-buffer expected-cursor-pos)
          scenario
        (let ((state (input-state :buffer buffer :cursor-pos cursor-pos)))
          (with-expected-input-state-reduction (new-state output)
              state
              (reduce-once state :alt-s)
              :suggest-update
              (:buffer expected-buffer
               :cursor-pos expected-cursor-pos))))))

  (it "input-state-public-dispatch-inserts-char-and-paste"
    (let ((state (input-state :buffer "ab" :cursor-pos 1)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :char #\x)
          :suggest-update
          (:buffer "axb" :cursor-pos 2)))
    (let ((state (input-state :buffer "ab" :cursor-pos 1)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :paste nil nil (list :text "XY"))
          :suggest-update
          (:buffer "aXYb" :cursor-pos 3))))

  (it "input-state-public-dispatch-moves-to-eol"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 1
                  :completion-index 1
                  :suggestion " status")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-e)
          :redraw
          (:buffer "git"
           :cursor-pos 3
           :completion-index 1
           :suggestion " status"))))

  (it "input-state-ctrl-l-emits-clear-screen-without-state-change"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 2
                  :completion-index 1
                  :suggestion " status")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-l)
          :clear-screen
          (:buffer "git"
           :cursor-pos 2
           :completion-index 1
           :suggestion " status"))))

  (it "input-state-unknown-key-event-noops-through-reducer"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 2
                  :completion-index 1
                  :suggestion " status")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :unknown)
          :none
          (:buffer "git"
           :cursor-pos 2
           :completion-index 1
           :suggestion " status"))))

  (it "input-state-ctrl-p-and-ctrl-n-request-history-navigation"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 2
                  :completion-index 1
                  :suggestion " status")))
      (with-expected-input-state-reduction (prev-state prev-output)
          state
          (reduce-once state :ctrl-p)
          :history-prev
          (:buffer "git"
           :cursor-pos 2
           :completion-index 1
           :suggestion " status"))
      (with-expected-input-state-reduction (next-state next-output)
          state
          (reduce-once state :ctrl-n)
          :history-next
          (:buffer "git" :cursor-pos 2))))

  (it "input-state-sgr-mouse-wheel-up-requests-history-prev"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 2
                  :completion-index 1
                  :suggestion " status")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :mouse nil 64
                       '(:protocol :sgr
                         :button 0
                         :button-code 64
                         :column 10
                         :row 5
                         :event :wheel-up
                         :modifiers nil))
          :history-prev
          (:buffer "git"
           :cursor-pos 2
           :completion-index 1
           :suggestion " status"))))

  (it "input-state-sgr-mouse-wheel-down-requests-history-next"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 2
                  :completion-index 1
                  :suggestion " status")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :mouse nil 65
                       '(:protocol :sgr
                         :button 1
                         :button-code 65
                         :column 10
                         :row 5
                         :event :wheel-down
                         :modifiers nil))
          :history-next
          (:buffer "git"
           :cursor-pos 2
           :completion-index 1
           :suggestion " status"))))

  (it "input-state-sgr-mouse-click-and-drag-redraw-without-editing"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 2
                  :completion-index 1
                  :suggestion " status")))
      (dolist (mouse-data
               '((:protocol :sgr
                  :button 0
                  :button-code 0
                  :column 10
                  :row 5
                  :event :press
                  :modifiers nil)
                 (:protocol :sgr
                  :button 0
                  :button-code 32
                  :column 10
                  :row 5
                  :event :drag
                  :modifiers nil)))
        (with-expected-input-state-reduction (new-state output)
            state
            (reduce-once state :mouse nil (getf mouse-data :button-code)
                         mouse-data)
            :redraw
            (:buffer "git"
             :cursor-pos 2
             :completion-index 1
             :suggestion " status")))))

  (it "input-state-sgr-mouse-selection-copies-forward-range"
    "A left-button press, drag, and release should copy the selected buffer range."
    (let ((state (input-state :buffer "abcdef" :cursor-pos 0)))
      (multiple-value-bind (pressed press-output)
          (reduce-once state :mouse nil 0
                       '(:protocol :sgr
                         :button 0
                         :button-code 0
                         :column 2
                         :row 1
                         :event :press
                         :buffer-index 1
                         :modifiers nil))
        (expect :redraw :to-be press-output)
        (expect 1 :to-equal
                (nshell.presentation::input-state-mouse-selection-anchor
                 pressed))
        (multiple-value-bind (dragged drag-output)
            (reduce-once pressed :mouse nil 32
                         '(:protocol :sgr
                           :button 0
                           :button-code 32
                           :column 5
                           :row 1
                           :event :drag
                           :buffer-index 4
                           :modifiers nil))
          (expect :redraw :to-be drag-output)
          (expect 4 :to-equal
                  (nshell.presentation::input-state-mouse-selection-end
                   dragged))
          (multiple-value-bind (released release-output)
              (reduce-once dragged :mouse nil 0
                           '(:protocol :sgr
                             :button 0
                             :button-code 0
                             :column 5
                             :row 1
                             :event :release
                             :buffer-index 4
                             :modifiers nil))
            (expect :copy :to-be release-output)
            (expect '("bcd") :to-equal
                    (nshell.presentation:input-state-kill-ring released))
            (expect (nshell.presentation::input-state-mouse-selection-anchor
                     released)
                    :to-be-null)
            (expect (nshell.presentation::input-state-mouse-selection-end
                     released)
                    :to-be-null)))))))

  (it "input-state-sgr-mouse-selection-supports-reverse-and-shift"
    "Reverse drags should normalize their range and Shift should extend an anchor."
    (let ((state (input-state :buffer "abcdef" :cursor-pos 0)))
      (multiple-value-bind (pressed ignored)
          (reduce-once state :mouse nil 0
                       '(:protocol :sgr
                         :button-code 0
                         :event :press
                         :buffer-index 4
                         :modifiers nil))
        (declare (ignore ignored))
        (multiple-value-bind (dragged ignored)
            (reduce-once pressed :mouse nil 32
                         '(:protocol :sgr
                           :button-code 32
                           :event :drag
                           :buffer-index 1
                           :modifiers nil))
          (declare (ignore ignored))
          (multiple-value-bind (released output)
              (reduce-once dragged :mouse nil 0
                           '(:protocol :sgr
                             :button-code 0
                             :event :release
                             :buffer-index 1
                             :modifiers nil))
            (expect :copy :to-be output)
            (expect '("bcd") :to-equal
                    (nshell.presentation:input-state-kill-ring released)))))
    (let ((state (input-state :buffer "abcdef"
                              :cursor-pos 0
                              :mouse-selection-anchor 1
                              :mouse-selection-end 2)))
      (multiple-value-bind (extended output)
          (reduce-once state :mouse nil 0
                       '(:protocol :sgr
                         :button-code 0
                         :event :press
                         :buffer-index 4
                         :modifiers (:shift)))
        (expect :redraw :to-be output)
        (expect 1 :to-equal
                (nshell.presentation::input-state-mouse-selection-anchor
                 extended))
        (expect 4 :to-equal
                (nshell.presentation::input-state-mouse-selection-end
                 extended)))))

  (it "input-state-edit-clears-mouse-selection"
    "Ordinary editing should clear a transient mouse selection before insertion."
    (let ((state (input-state :buffer "abc"
                              :cursor-pos 1
                              :mouse-selection-anchor 0
                              :mouse-selection-end 2)))
      (multiple-value-bind (edited output)
          (reduce-once state :char #\x)
        (expect :suggest-update :to-be output)
        (expect "axbc" :to-equal
                (nshell.presentation:input-state-buffer edited))
        (expect (nshell.presentation::input-state-mouse-selection-anchor edited)
                :to-be-null)
        (expect (nshell.presentation::input-state-mouse-selection-end edited)
                :to-be-null))))

  (it "input-state-alt-dot-requests-last-history-argument"
    (let ((state (completion-session-state
                  :buffer "echo "
                  :cursor-pos 5
                  :completion-index 1
                  :suggestion "tail")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :alt-dot)
          :insert-last-argument
          (:buffer "echo "
           :cursor-pos 5
           :completion-index 1
           :suggestion "tail"))))

  (it "input-state-alt-e-requests-external-command-edit"
    (let ((state (input-state :buffer "echo before" :cursor-pos 11)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :alt-e)
          :edit-command
          (:buffer "echo before"
           :cursor-pos 11))))

  (it "input-state-enter-on-text-returns-execute"
    (let ((state (input-state :buffer "echo hi" :cursor-pos 7)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :enter)
          :execute
          (:buffer "echo hi"))))

  (it "input-state-enter-accepts-suggestion-at-eol-before-execute"
    (let ((state (completion-session-state
                  :buffer "echo"
                  :cursor-pos 4
                  :completion-index 1
                  :suggestion " hello")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :enter)
          :execute
          (:buffer "echo hello"
           :cursor-pos 10
           :completion-index -1
           :suggestion nil))))

  (it "input-state-enter-expands-abbreviation-before-execute"
    (let ((state (completion-session-state
                  :buffer "gco"
                  :cursor-pos 3
                  :completion-index 2
                  :suggestion " ignored"
                  :abbreviation-expander
                  (lambda (token)
                    (when (string= token "gco")
                      "git checkout")))))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :enter)
          :execute
          (:buffer "git checkout ignored"
           :cursor-pos 20
           :completion-index -1
           :suggestion nil))))

  (it "input-state-inserts-continuation-newline-at-cursor"
    (let ((state (input-state :buffer "echo \"hi\"" :cursor-pos 5)))
      (with-expected-input-state-reduction (new-state output)
          state
          (nshell.presentation:insert-newline-at-cursor state)
          :suggest-update
          (:buffer (format nil "echo ~%\"hi\"")
           :cursor-pos 6))))

  (it "input-state-inserts-indented-continuation-newline-at-cursor"
    (let ((state (input-state :buffer "echo |" :cursor-pos 6)))
      (with-expected-input-state-reduction (new-state output)
          state
          (nshell.presentation:insert-newline-at-cursor state :indent 2)
          :suggest-update
          (:buffer (format nil "echo |~%  ")
           :cursor-pos 9))))

  (it "input-state-ctrl-d-empty-quits-but-non-empty-deletes"
    (multiple-value-bind (empty-state empty-output)
        (reduce-once (input-state) :ctrl-d)
      (declare (ignore empty-state))
      (expect :quit :to-be empty-output))
    (let ((state (input-state :buffer "ab" :cursor-pos 1)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-d)
          :suggest-update
          (:buffer "a" :cursor-pos 1))))

  (it "input-state-backspace-removes-character-before-cursor"
    (let ((state (input-state :buffer "abc" :cursor-pos 2)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :backspace)
          :suggest-update
          (:buffer "ac" :cursor-pos 1))))

  (it "input-state-ctrl-t-transposes-chars-around-cursor"
    (let ((state (completion-session-state
                  :buffer "abcd"
                  :cursor-pos 2
                  :completion-index 3
                  :suggestion " ignored")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-t)
          :suggest-update
          (:buffer "acbd"
           :cursor-pos 3
           :completion-index -1
           :suggestion nil))))

  (it "input-state-ctrl-t-at-eol-transposes-last-two-chars"
    (let ((state (input-state
                  :buffer "abcd"
                  :cursor-pos 4)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-t)
          :suggest-update
          (:buffer "abdc" :cursor-pos 4))))

  (it "input-state-ctrl-t-noops-without-left-char"
    (with-expected-noop-input-state-reductions (new-state output)
        :ctrl-t
        (list (input-state :buffer "" :cursor-pos 0)
              (input-state :buffer "a" :cursor-pos 1)
              (input-state :buffer "ab" :cursor-pos 0))))

  (it "input-state-char-transposition-projects-buffer-and-cursor"
    (let ((transposition (nshell.presentation::char-transposition-at-cursor
                          "abcd" 2)))
      (expect (nshell.presentation::%char-transposition-p transposition) :to-be-truthy)
      (expect (nshell.presentation::%char-transposition-plan-p
           (nshell.presentation::char-transposition-plan transposition)) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::char-transposition-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::char-transposition-plan-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-char-transposition) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-char-transposition-plan) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::char-transposition-left) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::char-transposition-right) :to-be-falsy)
      (expect "acbd" :to-equal (nshell.presentation::char-transposition-buffer
                    transposition
                    "abcd"))
      (expect 3 :to-equal (nshell.presentation::char-transposition-cursor-pos
                transposition)))
    (let ((transposition (nshell.presentation::char-transposition-at-cursor
                          "abcd" 4)))
      (expect "abdc" :to-equal (nshell.presentation::char-transposition-buffer
                    transposition
                    "abcd"))
      (expect 4 :to-equal (nshell.presentation::char-transposition-cursor-pos
                transposition)))
    (expect (nshell.presentation::char-transposition-at-cursor "a" 1) :to-be-null)
    (expect (nshell.presentation::char-transposition-at-cursor "ab" 0) :to-be-null))

  (it "input-state-word-transform-edit-projects-token-replacement"
    (let* ((edit (nshell.presentation::word-transform-edit-at-cursor
                  "echo hello tail"
                  5
                  #'string-upcase))
           (plan (nshell.presentation::word-transform-edit-plan edit)))
      (expect (nshell.presentation::%word-transform-edit-p edit) :to-be-truthy)
      (expect (nshell.presentation::%word-transform-plan-p plan) :to-be-truthy)
      (expect plan :to-be (nshell.presentation::word-transform-edit-plan edit))
      (expect (fboundp 'nshell.presentation::%make-word-transform-edit) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%make-word-transform-plan) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::word-transform-edit-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transform-plan-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-word-transform-edit) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-word-transform-plan) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transform-edit-start) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transform-edit-end) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transform-edit-replacement) :to-be-falsy)
      (expect 5 :to-equal (nshell.presentation::word-transform-plan-start plan))
      (expect 10 :to-equal (nshell.presentation::word-transform-plan-end plan))
      (expect "HELLO" :to-equal (nshell.presentation::word-transform-plan-replacement plan))
      (expect "echo HELLO tail" :to-equal (nshell.presentation::word-transform-edit-buffer
                    edit
                    "echo hello tail"))
      (expect 10 :to-equal (nshell.presentation::word-transform-edit-cursor-pos edit)))
    (let ((edit (nshell.presentation::word-transform-edit-at-cursor
                 "echo hello"
                 0
                 (lambda (word)
                   (concatenate 'string word "-suffix")))))
      (expect "echo-suffix hello" :to-equal (nshell.presentation::word-transform-edit-buffer
                    edit
                    "echo hello"))
      (expect 11 :to-equal (nshell.presentation::word-transform-edit-cursor-pos edit)))
    (expect (nshell.presentation::word-transform-edit-at-cursor
               "   "
               0
               #'string-upcase) :to-be-null))

  (it "input-state-word-transposition-projects-token-swap"
    (let* ((transposition (nshell.presentation::word-transposition-at-cursor
                           "echo one two" 9))
           (plan (nshell.presentation::word-transposition-plan transposition)))
      (expect (nshell.presentation::%word-transposition-p transposition) :to-be-truthy)
      (expect (nshell.presentation::%word-transposition-plan-p plan) :to-be-truthy)
      (expect plan :to-be (nshell.presentation::word-transposition-plan transposition))
      (expect (fboundp 'nshell.presentation::%make-word-transposition) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%make-word-transposition-plan) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::word-transposition-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transposition-plan-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-word-transposition) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-word-transposition-plan) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transposition-left-start) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transposition-left-end) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transposition-middle-start) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transposition-middle-end) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transposition-right-start) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::word-transposition-right-end) :to-be-falsy)
      (expect 5 :to-equal (nshell.presentation::word-transposition-plan-left-start plan))
      (expect 8 :to-equal (nshell.presentation::word-transposition-plan-left-end plan))
      (expect 8 :to-equal (nshell.presentation::word-transposition-plan-middle-start plan))
      (expect 9 :to-equal (nshell.presentation::word-transposition-plan-middle-end plan))
      (expect 9 :to-equal (nshell.presentation::word-transposition-plan-right-start plan))
      (expect 12 :to-equal (nshell.presentation::word-transposition-plan-right-end plan))
      (expect "echo two one" :to-equal (nshell.presentation::word-transposition-buffer
                    transposition
                    "echo one two"))
      (expect 12 :to-equal (nshell.presentation::word-transposition-cursor-pos
                 transposition)))
    (expect (nshell.presentation::word-transposition-at-cursor "one" 3) :to-be-null))

  (it "input-state-alt-t-transposes-last-two-words-at-eol"
    (let ((state (completion-session-state
                  :buffer "echo one two"
                  :cursor-pos 12
                  :completion-index 3
                  :suggestion " ignored")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :alt-t)
          :suggest-update
          (:buffer "echo two one"
           :cursor-pos 12
           :completion-index -1
           :suggestion nil))))

  ;; Every case here transposes the two words around $cursor-pos via :alt-t and
  ;; checks the resulting buffer/cursor; only what counts as a "word" boundary
  ;; and where the cursor lands differ per case.
  (it-each (("word at cursor with previous word"
             "echo one two" 9
             "echo two one" 12)
            ("an escaped space as token content"
             "echo my\\ file.txt tail" 22
             "echo tail my\\ file.txt" 22)
            ("a quoted space as token content"
             "echo \"hello world\" tail" 23
             "echo tail \"hello world\"" 23)
            ("shell operators as word boundaries"
             "echo one|two" 12
             "echo two|one" 12))
      "input-state-alt-t transposes ~A"
      (description buffer cursor expected-buffer expected-cursor)
    (declare (ignore description))
    (let ((state (input-state :buffer buffer :cursor-pos cursor)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :alt-t)
          :suggest-update
          (:buffer expected-buffer :cursor-pos expected-cursor))))

  (it "input-state-alt-t-noops-without-two-words"
    (with-expected-noop-input-state-reductions (new-state output)
        :alt-t
        (list (input-state :buffer "" :cursor-pos 0)
              (input-state :buffer "one" :cursor-pos 3)
              (input-state :buffer "one " :cursor-pos 4)))))
