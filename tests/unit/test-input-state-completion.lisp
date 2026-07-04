(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-completion-cycle-edit-stays-behind-public-projections
  "Completion cycling should commit an edit value, not raw apply-completion values."
  (let* ((state (input-state
                  :buffer "git ch --dry-run"
                  :cursor-pos 6
                  :suggestion " ignored"
                  :completion-index -1
                  :last-candidates '("checkout" "cherry-pick")))
         (selection (nshell.presentation::completion-cycle-selection-for-state
                     state
                     1
                     '("checkout" "cherry-pick")))
         (edit (nshell.presentation::completion-cycle-edit-for-selection selection))
         (committed (nshell.presentation::commit-completion-cycle-edit
                      state
                      edit)))
    (is (fboundp 'nshell.presentation::%make-completion-cycle-selection))
    (is (fboundp 'nshell.presentation::%completion-cycle-selection-base-buffer))
    (is (not (fboundp 'nshell.presentation::make-completion-cycle-selection)))
    (is (not (fboundp 'nshell.presentation::%completion-cycle-selection)))
    (is (string= "git ch --dry-run"
                 (nshell.presentation::completion-cycle-selection-base-buffer
                  selection)))
    (is (= 6
           (nshell.presentation::completion-cycle-selection-base-cursor
            selection)))
    (is (= 0
           (nshell.presentation::completion-cycle-selection-index selection)))
    (is (string= "checkout"
                 (nshell.presentation::completion-cycle-selection-candidate
                  selection)))
    (is (fboundp 'nshell.presentation::%make-completion-cycle-edit))
    (is (fboundp 'nshell.presentation::%completion-cycle-edit-buffer))
    (is (not (fboundp 'nshell.presentation::make-completion-cycle-edit)))
    (is (string= "git checkout --dry-run"
                 (nshell.presentation::completion-cycle-edit-buffer edit)))
    (is (= 12
           (nshell.presentation::completion-cycle-edit-cursor-pos edit)))
    (is (= 0
           (nshell.presentation::completion-cycle-edit-index edit)))
    (is (string= "git ch --dry-run"
                 (nshell.presentation::completion-cycle-edit-base-buffer edit)))
    (is (= 6
           (nshell.presentation::completion-cycle-edit-base-cursor edit)))
    (is-input-state committed
                    :buffer "git checkout --dry-run"
                    :cursor-pos 12
                    :suggestion nil
                    :completion-index 0
                    :completion-base-buffer "git ch --dry-run"
                    :completion-base-cursor 6)))

(test input-state-tab-cycles-through-completion-candidates
    (let ((state (input-state
                  :buffer "g"
                  :cursor-pos 1
                  :completion-index -1
                  :last-candidates '("git" "grep" "go"))))
      (with-reduced-input-states state
          (((first-state first-output) :tab)
           ((second-state) :tab)
           ((reverse-state reverse-output) :shift-tab))
        (is-input-state first-state
                        :buffer "git"
                        :completion-index 0)
        (is (eq :complete first-output))
        (is-input-state second-state
                        :buffer "grep"
                        :completion-index 1)
        (is-input-state reverse-state
                        :buffer "git"
                        :completion-index 0)
        (is (eq :complete reverse-output)))))

(test input-state-shift-tab-wraps-to-last-candidate-on-fresh-cycle
  (let ((state (input-state
                :buffer "g"
                :cursor-pos 1
                :completion-index -1
                :last-candidates '("git" "grep" "go"))))
    (multiple-value-bind (next-state next-output) (reduce-once state :shift-tab)
      (is-input-state next-state
                      :buffer "go"
                      :completion-index 2
                      :completion-base-buffer "g"
                      :completion-base-cursor 1)
      (is (eq :complete next-output)))))

(test input-state-tab-completes-current-token-without-dropping-prefix
    (let ((state (input-state
                  :buffer "git ch"
                  :cursor-pos 6
                  :completion-index -1
                  :last-candidates '("checkout" "cherry-pick"))))
      (with-reduced-input-states state
          (((first-state first-output) :tab)
           ((second-state) :tab)
           ((reverse-state reverse-output) :shift-tab))
        (is-input-state first-state
                        :buffer "git checkout"
                        :cursor-pos 12
                        :completion-base-buffer "git ch")
        (is (eq :complete first-output))
        (is-input-state second-state
                        :buffer "git cherry-pick"
                        :cursor-pos 15)
        (is-input-state reverse-state
                        :buffer "git checkout"
                        :completion-index 0)
        (is (eq :complete reverse-output)))))

(test input-state-tab-completes-token-at-cursor-without-dropping-suffix
    (let ((state (input-state
                  :buffer "git ch --dry-run"
                  :cursor-pos 6
                  :completion-index -1
                  :last-candidates '("checkout" "cherry-pick"))))
      (with-reduced-input-states state
          (((first-state first-output) :tab)
           ((second-state) :tab))
        (is-input-state first-state
                        :buffer "git checkout --dry-run"
                        :cursor-pos 12
                        :completion-base-buffer "git ch --dry-run"
                        :completion-base-cursor 6)
        (is (eq :complete first-output))
        (is-input-state second-state
                        :buffer "git cherry-pick --dry-run"
                        :cursor-pos 15))))

(test input-state-tab-completes-quoted-token-without-dropping-opening-quote
  (let ((state (input-state
                :buffer "echo \"he"
                :cursor-pos 8
                :completion-index -1
                :last-candidates '("hello world" "hello there"))))
    (multiple-value-bind (new-state output) (reduce-once state :tab)
      (is-input-state new-state
                      :buffer "echo \"hello world"
                      :cursor-pos 17
                      :completion-base-buffer "echo \"he"
                      :completion-base-cursor 8)
      (is (eq :complete output)))))

(test input-state-tab-completes-closed-quoted-token-without-dropping-closing-quote
  (let ((state (input-state
                :buffer "echo \"he\""
                :cursor-pos 9
                :completion-index -1
                :last-candidates '("hello world" "hello there"))))
    (multiple-value-bind (new-state output) (reduce-once state :tab)
      (is-input-state new-state
                      :buffer "echo \"hello world\""
                      :cursor-pos 17
                      :completion-base-buffer "echo \"he\""
                      :completion-base-cursor 9)
      (is (eq :complete output)))))

(test input-state-tab-completes-single-quoted-token-without-escaping-spaces
  (let ((state (input-state
                :buffer "echo 'he"
                :cursor-pos 8
                :completion-index -1
                :last-candidates '("hello world" "hello there"))))
    (multiple-value-bind (new-state output) (reduce-once state :tab)
      (is-input-state new-state
                      :buffer "echo 'hello world"
                      :cursor-pos 17
                      :completion-base-buffer "echo 'he"
                      :completion-base-cursor 8)
      (is (eq :complete output)))))

(test input-state-tab-cycles-structured-completion-candidates
    (let* ((status (nshell.domain.completion:make-candidate
                  "status"
                  :kind :command
                  :description "show working tree status"
                  :score 10))
         (stash (nshell.domain.completion:make-candidate
                 "stash"
                 :kind :command
                 :description "store local modifications"
                 :score 9))
         (candidates (list status stash))
           (state (input-state
                   :buffer "git st"
                   :cursor-pos 6
                   :completion-index -1
                   :last-candidates candidates)))
      (with-reduced-input-states state
          (((first-state first-output) :tab)
           ((second-state second-output) :tab)
           ((reverse-state reverse-output) :shift-tab))
        (is-input-state first-state
                        :buffer "git status"
                        :cursor-pos 10)
        (is (eq :complete first-output))
        (is (eq candidates (nshell.presentation:input-state-last-candidates first-state)))
        (is (string= "show working tree status"
                     (nshell.domain.completion:candidate-description
                      (first (nshell.presentation:input-state-last-candidates first-state)))))
        (is-input-state second-state
                        :buffer "git stash"
                        :cursor-pos 9)
        (is (eq :complete second-output))
        (is (eq candidates (nshell.presentation:input-state-last-candidates second-state)))
        (is-input-state reverse-state
                        :buffer "git status"
                        :completion-index 0)
        (is (eq :complete reverse-output)))))

(test input-state-tab-shell-escapes-completion-candidate
  (let ((state (input-state
                :buffer "cat my"
                :cursor-pos 6
                :completion-index -1
                :last-candidates '("my file.txt" "my#script"))))
    (multiple-value-bind (first-state first-output) (reduce-once state :tab)
      (is-input-state first-state
                      :buffer "cat my\\ file.txt"
                      :cursor-pos 16
                      :completion-base-buffer "cat my"
                      :completion-base-cursor 6)
      (is (eq :complete first-output))
      (multiple-value-bind (second-state) (reduce-once first-state :tab)
        (is-input-state second-state
                        :buffer "cat my\\#script"
                        :cursor-pos 14)))))

(test input-state-tab-replaces-token-with-escaped-space
  (let ((state (input-state
                :buffer "cat my\\ file"
                :cursor-pos 12
                :completion-index -1
                :last-candidates '("my file.txt" "my file.md"))))
    (multiple-value-bind (new-state output) (reduce-once state :tab)
      (is-input-state new-state
                      :buffer "cat my\\ file.txt"
                      :cursor-pos 16
                      :completion-base-buffer "cat my\\ file"
                      :completion-base-cursor 12)
      (is (eq :complete output)))))
