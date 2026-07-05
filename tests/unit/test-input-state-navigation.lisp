(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-cursor-moves-with-arrow-keys-within-bounds
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

(test input-state-page-navigation-requests-history-traversal
  (let ((state (input-state :buffer "git" :cursor-pos 3)))
    (with-reduced-input-state (prev-state prev-output) (reduce-once state :page-up)
      (is-input-state prev-state :buffer "git" :cursor-pos 3)
      (is (eq :history-prev prev-output)))
    (with-reduced-input-state (next-state next-output) (reduce-once state :page-down)
      (is-input-state next-state :buffer "git" :cursor-pos 3)
      (is (eq :history-next next-output)))))

(test input-state-cursor-moves-clear-autosuggestion
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

(test input-state-right-arrow-before-eol-clears-autosuggestion
  (let ((state (input-state
                :buffer "git status"
                :cursor-pos 3
                :suggestion " --short")))
    (with-expected-input-state-reduction (right-state right-output)
        state
        (reduce-once state :right)
        :redraw
        (:buffer "git status" :cursor-pos 4 :suggestion nil))))

(test input-state-modified-arrows-move-by-word-and-handle-mouse-redraw
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
      (is (eq :redraw mouse-output)))))

(test input-state-meta-b-and-f-move-by-word
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

(test input-state-word-navigation-treats-escaped-space-as-token-content
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
        (is (eq :redraw left-output)))))
  (let ((state (input-state
                :buffer "cat my\\ file.txt next"
                :cursor-pos 8)))
    (with-expected-input-state-reduction (right-state right-output)
        state
        (reduce-once state :alt-right)
        :redraw
        (:cursor-pos 17))))

(test input-state-word-navigation-treats-quoted-space-as-token-content
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
        (is (eq :redraw left-output)))))
  (let ((state (input-state
                :buffer "echo \"hello world\" tail"
                :cursor-pos 8)))
    (with-expected-input-state-reduction (right-state right-output)
        state
        (reduce-once state :ctrl-right)
        :redraw
        (:cursor-pos 19))))

(test input-state-word-navigation-treats-shell-operators-as-boundaries
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
        (is (eq :redraw one-start-output))))))

(test shell-token-range-lookups-return-range-objects
  (let ((inside (nshell.presentation::shell-token-range-at-position "echo foo" 5))
        (after (nshell.presentation::shell-token-range-at-or-after-cursor "echo foo" 4))
        (at-end (nshell.presentation::shell-token-range-at-or-after-cursor "echo foo" 8))
        (before (nshell.presentation::shell-token-range-before-position "echo foo" 4)))
    (is (not (fboundp 'nshell.presentation::shell-token-range-p)))
    (is (not (fboundp 'nshell.presentation::make-shell-token-range)))
    (is (fboundp 'nshell.presentation::%make-shell-token-range))
    (is (nshell.presentation::%shell-token-range-p inside))
    (is (= 5 (nshell.presentation::shell-token-range-start inside)))
    (is (= 8 (nshell.presentation::shell-token-range-end inside)))
    (is (nshell.presentation::%shell-token-range-p after))
    (is (= 5 (nshell.presentation::shell-token-range-start after)))
    (is (= 8 (nshell.presentation::shell-token-range-end after)))
    (is (nshell.presentation::%shell-token-range-p at-end))
    (is (= 5 (nshell.presentation::shell-token-range-start at-end)))
    (is (= 8 (nshell.presentation::shell-token-range-end at-end)))
    (is (nshell.presentation::%shell-token-range-p before))
    (is (= 0 (nshell.presentation::shell-token-range-start before)))
    (is (= 4 (nshell.presentation::shell-token-range-end before)))
    (is (null (nshell.presentation::shell-token-range-at-position "echo foo" 4)))))

(test shell-token-range-set-stays-private-scan-boundary
  (let ((range-set (nshell.presentation::shell-token-range-set-before
                    "echo foo"
                    8)))
    (is (not (fboundp 'nshell.presentation::shell-token-range-set-p)))
    (is (nshell.presentation::%shell-token-range-set-p range-set))
    (is (not (listp range-set)))
    (is (not (fboundp 'nshell.presentation::make-shell-token-range-set)))
    (is (fboundp 'nshell.presentation::%make-shell-token-range-set))
    (is (fboundp 'nshell.presentation::%shell-token-range-set-ranges))
    (is (not (fboundp 'nshell.presentation::shell-token-range-set-ranges)))
    (let ((last-range (nshell.presentation::shell-token-range-set-last range-set)))
      (is (nshell.presentation::%shell-token-range-p last-range))
      (is (= 5 (nshell.presentation::shell-token-range-start last-range)))
      (is (= 8 (nshell.presentation::shell-token-range-end last-range))))))

(test shell-token-range-raw-accessors-stay-internal
  "shell-token-range exposes explicit readers; generated slot readers remain internal."
  (let ((range (nshell.presentation::shell-token-range-at-position "echo foo" 5)))
    (is (fboundp 'nshell.presentation::%shell-token-range-start))
    (is (not (eq (symbol-function
                  'nshell.presentation::shell-token-range-start)
                 (symbol-function
                  'nshell.presentation::%shell-token-range-start))))
    (is (= 5 (nshell.presentation::shell-token-range-start range)))
    (is (= 8 (nshell.presentation::shell-token-range-end range)))))

(test word-motion-targets-are-value-objects
  (let ((left (nshell.presentation::word-motion-target-left "git checkout main" 17))
        (left-after-spaces (nshell.presentation::word-motion-target-left "git checkout main   " 20))
        (right (nshell.presentation::word-motion-target-right "git checkout main" 4))
        (empty-left (nshell.presentation::word-motion-target-left "" 0))
        (empty-right (nshell.presentation::word-motion-target-right "" 0)))
    (is (nshell.presentation::%word-motion-target-p left))
    (is (not (fboundp 'nshell.presentation::word-motion-target-p)))
    (is (not (fboundp 'nshell.presentation::make-word-motion-target)))
    (is (= 13 (nshell.presentation::word-motion-target-cursor-pos left)))
    (is (nshell.presentation::%word-motion-target-p left-after-spaces))
    (is (= 13 (nshell.presentation::word-motion-target-cursor-pos left-after-spaces)))
    (is (nshell.presentation::%word-motion-target-p right))
    (is (= 13 (nshell.presentation::word-motion-target-cursor-pos right)))
    (is (= 0 (nshell.presentation::word-motion-target-cursor-pos empty-left)))
    (is (= 0 (nshell.presentation::word-motion-target-cursor-pos empty-right)))))

(test word-motion-target-raw-accessors-stay-internal
  "word-motion-target exposes explicit readers; generated slot readers remain internal."
  (let ((target (nshell.presentation::word-motion-target-right "echo foo" 0)))
    (is (fboundp 'nshell.presentation::%word-motion-target-cursor-pos))
    (is (not (eq (symbol-function
                  'nshell.presentation::word-motion-target-cursor-pos)
                 (symbol-function
                  'nshell.presentation::%word-motion-target-cursor-pos))))
    (is (= 5 (nshell.presentation::word-motion-target-cursor-pos target)))))

(test input-state-word-navigation-clears-visible-suggestion-when-moving
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
        (:buffer "git checkout main" :cursor-pos 4 :suggestion nil))))
