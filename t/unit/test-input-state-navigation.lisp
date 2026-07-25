(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-cursor-moves-with-arrow-keys-within-bounds"
    (let ((state (input-state :buffer "abc" :cursor-pos 1)))
      (with-expected-input-state-reduction (left-state left-output)
          state
          (reduce-once state :left)
          :redraw
          (:cursor-pos 0)
        (with-reduced-input-state (bounded-left-state) (reduce-once left-state :left)
          (is-input-state bounded-left-state :cursor-pos 0)))
      (with-expected-input-state-reduction (right-state right-output)
          state
          (reduce-once state :right)
          :redraw
          (:cursor-pos 2)
        (with-reduced-input-state (end-state) (reduce-once right-state :end)
          (is-input-state end-state :cursor-pos 3)
          (with-reduced-input-state (bounded-right-state) (reduce-once end-state :right)
            (is-input-state bounded-right-state :cursor-pos 3))))))

  (it "input-state-page-navigation-requests-history-traversal"
    (let ((state (input-state :buffer "git" :cursor-pos 3)))
      (with-reduced-input-state (prev-state prev-output) (reduce-once state :page-up)
        (is-input-state prev-state :buffer "git" :cursor-pos 3)
        (expect :history-prev :to-be prev-output))
      (with-reduced-input-state (next-state next-output) (reduce-once state :page-down)
        (is-input-state next-state :buffer "git" :cursor-pos 3)
        (expect :history-next :to-be next-output))))

  (it "input-state-cursor-moves-clear-autosuggestion"
    (let ((state (input-state
                  :buffer "git status"
                  :cursor-pos 10
                  :suggestion " && apt upgrade")))
      (with-expected-input-state-reduction (left-state left-output)
          state
          (reduce-once state :left)
          :redraw
          (:buffer "git status" :cursor-pos 9 :suggestion nil)
        (with-expected-input-state-reduction (home-state home-output)
            state
            (reduce-once state :home)
            :redraw
            (:buffer "git status" :cursor-pos 0 :suggestion nil)))
      (with-expected-input-state-reduction (ctrl-b-state ctrl-b-output)
          state
          (reduce-once state :ctrl-b)
          :redraw
          (:buffer "git status" :cursor-pos 9 :suggestion nil))
      (with-expected-input-state-reduction (ctrl-a-state ctrl-a-output)
          state
          (reduce-once state :ctrl-a)
          :redraw
          (:buffer "git status" :cursor-pos 0 :suggestion nil))))

  (it "input-state-right-arrow-before-eol-clears-autosuggestion"
    (let ((state (input-state
                  :buffer "git status"
                  :cursor-pos 3
                  :suggestion " --short")))
      (with-expected-input-state-reduction (right-state right-output)
          state
          (reduce-once state :right)
          :redraw
          (:buffer "git status" :cursor-pos 4 :suggestion nil))))

  (it "input-state-modified-arrows-move-by-word-and-handle-mouse-redraw"
    (let ((state (input-state
                  :buffer "git checkout main"
                  :cursor-pos 17)))
      (with-expected-input-state-reduction (main-state main-output)
          state
          (reduce-once state :ctrl-left)
          :redraw
          (:cursor-pos 13)
        (with-reduced-input-state (checkout-state) (reduce-once main-state :alt-left)
          (is-input-state checkout-state :cursor-pos 4))))
    (let ((state (input-state
                  :buffer "git checkout main"
                  :cursor-pos 0)))
      (with-expected-input-state-reduction (git-state git-output)
          state
          (reduce-once state :alt-right)
          :redraw
          (:cursor-pos 4)
        (with-reduced-input-state (checkout-state) (reduce-once git-state :ctrl-right)
          (is-input-state checkout-state :cursor-pos 13))))
    (let ((state (input-state
                  :buffer "abc"
                  :cursor-pos 2)))
      (with-reduced-input-state (mouse-state mouse-output)
          (reduce-once state :mouse nil 0
                       '(:protocol :sgr :button 0 :column 2 :row 1))
        (is-input-state mouse-state :buffer "abc" :cursor-pos 2)
        (expect :redraw :to-be mouse-output))))

  (it "input-state-meta-b-and-f-move-by-word"
    (let ((state (input-state
                  :buffer "git checkout main"
                  :cursor-pos 17)))
      (with-expected-input-state-reduction (left-state left-output)
          state
          (reduce-once state :alt-b)
          :redraw
          (:cursor-pos 13)
        (with-reduced-input-state (right-state) (reduce-once left-state :alt-f)
          (is-input-state right-state :cursor-pos 17)))))

  (it "input-state-word-navigation-treats-escaped-space-as-token-content"
    (let ((state (input-state
                  :buffer "cat my\\ file.txt next"
                  :cursor-pos 4)))
      (with-expected-input-state-reduction (right-state right-output)
          state
          (reduce-once state :alt-right)
          :redraw
          (:cursor-pos 17)
        (with-reduced-input-state (left-state left-output) (reduce-once right-state :alt-left)
          (is-input-state left-state :cursor-pos 4)
          (expect :redraw :to-be left-output))))
    (let ((state (input-state
                  :buffer "cat my\\ file.txt next"
                  :cursor-pos 8)))
      (with-expected-input-state-reduction (right-state right-output)
          state
          (reduce-once state :alt-right)
          :redraw
          (:cursor-pos 17))))

  (it "input-state-word-navigation-treats-quoted-space-as-token-content"
    (let ((state (input-state
                  :buffer "echo \"hello world\" tail"
                  :cursor-pos 5)))
      (with-expected-input-state-reduction (right-state right-output)
          state
          (reduce-once state :ctrl-right)
          :redraw
          (:cursor-pos 19)
        (with-reduced-input-state (left-state left-output) (reduce-once right-state :ctrl-left)
          (is-input-state left-state :cursor-pos 5)
          (expect :redraw :to-be left-output))))
    (let ((state (input-state
                  :buffer "echo \"hello world\" tail"
                  :cursor-pos 8)))
      (with-expected-input-state-reduction (right-state right-output)
          state
          (reduce-once state :ctrl-right)
          :redraw
          (:cursor-pos 19))))

  (it "input-state-word-navigation-treats-shell-operators-as-boundaries"
    (let ((state (input-state
                  :buffer "echo one|two"
                  :cursor-pos 5)))
      (with-expected-input-state-reduction (two-start-state two-start-output)
          state
          (reduce-once state :alt-right)
          :redraw
          (:cursor-pos 9)
        (with-reduced-input-state (one-start-state one-start-output)
            (reduce-once two-start-state :alt-left)
          (is-input-state one-start-state :cursor-pos 5)
          (expect :redraw :to-be one-start-output)))))

  (it "shell-token-range-lookups-return-range-objects"
    (let ((inside (nshell.presentation::shell-token-range-at-position "echo foo" 5))
          (after (nshell.presentation::shell-token-range-at-or-after-cursor "echo foo" 4))
          (at-end (nshell.presentation::shell-token-range-at-or-after-cursor "echo foo" 8))
          (before (nshell.presentation::shell-token-range-before-position "echo foo" 4)))
      (expect (fboundp 'nshell.presentation::shell-token-range-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-shell-token-range) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::%make-shell-token-range) :to-be-truthy)
      (expect (nshell.presentation::%shell-token-range-p inside) :to-be-truthy)
      (expect 5 :to-equal (nshell.presentation::shell-token-range-start inside))
      (expect 8 :to-equal (nshell.presentation::shell-token-range-end inside))
      (expect (nshell.presentation::%shell-token-range-p after) :to-be-truthy)
      (expect 5 :to-equal (nshell.presentation::shell-token-range-start after))
      (expect 8 :to-equal (nshell.presentation::shell-token-range-end after))
      (expect (nshell.presentation::%shell-token-range-p at-end) :to-be-truthy)
      (expect 5 :to-equal (nshell.presentation::shell-token-range-start at-end))
      (expect 8 :to-equal (nshell.presentation::shell-token-range-end at-end))
      (expect (nshell.presentation::%shell-token-range-p before) :to-be-truthy)
      (expect 0 :to-equal (nshell.presentation::shell-token-range-start before))
      (expect 4 :to-equal (nshell.presentation::shell-token-range-end before))
      (expect (nshell.presentation::shell-token-range-at-position "echo foo" 4) :to-be-null)))

  (it "shell-token-range-set-stays-private-scan-boundary"
    (let ((range-set (nshell.presentation::shell-token-range-set-before
                      "echo foo"
                      8)))
      (expect (fboundp 'nshell.presentation::shell-token-range-set-p) :to-be-falsy)
      (expect (nshell.presentation::%shell-token-range-set-p range-set) :to-be-truthy)
      (expect (listp range-set) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-shell-token-range-set) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::%make-shell-token-range-set) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%shell-token-range-set-ranges) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::shell-token-range-set-ranges) :to-be-falsy)
      (let ((last-range (nshell.presentation::shell-token-range-set-last range-set)))
        (expect (nshell.presentation::%shell-token-range-p last-range) :to-be-truthy)
        (expect 5 :to-equal (nshell.presentation::shell-token-range-start last-range))
        (expect 8 :to-equal (nshell.presentation::shell-token-range-end last-range)))))

  (it "shell-token-range-raw-accessors-stay-internal"
    "shell-token-range exposes explicit readers; generated slot readers remain internal."
    (let ((range (nshell.presentation::shell-token-range-at-position "echo foo" 5)))
      (expect (fboundp 'nshell.presentation::%shell-token-range-start) :to-be-truthy)
      (expect (eq (symbol-function
                    'nshell.presentation::shell-token-range-start)
                   (symbol-function
                    'nshell.presentation::%shell-token-range-start)) :to-be-falsy)
      (expect 5 :to-equal (nshell.presentation::shell-token-range-start range))
      (expect 8 :to-equal (nshell.presentation::shell-token-range-end range))))

  (it "word-motion-targets-are-value-objects"
    (let ((left (nshell.presentation::word-motion-target-left "git checkout main" 17))
          (left-after-spaces (nshell.presentation::word-motion-target-left "git checkout main   " 20))
          (right (nshell.presentation::word-motion-target-right "git checkout main" 4))
          (empty-left (nshell.presentation::word-motion-target-left "" 0))
          (empty-right (nshell.presentation::word-motion-target-right "" 0)))
      (expect (nshell.presentation::%word-motion-target-p left) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::word-motion-target-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-word-motion-target) :to-be-falsy)
      (expect 13 :to-equal (nshell.presentation::word-motion-target-cursor-pos left))
      (expect (nshell.presentation::%word-motion-target-p left-after-spaces) :to-be-truthy)
      (expect 13 :to-equal (nshell.presentation::word-motion-target-cursor-pos left-after-spaces))
      (expect (nshell.presentation::%word-motion-target-p right) :to-be-truthy)
      (expect 13 :to-equal (nshell.presentation::word-motion-target-cursor-pos right))
      (expect 0 :to-equal (nshell.presentation::word-motion-target-cursor-pos empty-left))
      (expect 0 :to-equal (nshell.presentation::word-motion-target-cursor-pos empty-right))))

  (it "word-motion-target-raw-accessors-stay-internal"
    "word-motion-target exposes explicit readers; generated slot readers remain internal."
    (let ((target (nshell.presentation::word-motion-target-right "echo foo" 0)))
      (expect (fboundp 'nshell.presentation::%word-motion-target-cursor-pos) :to-be-truthy)
      (expect (eq (symbol-function
                    'nshell.presentation::word-motion-target-cursor-pos)
                   (symbol-function
                    'nshell.presentation::%word-motion-target-cursor-pos)) :to-be-falsy)
      (expect 5 :to-equal (nshell.presentation::word-motion-target-cursor-pos target))))

  (it "input-state-word-navigation-clears-visible-suggestion-when-moving"
    (let ((state (input-state
                  :buffer "git checkout main"
                  :cursor-pos 0
                  :suggestion " --branch")))
      (with-expected-input-state-reduction (alt-right-state alt-right-output)
          state
          (reduce-once state :alt-right)
          :redraw
          (:buffer "git checkout main" :cursor-pos 4 :suggestion nil))
      (with-expected-input-state-reduction (ctrl-right-state ctrl-right-output)
          state
          (reduce-once state :ctrl-right)
          :redraw
          (:buffer "git checkout main" :cursor-pos 4 :suggestion nil)))))
