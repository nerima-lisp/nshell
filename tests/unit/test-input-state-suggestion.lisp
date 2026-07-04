(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-right-arrow-at-eol-accepts-suggestion
  (with-expected-suggestion-reduction (new-state output)
      ("git" 3 " status" :right)
      "git status"
      10
      nil
      :suggest-update))

(test input-state-end-at-eol-accepts-suggestion
  (with-expected-suggestion-reduction (new-state output)
      ("git" 3 " status" :end)
      "git status"
      10
      nil
      :suggest-update))

(test input-state-ctrl-e-at-eol-accepts-suggestion
  (with-expected-suggestion-reduction (new-state output)
      ("git" 3 " status" :ctrl-e)
      "git status"
      10
      nil
      :suggest-update))

(test input-state-end-before-eol-moves-to-line-end-without-accepting-suggestion
  (with-expected-suggestion-reduction (new-state output)
      ("git status" 3 " --short" :end)
      "git status"
      10
      " --short"
      :redraw))

(test input-state-ctrl-e-before-eol-moves-to-line-end-without-accepting-suggestion
  (with-expected-suggestion-reduction (new-state output)
      ("git status" 3 " --short" :ctrl-e)
      "git status"
      10
      " --short"
      :redraw))

(test input-state-alt-right-at-eol-accepts-one-suggestion-word
  (with-expected-suggestion-reduction (first-state first-output)
      ("git" 3 " status --short" :alt-right)
      "git status"
      10
      " --short"
      :suggest-update
    (with-reduced-input-state (second-state second-output)
        (reduce-once first-state :alt-right)
      (is-input-state second-state
                      :buffer "git status --short"
                      :cursor-pos 18
                      :suggestion nil)
      (is (eq :suggest-update second-output)))))

(test input-state-ctrl-right-at-eol-accepts-one-suggestion-word
  (with-expected-suggestion-reduction (new-state output)
      ("git" 3 " status --short" :ctrl-right)
      "git status"
      10
      " --short"
      :suggest-update))

(test input-state-alt-right-at-eol-accepts-one-quoted-suggestion-token
  (with-expected-suggestion-reduction (new-state output)
      ("git commit -m" 13 " \"hello world\" --amend" :alt-right)
      "git commit -m \"hello world\""
      27
      " --amend"
      :suggest-update))

(test input-state-alt-right-at-eol-keeps-escaped-space-in-suggestion-token
  (with-expected-suggestion-reduction (new-state output)
      ("cat" 3 " my\\ file.txt tail" :alt-right)
      "cat my\\ file.txt"
      16
      " tail"
      :suggest-update))

(test input-state-ctrl-right-at-eol-keeps-escaped-space-in-suggestion-token
  (with-expected-suggestion-reduction (new-state output)
      ("cat" 3 " my\\ file.txt tail" :ctrl-right)
      "cat my\\ file.txt"
      16
      " tail"
      :suggest-update))

(test input-state-alt-right-at-eol-accepts-pipeline-operator-before-next-command
  (let ((state (input-state
                :buffer "git status"
                :cursor-pos 10
                :suggestion " | grep modified")))
    (with-reduced-input-state (pipe-state pipe-output) (reduce-once state :alt-right)
      (is-input-state pipe-state
                      :buffer "git status |"
                      :cursor-pos 12
                      :suggestion " grep modified")
      (is (eq :suggest-update pipe-output))
      (with-reduced-input-state (grep-state grep-output)
          (reduce-once pipe-state :alt-right)
        (is-input-state grep-state
                        :buffer "git status | grep"
                        :cursor-pos 17
                        :suggestion " modified")
        (is (eq :suggest-update grep-output))))))

(test input-state-alt-right-at-eol-accepts-redirection-operator-before-target
  (let ((state (input-state
                :buffer "echo hi"
                :cursor-pos 7
                :suggestion " > out.txt")))
    (with-reduced-input-state (redirect-state redirect-output)
        (reduce-once state :alt-right)
      (is-input-state redirect-state
                      :buffer "echo hi >"
                      :cursor-pos 9
                      :suggestion " out.txt")
      (is (eq :suggest-update redirect-output))
      (with-reduced-input-state (target-state target-output)
          (reduce-once redirect-state :alt-right)
        (is-input-state target-state
                        :buffer "echo hi > out.txt"
                        :cursor-pos 17
                        :suggestion nil)
        (is (eq :suggest-update target-output))))))

(test input-state-alt-right-at-eol-accepts-compact-fd-redirection
  (with-expected-suggestion-reduction (new-state output)
      ("grep error log" 14 " 2>&1 | less" :alt-right)
      "grep error log 2>&1"
      19
      " | less"
      :suggest-update))

(test input-state-alt-right-at-eol-accepts-multi-digit-fd-redirection
  (with-expected-suggestion-reduction (new-state output)
      ("grep error log" 14 " 2>&10 | less" :alt-right)
      "grep error log 2>&10"
      20
      " | less"
      :suggest-update))

(test input-state-alt-right-at-eol-accepts-closed-fd-redirection
  (with-expected-suggestion-reduction (new-state output)
      ("grep error log" 14 " 2>&- | less" :alt-right)
      "grep error log 2>&-"
      19
      " | less"
      :suggest-update))

(test input-state-alt-right-at-eol-accepts-attached-redirection-target
  (with-expected-suggestion-reduction (new-state output)
      ("echo hi" 7 " >out.txt && cat out.txt" :alt-right)
      "echo hi >out.txt"
      16
      " && cat out.txt"
      :suggest-update))

(test input-state-copy-explicit-nil-clears-suggestion
  (let* ((state (input-state
                 :buffer "git"
                 :cursor-pos 3
                 :suggestion " status"))
         (new-state (nshell.presentation::copy-input-state-with
                     state
                     :suggestion nil)))
    (is-input-state new-state :suggestion nil)))

(test input-state-normalize-clamps-cursor-and-keeps-other-slots
  (let ((state (input-state
                :buffer "git"
                :cursor-pos 99
                :suggestion " status"
                :search-query "g"
                :completion-index 2)))
    (nshell.presentation:with-normalized-input-state (normalized state)
      (is-input-state normalized
                      :buffer "git"
                      :cursor-pos 3
                      :suggestion " status"
                      :completion-index 2)
      (is (string= "g" (nshell.presentation:input-state-search-query normalized))))))

(test input-state-ctrl-g-cancels-visible-suggestion-without-editing
  (with-expected-suggestion-reduction (new-state output)
      ("git" 2 " status" :ctrl-g)
      "git"
      2
      nil
      :redraw))

(test input-state-suggestion-acceptance-stays-behind-public-projections
  "Autosuggestion acceptance should expose a value object, not raw split indexes."
  (let ((acceptance (nshell.presentation::next-suggestion-acceptance
                     " status --short")))
    (is (fboundp 'nshell.presentation::%make-suggestion-acceptance))
    (is (fboundp 'nshell.presentation::%suggestion-acceptance-accepted))
    (is (fboundp 'nshell.presentation::%suggestion-acceptance-remaining))
    (is (not (fboundp 'nshell.presentation::make-suggestion-acceptance)))
    (is (not (fboundp 'nshell.presentation::suggestion-next-word-end)))
    (is (fboundp 'nshell.presentation::%suggestion-next-word-end))
    (is (string= " status"
                 (nshell.presentation::suggestion-acceptance-accepted acceptance)))
    (is (string= " --short"
                 (nshell.presentation::suggestion-acceptance-remaining acceptance)))
    (is (string= (nshell.presentation::%suggestion-acceptance-accepted acceptance)
                 (nshell.presentation::suggestion-acceptance-accepted acceptance)))
    (is (string= (nshell.presentation::%suggestion-acceptance-remaining acceptance)
                 (nshell.presentation::suggestion-acceptance-remaining acceptance)))))

(test input-state-suggestion-append-edit-stays-behind-public-projections
  "Autosuggestion insertion should expose buffer, cursor, and remaining projections."
  (let* ((state (input-state
                 :buffer "git"
                 :cursor-pos 3
                 :suggestion " status --short"))
         (acceptance (nshell.presentation::next-suggestion-acceptance
                      (nshell.presentation:input-state-suggestion state)))
         (edit (nshell.presentation::suggestion-append-edit-for-state
                state
                (nshell.presentation::suggestion-acceptance-accepted acceptance)
                (nshell.presentation::suggestion-acceptance-remaining acceptance))))
    (is (fboundp 'nshell.presentation::%make-suggestion-append-plan))
    (is (fboundp 'nshell.presentation::%suggestion-append-plan-splice))
    (is (fboundp 'nshell.presentation::%make-suggestion-append-edit))
    (is (fboundp 'nshell.presentation::%suggestion-append-edit-plan))
    (is (not (fboundp 'nshell.presentation::make-suggestion-append-plan)))
    (is (not (fboundp 'nshell.presentation::make-suggestion-append-edit)))
    (is (not (fboundp 'nshell.presentation::suggestion-append-edit-splice)))
    (let ((plan (nshell.presentation::suggestion-append-edit-plan edit)))
      (is (nshell.presentation::suggestion-append-plan-p plan))
      (is (nshell.presentation::buffer-splice-p
           (nshell.presentation::suggestion-append-plan-splice plan))))
    (is (string= "git status"
                 (nshell.presentation::suggestion-append-edit-buffer
                  edit
                  (nshell.presentation:input-state-buffer state))))
    (is (= 10
           (nshell.presentation::suggestion-append-edit-cursor-pos edit)))
    (is (string= " --short"
                 (nshell.presentation::suggestion-append-edit-remaining edit)))
    (let ((finished-edit
            (nshell.presentation::suggestion-append-edit-for-state
             state
             (nshell.presentation:input-state-suggestion state)
             "")))
      (is (null (nshell.presentation::suggestion-append-edit-remaining
                 finished-edit))))))

(test input-state-suggestion-acceptance-commit-applies-state-transition
  "Reducers should commit suggestion acceptance rather than assembling append edits inline."
  (let* ((state (completion-session-state
                 :buffer "git"
                 :cursor-pos 3
                 :suggestion " status --short"
                 :completion-index 0
                 :completion-base-buffer "git"
                 :completion-base-cursor 3
                 :last-candidates '("status")))
         (acceptance (nshell.presentation::next-suggestion-acceptance
                      (nshell.presentation:input-state-suggestion state)))
         (new-state (nshell.presentation::commit-suggestion-acceptance
                     state
                     acceptance)))
    (is (fboundp 'nshell.presentation::commit-suggestion-acceptance))
    (is-input-state new-state
                    :buffer "git status"
                    :cursor-pos 10
                    :suggestion " --short"
                    :completion-index -1
                    :completion-base-buffer nil
                    :completion-base-cursor nil
                    :last-candidates nil)))

(test input-state-suggestion-word-like-token-p-returns-canonical-booleans
  (is (eq t (nshell.presentation::suggestion-word-like-token-p
             (nshell.domain.parsing:make-token :word "git"))))
  (is (eq t (nshell.presentation::suggestion-word-like-token-p
             (nshell.domain.parsing:make-token :error "git"))))
  (is (null (nshell.presentation::suggestion-word-like-token-p
             (nshell.domain.parsing:make-token :pipe "|")))))
