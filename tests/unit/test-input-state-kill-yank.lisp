(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-kill-edit-projects-buffer-and-killed-text
  (let* ((plan (nshell.presentation::%make-kill-edit-plan 5 10 5))
         (edit (nshell.presentation::%make-kill-edit plan))
         (buffer "echo hello world"))
    (is (nshell.presentation::%kill-edit-plan-p plan))
    (is (nshell.presentation::%kill-edit-p edit))
    (is (eq plan (nshell.presentation::kill-edit-plan edit)))
    (is (= 5 (nshell.presentation::kill-edit-plan-start plan)))
    (is (= 10 (nshell.presentation::kill-edit-plan-end plan)))
    (is (= 5 (nshell.presentation::kill-edit-plan-cursor-pos plan)))
    (is (not (fboundp 'nshell.presentation::make-kill-edit-plan)))
    (is (not (fboundp 'nshell.presentation::make-kill-edit)))
    (is (not (fboundp 'nshell.presentation::kill-edit-plan-p)))
    (is (not (fboundp 'nshell.presentation::kill-edit-p)))
    (is (not (fboundp 'nshell.presentation::kill-edit-start)))
    (is (not (fboundp 'nshell.presentation::kill-edit-end)))
    (is (not (fboundp 'nshell.presentation::kill-edit-cursor-pos)))
    (is (not (nshell.presentation::kill-edit-empty-p edit)))
    (is (string= "hello"
                 (nshell.presentation::kill-edit-killed-text edit buffer)))
    (is (string= "echo  world"
                 (nshell.presentation::kill-edit-buffer edit buffer)))))

(test input-state-kill-edit-detects-empty-range
  (is (nshell.presentation::kill-edit-empty-p
       (nshell.presentation::%make-kill-edit
        (nshell.presentation::%make-kill-edit-plan 3 3 3)))))

(test input-state-kill-ring-selection-projects-entry-boundary
  (let* ((state (input-state :kill-ring '("one" "two")))
         (selection (nshell.presentation::kill-ring-first-selection state))
         (next-selection
           (nshell.presentation::kill-ring-next-selection
            (nshell.presentation::input-state-kill-ring state)
            selection)))
    (is (nshell.presentation::%kill-ring-selection-p selection))
    (is (fboundp 'nshell.presentation::%make-kill-ring-selection))
    (is (fboundp 'nshell.presentation::kill-ring-selection-index))
    (is (fboundp 'nshell.presentation::kill-ring-selection-text))
    (is (not (fboundp 'nshell.presentation::make-kill-ring-selection)))
    (is (not (fboundp 'nshell.presentation::kill-ring-selection-p)))
    (is (= 0 (nshell.presentation::kill-ring-selection-index selection)))
    (is (string= "one"
                 (nshell.presentation::kill-ring-selection-text selection)))
    (is (= 1 (nshell.presentation::kill-ring-selection-index next-selection)))
    (is (string= "two"
                 (nshell.presentation::kill-ring-selection-text next-selection)))
    (is (not (nshell.presentation::kill-ring-first-selection
              (input-state :kill-ring nil))))
    (is (not (nshell.presentation::kill-ring-selection-at nil 0)))))

(test input-state-yank-edit-commits-insertion-and-yank-metadata
  (let* ((state (completion-session-state
                 :buffer "echo "
                 :cursor-pos 5
                 :completion-index 1
                 :suggestion " ignored"
                 :kill-ring '("one")))
         (edit (nshell.presentation::yank-edit-for-state state)))
    (is (nshell.presentation::%yank-edit-p edit))
    (let ((plan (nshell.presentation::yank-edit-plan edit)))
      (is (nshell.presentation::%yank-edit-plan-p plan))
      (is (= 5 (nshell.presentation::yank-edit-plan-start plan)))
      (is (string= "one" (nshell.presentation::yank-edit-plan-text plan)))
      (is (string= "echo one"
                   (nshell.presentation::yank-edit-plan-buffer plan)))
      (is (= 8 (nshell.presentation::yank-edit-plan-cursor-pos plan)))
      (is (not (fboundp 'nshell.presentation::make-yank-edit-plan)))
      (is (not (fboundp 'nshell.presentation::make-yank-edit)))
      (is (not (fboundp 'nshell.presentation::yank-edit-plan-p)))
      (is (not (fboundp 'nshell.presentation::yank-edit-p)))
      (is (not (fboundp 'nshell.presentation::yank-edit-start)))
      (is (not (fboundp 'nshell.presentation::yank-edit-text)))
      (is (not (fboundp 'nshell.presentation::yank-edit-buffer)))
      (is (not (fboundp 'nshell.presentation::yank-edit-cursor-pos))))
    (with-reduced-input-state (new-state output)
        (nshell.presentation::commit-yank-edit state edit)
      (is-input-state-with-completion-cleared
       new-state
       :buffer "echo one"
       :cursor-pos 8
       :kill-ring '("one"))
      (is (= 5 (nshell.presentation::input-state-last-yank-start new-state)))
      (is (= 8 (nshell.presentation::input-state-last-yank-end new-state)))
      (is (= 0 (nshell.presentation::input-state-last-yank-index new-state)))
      (is (eq :suggest-update output)))))

(test input-state-ctrl-w-kills-previous-word-into-kill-ring
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
      (is (eq :suggest-update output)))))

(test input-state-ctrl-w-preserves-trailing-whitespace-in-kill-ring
  (let ((state (input-state
                :buffer "echo foo   "
                :cursor-pos 11)))
    (with-reduced-input-state (new-state output) (reduce-once state :ctrl-w)
      (is-input-state
       new-state
       :buffer "echo "
       :cursor-pos 5
       :kill-ring '("foo   "))
      (is (eq :suggest-update output)))))

(test input-state-alt-backspace-kills-previous-word
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
      (is (eq :suggest-update output)))))

(test input-state-alt-backspace-treats-shell-operators-as-word-boundaries
  (let ((state (input-state
                :buffer "echo one|two"
                :cursor-pos 12)))
    (with-reduced-input-state (new-state output) (reduce-once state :alt-backspace)
      (is-input-state
       new-state
       :buffer "echo one|"
       :cursor-pos 9
       :kill-ring '("two"))
      (is (eq :suggest-update output)))))

(test input-state-ctrl-w-treats-escaped-space-as-token-content
  (let ((state (input-state
                :buffer "echo my\\ file.txt tail"
                :cursor-pos 18)))
    (with-reduced-input-state (new-state output) (reduce-once state :ctrl-w)
      (is-input-state
       new-state
       :buffer "echo tail"
       :cursor-pos 5
       :kill-ring '("my\\ file.txt "))
      (is (eq :suggest-update output)))))

(test input-state-alt-backspace-treats-quoted-space-as-token-content
  (let ((state (input-state
                :buffer "echo \"hello world\" tail"
                :cursor-pos 19)))
    (with-reduced-input-state (new-state output) (reduce-once state :alt-backspace)
      (is-input-state
       new-state
       :buffer "echo tail"
       :cursor-pos 5
       :kill-ring '("\"hello world\" "))
      (is (eq :suggest-update output)))))

(test input-state-alt-d-kills-next-word
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
      (is (eq :suggest-update output))))
  (let ((state (input-state
                :buffer "echo hello world"
                :cursor-pos 7)))
    (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
      (is-input-state
       new-state
       :buffer "echo he world"
       :cursor-pos 7
       :kill-ring '("llo"))
      (is (eq :suggest-update output)))))

(test input-state-alt-d-includes-shell-operator-before-next-word
  (let ((state (input-state
                :buffer "echo one|two"
                :cursor-pos 8)))
    (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
      (is-input-state
       new-state
       :buffer "echo one"
       :cursor-pos 8
       :kill-ring '("|two"))
      (is (eq :suggest-update output)))))

(test input-state-alt-d-treats-escaped-space-as-token-content
  (let ((state (input-state
                :buffer "echo my\\ file.txt tail"
                :cursor-pos 4)))
    (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
      (is-input-state
       new-state
       :buffer "echo tail"
       :cursor-pos 4
       :kill-ring '(" my\\ file.txt"))
      (is (eq :suggest-update output)))))

(test input-state-alt-d-treats-quoted-space-as-token-content
  (let ((state (input-state
                :buffer "echo \"hello world\" tail"
                :cursor-pos 4)))
    (with-reduced-input-state (new-state output) (reduce-once state :alt-d)
      (is-input-state
       new-state
       :buffer "echo tail"
       :cursor-pos 4
       :kill-ring '(" \"hello world\""))
      (is (eq :suggest-update output)))))

(test input-state-kill-and-yank-restores-killed-text
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

(test input-state-alt-y-cycles-kill-ring-after-yank
  (let ((state (input-state
                :buffer "echo one two three"
                :cursor-pos 18)))
    (with-reduced-input-states state
        (((killed-three killed-three-output) :ctrl-w)
         ((killed-two killed-two-output) :ctrl-w)
         ((yanked yank-output) :ctrl-y)
         ((popped pop-output) :alt-y)
         ((cycled cycle-output) :alt-y))
      (is (eq :suggest-update killed-three-output))
      (is (eq :suggest-update killed-two-output))
      (is (eq :suggest-update yank-output))
      (is (eq :suggest-update pop-output))
      (is (eq :suggest-update cycle-output))
      (is-input-state popped :buffer "echo one three" :cursor-pos 14)
      (is-input-state cycled :buffer "echo one two " :cursor-pos 13))))

(test input-state-yank-pop-edit-validates-recorded-yank
  (let* ((state (input-state
                 :buffer "echo one"
                 :cursor-pos 8
                 :kill-ring '("one" "two")
                 :last-yank-start 5
                 :last-yank-end 8
                 :last-yank-index 0))
         (edit (nshell.presentation::yank-pop-edit-for-state state)))
    (is (nshell.presentation::%yank-pop-edit-p edit))
    (let ((plan (nshell.presentation::yank-pop-edit-plan edit)))
      (is (nshell.presentation::%yank-pop-edit-plan-p plan))
      (is (= 5 (nshell.presentation::yank-pop-edit-plan-start plan)))
      (is (= 8 (nshell.presentation::yank-pop-edit-plan-end plan)))
      (is (= 1 (nshell.presentation::yank-pop-edit-plan-next-index plan)))
      (is (= 8 (nshell.presentation::yank-pop-edit-plan-cursor-pos plan)))
      (is (string= "two"
                   (nshell.presentation::yank-pop-edit-plan-replacement plan)))
      (is (string= "echo two"
                   (nshell.presentation::yank-pop-edit-plan-buffer
                    plan
                    "echo one")))
      (is (not (fboundp 'nshell.presentation::make-yank-pop-edit-plan)))
      (is (not (fboundp 'nshell.presentation::make-yank-pop-edit)))
      (is (not (fboundp 'nshell.presentation::yank-pop-edit-plan-p)))
      (is (not (fboundp 'nshell.presentation::yank-pop-edit-p)))
      (is (not (fboundp 'nshell.presentation::yank-pop-edit-start)))
      (is (not (fboundp 'nshell.presentation::yank-pop-edit-end)))
      (is (not (fboundp 'nshell.presentation::yank-pop-edit-next-index)))
      (is (not (fboundp 'nshell.presentation::yank-pop-edit-replacement))))))

(test input-state-yank-pop-edit-rejects-stale-yank-metadata
  (is (null (nshell.presentation::yank-pop-edit-for-state
             (input-state
              :buffer "echo other"
              :cursor-pos 10
              :kill-ring '("one" "two")
              :last-yank-start 5
              :last-yank-end 10
              :last-yank-index 0)))))

(test input-state-alt-y-noops-after-non-yank-edit
  (let ((state (input-state
                :buffer "echo one two"
                :cursor-pos 12)))
    (with-reduced-input-states state
        (((killed-two killed-two-output) :ctrl-w)
         ((killed-one killed-one-output) :ctrl-w)
         ((yanked yank-output) :ctrl-y)
         ((edited edit-output) :char #\x)
         ((popped output) :alt-y))
      (is (eq :suggest-update killed-two-output))
      (is (eq :suggest-update killed-one-output))
      (is (eq :suggest-update yank-output))
      (is (eq :suggest-update edit-output))
      (is (eq :none output))
      (is (string= (nshell.presentation:input-state-buffer edited)
                   (nshell.presentation:input-state-buffer popped))))))

(test input-state-alt-y-noops-when-yank-metadata-is-stale
  (let ((state (input-state
                :buffer "echo other"
                :cursor-pos 10
                :kill-ring '("two" "one")
                :last-yank-start 5
                :last-yank-end 10
                :last-yank-index 0)))
    (with-reduced-input-state (popped output) (reduce-once state :alt-y)
      (is (eq :none output))
      (is-input-state popped :buffer "echo other" :cursor-pos 10))))
