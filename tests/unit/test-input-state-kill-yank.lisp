(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-kill-edit-projects-buffer-and-killed-text"
    (let* ((plan (nshell.presentation::%make-kill-edit-plan 5 10 5))
           (edit (nshell.presentation::%make-kill-edit plan))
           (buffer "echo hello world"))
      (expect (nshell.presentation::%kill-edit-plan-p plan) :to-be-truthy)
      (expect (nshell.presentation::%kill-edit-p edit) :to-be-truthy)
      (expect plan :to-be (nshell.presentation::kill-edit-plan edit))
      (expect 5 :to-equal (nshell.presentation::kill-edit-plan-start plan))
      (expect 10 :to-equal (nshell.presentation::kill-edit-plan-end plan))
      (expect 5 :to-equal (nshell.presentation::kill-edit-plan-cursor-pos plan))
      (expect (fboundp 'nshell.presentation::make-kill-edit-plan) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-kill-edit) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::kill-edit-plan-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::kill-edit-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::kill-edit-start) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::kill-edit-end) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::kill-edit-cursor-pos) :to-be-falsy)
      (expect (nshell.presentation::kill-edit-empty-p edit) :to-be-falsy)
      (expect "hello" :to-equal (nshell.presentation::kill-edit-killed-text edit buffer))
      (expect "echo  world" :to-equal (nshell.presentation::kill-edit-buffer edit buffer))))

  (it "input-state-kill-edit-detects-empty-range"
    (expect (nshell.presentation::kill-edit-empty-p
         (nshell.presentation::%make-kill-edit
          (nshell.presentation::%make-kill-edit-plan 3 3 3))) :to-be-truthy))

  (it "input-state-kill-ring-selection-projects-entry-boundary"
    (let* ((state (input-state :kill-ring '("one" "two")))
           (selection (nshell.presentation::kill-ring-first-selection state))
           (next-selection
             (nshell.presentation::kill-ring-next-selection
              (nshell.presentation::input-state-kill-ring state)
              selection)))
      (expect (nshell.presentation::%kill-ring-selection-p selection) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%make-kill-ring-selection) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::kill-ring-selection-index) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::kill-ring-selection-text) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::make-kill-ring-selection) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::kill-ring-selection-p) :to-be-falsy)
      (expect 0 :to-equal (nshell.presentation::kill-ring-selection-index selection))
      (expect "one" :to-equal (nshell.presentation::kill-ring-selection-text selection))
      (expect 1 :to-equal (nshell.presentation::kill-ring-selection-index next-selection))
      (expect "two" :to-equal (nshell.presentation::kill-ring-selection-text next-selection))
      (expect (nshell.presentation::kill-ring-first-selection
                (input-state :kill-ring nil)) :to-be-falsy)
      (expect (nshell.presentation::kill-ring-selection-at nil 0) :to-be-falsy)))

  (it "input-state-yank-edit-commits-insertion-and-yank-metadata"
    (let* ((state (completion-session-state
                   :buffer "echo "
                   :cursor-pos 5
                   :completion-index 1
                   :suggestion " ignored"
                   :kill-ring '("one")))
           (edit (nshell.presentation::yank-edit-for-state state)))
      (expect (nshell.presentation::%yank-edit-p edit) :to-be-truthy)
      (let ((plan (nshell.presentation::yank-edit-plan edit)))
        (expect (nshell.presentation::%yank-edit-plan-p plan) :to-be-truthy)
        (expect 5 :to-equal (nshell.presentation::yank-edit-plan-start plan))
        (expect "one" :to-equal (nshell.presentation::yank-edit-plan-text plan))
        (expect "echo one" :to-equal (nshell.presentation::yank-edit-plan-buffer plan))
        (expect 8 :to-equal (nshell.presentation::yank-edit-plan-cursor-pos plan))
        (expect (fboundp 'nshell.presentation::make-yank-edit-plan) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::make-yank-edit) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-edit-plan-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-edit-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-edit-start) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-edit-text) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-edit-buffer) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-edit-cursor-pos) :to-be-falsy))
      (with-reduced-input-state (new-state output)
          (nshell.presentation::commit-yank-edit state edit)
        (is-input-state-with-completion-cleared
         new-state
         :buffer "echo one"
         :cursor-pos 8
         :kill-ring '("one"))
        (expect 5 :to-equal (nshell.presentation::input-state-last-yank-start new-state))
        (expect 8 :to-equal (nshell.presentation::input-state-last-yank-end new-state))
        (expect 0 :to-equal (nshell.presentation::input-state-last-yank-index new-state))
        (expect :suggest-update :to-be output))))

  (it "input-state-ctrl-w-kills-previous-word-into-kill-ring"
    (let ((state (completion-session-state
                  :buffer "git checkout main"
                  :cursor-pos 17
                  :completion-index 2
                  :suggestion " ignored")))
      (with-reduced-input-state (new-state output) (reduce-once state :ctrl-w)
        (is-input-state-with-completion-cleared
         new-state
         :buffer "git checkout "
         :cursor-pos 13
         :kill-ring '("main"))
        (expect :suggest-update :to-be output))))

  (it "input-state-ctrl-w-preserves-trailing-whitespace-in-kill-ring"
    (let ((state (input-state
                  :buffer "echo foo   "
                  :cursor-pos 11)))
      (with-reduced-input-state (new-state output) (reduce-once state :ctrl-w)
        (is-input-state
         new-state
         :buffer "echo "
         :cursor-pos 5
         :kill-ring '("foo   "))
        (expect :suggest-update :to-be output))))

  (it "input-state-alt-backspace-kills-previous-word"
    (let ((state (completion-session-state
                  :buffer "git checkout main"
                  :cursor-pos 17
                  :completion-index 1
                  :suggestion " ignored")))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-backspace)
        (is-input-state-with-completion-cleared
         new-state
         :buffer "git checkout "
         :cursor-pos 13
         :kill-ring '("main"))
        (expect :suggest-update :to-be output))))

  (it "input-state-alt-backspace-treats-shell-operators-as-word-boundaries"
    (let ((state (input-state
                  :buffer "echo one|two"
                  :cursor-pos 12)))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-backspace)
        (is-input-state
         new-state
         :buffer "echo one|"
         :cursor-pos 9
         :kill-ring '("two"))
        (expect :suggest-update :to-be output))))

  (it "input-state-ctrl-w-treats-escaped-space-as-token-content"
    (let ((state (input-state
                  :buffer "echo my\\ file.txt tail"
                  :cursor-pos 18)))
      (with-reduced-input-state (new-state output) (reduce-once state :ctrl-w)
        (is-input-state
         new-state
         :buffer "echo tail"
         :cursor-pos 5
         :kill-ring '("my\\ file.txt "))
        (expect :suggest-update :to-be output))))

  (it "input-state-alt-backspace-treats-quoted-space-as-token-content"
    (let ((state (input-state
                  :buffer "echo \"hello world\" tail"
                  :cursor-pos 19)))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-backspace)
        (is-input-state
         new-state
         :buffer "echo tail"
         :cursor-pos 5
         :kill-ring '("\"hello world\" "))
        (expect :suggest-update :to-be output))))

  (it "input-state-alt-d-kills-next-word"
    (let ((state (completion-session-state
                  :buffer "echo   hello world"
                  :cursor-pos 4
                  :completion-index 1
                  :suggestion " ignored")))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
        (is-input-state-with-completion-cleared
         new-state
         :buffer "echo world"
         :cursor-pos 4
         :kill-ring '("   hello"))
        (expect :suggest-update :to-be output)))
    (let ((state (input-state
                  :buffer "echo hello world"
                  :cursor-pos 7)))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
        (is-input-state
         new-state
         :buffer "echo he world"
         :cursor-pos 7
         :kill-ring '("llo"))
        (expect :suggest-update :to-be output))))

  (it "input-state-alt-d-includes-shell-operator-before-next-word"
    (let ((state (input-state
                  :buffer "echo one|two"
                  :cursor-pos 8)))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
        (is-input-state
         new-state
         :buffer "echo one"
         :cursor-pos 8
         :kill-ring '("|two"))
        (expect :suggest-update :to-be output))))

  (it "input-state-alt-d-treats-escaped-space-as-token-content"
    (let ((state (input-state
                  :buffer "echo my\\ file.txt tail"
                  :cursor-pos 4)))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
        (is-input-state
         new-state
         :buffer "echo tail"
         :cursor-pos 4
         :kill-ring '(" my\\ file.txt"))
        (expect :suggest-update :to-be output))))

  (it "input-state-alt-d-treats-quoted-space-as-token-content"
    (let ((state (input-state
                  :buffer "echo \"hello world\" tail"
                  :cursor-pos 4)))
      (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
        (is-input-state
         new-state
         :buffer "echo tail"
         :cursor-pos 4
         :kill-ring '(" \"hello world\""))
        (expect :suggest-update :to-be output))))

  (it "input-state-kill-and-yank-restores-killed-text"
    (let ((state (input-state
                  :buffer "echo hello world"
                  :cursor-pos 5)))
      (with-kill-then-yank (killed-right yanked-right) state :ctrl-k
        (is-input-state
         killed-right
         :buffer "echo "
         :kill-ring '("hello world"))
        (is-input-state
         yanked-right
         :buffer "echo hello world"
         :cursor-pos 16
         :kill-ring '("hello world"))))
    (let ((state (input-state
                  :buffer "echo hello world"
                  :cursor-pos 11)))
      (with-kill-then-yank (killed-left yanked-left) state :ctrl-u
        (is-input-state
         killed-left
         :buffer "world"
         :kill-ring '("echo hello "))
        (is-input-state yanked-left :buffer "echo hello world" :cursor-pos 11))))

  (it "input-state-alt-y-cycles-kill-ring-after-yank"
    (let ((state (input-state
                  :buffer "echo one two three"
                  :cursor-pos 18)))
      (with-reduced-input-states state
          (((killed-three killed-three-output) :ctrl-w)
           ((killed-two killed-two-output) :ctrl-w)
           ((yanked yank-output) :ctrl-y)
           ((popped pop-output) :alt-y)
           ((cycled cycle-output) :alt-y))
        (expect :suggest-update :to-be killed-three-output)
        (expect :suggest-update :to-be killed-two-output)
        (expect :suggest-update :to-be yank-output)
        (expect :suggest-update :to-be pop-output)
        (expect :suggest-update :to-be cycle-output)
        (is-input-state popped :buffer "echo one three" :cursor-pos 14)
        (is-input-state cycled :buffer "echo one two " :cursor-pos 13))))

  (it "input-state-yank-pop-edit-validates-recorded-yank"
    (let* ((state (input-state
                   :buffer "echo one"
                   :cursor-pos 8
                   :kill-ring '("one" "two")
                   :last-yank-start 5
                   :last-yank-end 8
                   :last-yank-index 0))
           (edit (nshell.presentation::yank-pop-edit-for-state state)))
      (expect (nshell.presentation::%yank-pop-edit-p edit) :to-be-truthy)
      (let ((plan (nshell.presentation::yank-pop-edit-plan edit)))
        (expect (nshell.presentation::%yank-pop-edit-plan-p plan) :to-be-truthy)
        (expect 5 :to-equal (nshell.presentation::yank-pop-edit-plan-start plan))
        (expect 8 :to-equal (nshell.presentation::yank-pop-edit-plan-end plan))
        (expect 1 :to-equal (nshell.presentation::yank-pop-edit-plan-next-index plan))
        (expect 8 :to-equal (nshell.presentation::yank-pop-edit-plan-cursor-pos plan))
        (expect "two" :to-equal (nshell.presentation::yank-pop-edit-plan-replacement plan))
        (expect "echo two" :to-equal (nshell.presentation::yank-pop-edit-plan-buffer
                      plan
                      "echo one"))
        (expect (fboundp 'nshell.presentation::make-yank-pop-edit-plan) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::make-yank-pop-edit) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-pop-edit-plan-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-pop-edit-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-pop-edit-start) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-pop-edit-end) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-pop-edit-next-index) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::yank-pop-edit-replacement) :to-be-falsy))))

  (it "input-state-yank-pop-edit-rejects-stale-yank-metadata"
    (expect (nshell.presentation::yank-pop-edit-for-state
               (input-state
                :buffer "echo other"
                :cursor-pos 10
                :kill-ring '("one" "two")
                :last-yank-start 5
                :last-yank-end 10
                :last-yank-index 0)) :to-be-null))

  (it "input-state-alt-y-noops-after-non-yank-edit"
    (let ((state (input-state
                  :buffer "echo one two"
                  :cursor-pos 12)))
      (with-reduced-input-states state
          (((killed-two killed-two-output) :ctrl-w)
           ((killed-one killed-one-output) :ctrl-w)
           ((yanked yank-output) :ctrl-y)
           ((edited edit-output) :char #\x)
           ((popped output) :alt-y))
        (expect :suggest-update :to-be killed-two-output)
        (expect :suggest-update :to-be killed-one-output)
        (expect :suggest-update :to-be yank-output)
        (expect :suggest-update :to-be edit-output)
        (expect :none :to-be output)
        (expect (nshell.presentation:input-state-buffer edited) :to-equal (nshell.presentation:input-state-buffer popped)))))

  (it "input-state-alt-y-noops-when-yank-metadata-is-stale"
    (let ((state (input-state
                  :buffer "echo other"
                  :cursor-pos 10
                  :kill-ring '("two" "one")
                  :last-yank-start 5
                  :last-yank-end 10
                  :last-yank-index 0)))
      (with-reduced-input-state (popped output) (reduce-once state :alt-y)
        (expect :none :to-be output)
        (is-input-state popped :buffer "echo other" :cursor-pos 10)))))
