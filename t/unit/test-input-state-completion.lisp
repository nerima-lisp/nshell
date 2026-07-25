(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-completion-cycle-edit-stays-behind-public-projections"
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
      (expect (fboundp 'nshell.presentation::%make-completion-cycle-selection) :to-be-truthy)
      (expect (nshell.presentation::%completion-cycle-selection-p selection) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%completion-cycle-selection-base-buffer) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::make-completion-cycle-selection) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::completion-cycle-selection-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::%completion-cycle-selection) :to-be-falsy)
      (expect "git ch --dry-run" :to-equal (nshell.presentation::completion-cycle-selection-base-buffer
                    selection))
      (expect 6 :to-equal (nshell.presentation::completion-cycle-selection-base-cursor
              selection))
      (expect 0 :to-equal (nshell.presentation::completion-cycle-selection-index selection))
      (expect "checkout" :to-equal (nshell.presentation::completion-cycle-selection-candidate
                    selection))
      (expect (fboundp 'nshell.presentation::%make-completion-cycle-edit) :to-be-truthy)
      (expect (nshell.presentation::%completion-cycle-edit-p edit) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%completion-cycle-edit-buffer) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::make-completion-cycle-edit) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::completion-cycle-edit-p) :to-be-falsy)
      (expect "git checkout --dry-run" :to-equal (nshell.presentation::completion-cycle-edit-buffer edit))
      (expect 12 :to-equal (nshell.presentation::completion-cycle-edit-cursor-pos edit))
      (expect 0 :to-equal (nshell.presentation::completion-cycle-edit-index edit))
      (expect "git ch --dry-run" :to-equal (nshell.presentation::completion-cycle-edit-base-buffer edit))
      (expect 6 :to-equal (nshell.presentation::completion-cycle-edit-base-cursor edit))
      (is-input-state committed
                      :buffer "git checkout --dry-run"
                      :cursor-pos 12
                      :suggestion nil
                      :completion-index 0
                      :completion-base-buffer "git ch --dry-run"
                      :completion-base-cursor 6)))

  (it "input-state-tab-cycles-through-completion-candidates"
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
          (expect :complete :to-be first-output)
          (is-input-state second-state
                          :buffer "grep"
                          :completion-index 1)
          (is-input-state reverse-state
                          :buffer "git"
                          :completion-index 0)
          (expect :complete :to-be reverse-output))))

  (it "input-state-shift-tab-wraps-to-last-candidate-on-fresh-cycle"
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
        (expect :complete :to-be next-output))))

  (it "input-state-tab-completes-current-token-without-dropping-prefix"
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
          (expect :complete :to-be first-output)
          (is-input-state second-state
                          :buffer "git cherry-pick"
                          :cursor-pos 15)
          (is-input-state reverse-state
                          :buffer "git checkout"
                          :completion-index 0)
          (expect :complete :to-be reverse-output))))

  (it "input-state-tab-completes-token-at-cursor-without-dropping-suffix"
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
          (expect :complete :to-be first-output)
          (is-input-state second-state
                          :buffer "git cherry-pick --dry-run"
                          :cursor-pos 15))))

  (it "input-state-tab-completes-quoted-token-without-dropping-opening-quote"
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
        (expect :complete :to-be output))))

  (it "input-state-tab-completes-closed-quoted-token-without-dropping-closing-quote"
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
        (expect :complete :to-be output))))

  (it "input-state-tab-completes-single-quoted-token-without-escaping-spaces"
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
        (expect :complete :to-be output))))

  (it "input-state-tab-cycles-structured-completion-candidates"
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
          (expect :complete :to-be first-output)
          (expect candidates :to-be (nshell.presentation:input-state-last-candidates first-state))
          (expect "show working tree status" :to-equal (nshell.domain.completion:candidate-description
                        (first (nshell.presentation:input-state-last-candidates first-state))))
          (is-input-state second-state
                          :buffer "git stash"
                          :cursor-pos 9)
          (expect :complete :to-be second-output)
          (expect candidates :to-be (nshell.presentation:input-state-last-candidates second-state))
          (is-input-state reverse-state
                          :buffer "git status"
                          :completion-index 0)
          (expect :complete :to-be reverse-output))))

  (it "input-state-tab-shell-escapes-completion-candidate"
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
        (expect :complete :to-be first-output)
        (multiple-value-bind (second-state) (reduce-once first-state :tab)
          (is-input-state second-state
                          :buffer "cat my\\#script"
                          :cursor-pos 14)))))

  (it "input-state-tab-replaces-token-with-escaped-space"
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
        (expect :complete :to-be output)))))
