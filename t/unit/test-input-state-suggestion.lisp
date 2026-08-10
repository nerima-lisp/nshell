(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-right-arrow-at-eol-accepts-suggestion"
    (with-expected-suggestion-reduction (new-state output)
        ("git" 3 " status" :right)
        "git status"
        10
        nil
        :suggest-update))

  (it "input-state-end-at-eol-accepts-suggestion"
    (with-expected-suggestion-reduction (new-state output)
        ("git" 3 " status" :end)
        "git status"
        10
        nil
        :suggest-update))

  (it "input-state-ctrl-e-at-eol-accepts-suggestion"
    (with-expected-suggestion-reduction (new-state output)
        ("git" 3 " status" :ctrl-e)
        "git status"
        10
        nil
        :suggest-update))

  (it "input-state-end-before-eol-moves-to-line-end-without-accepting-suggestion"
    (with-expected-suggestion-reduction (new-state output)
        ("git status" 3 " --short" :end)
        "git status"
        10
        " --short"
        :redraw))

  (it "input-state-ctrl-e-before-eol-moves-to-line-end-without-accepting-suggestion"
    (with-expected-suggestion-reduction (new-state output)
        ("git status" 3 " --short" :ctrl-e)
        "git status"
        10
        " --short"
        :redraw))

  (it "input-state-alt-right-at-eol-accepts-one-suggestion-word"
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
        (expect :suggest-update :to-be second-output))))

  (it "input-state-ctrl-right-at-eol-accepts-one-suggestion-word"
    (with-expected-suggestion-reduction (new-state output)
        ("git" 3 " status --short" :ctrl-right)
        "git status"
        10
        " --short"
        :suggest-update))

  (it "input-state-alt-right-at-eol-accepts-one-quoted-suggestion-token"
    (with-expected-suggestion-reduction (new-state output)
        ("git commit -m" 13 " \"hello world\" --amend" :alt-right)
        "git commit -m \"hello world\""
        27
        " --amend"
        :suggest-update))

  (it "input-state-alt-right-at-eol-keeps-escaped-space-in-suggestion-token"
    (with-expected-suggestion-reduction (new-state output)
        ("cat" 3 " my\\ file.txt tail" :alt-right)
        "cat my\\ file.txt"
        16
        " tail"
        :suggest-update))

  (it "input-state-ctrl-right-at-eol-keeps-escaped-space-in-suggestion-token"
    (with-expected-suggestion-reduction (new-state output)
        ("cat" 3 " my\\ file.txt tail" :ctrl-right)
        "cat my\\ file.txt"
        16
        " tail"
        :suggest-update))

  (it "input-state-alt-right-at-eol-accepts-pipeline-operator-before-next-command"
    (let ((state (input-state
                  :buffer "git status"
                  :cursor-pos 10
                  :suggestion " | grep modified")))
      (with-reduced-input-state (pipe-state pipe-output) (reduce-once state :alt-right)
        (is-input-state pipe-state
                        :buffer "git status |"
                        :cursor-pos 12
                        :suggestion " grep modified")
        (expect :suggest-update :to-be pipe-output)
        (with-reduced-input-state (grep-state grep-output)
            (reduce-once pipe-state :alt-right)
          (is-input-state grep-state
                          :buffer "git status | grep"
                          :cursor-pos 17
                          :suggestion " modified")
          (expect :suggest-update :to-be grep-output)))))

  (it "input-state-alt-right-at-eol-accepts-redirection-operator-before-target"
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
        (expect :suggest-update :to-be redirect-output)
        (with-reduced-input-state (target-state target-output)
            (reduce-once redirect-state :alt-right)
          (is-input-state target-state
                          :buffer "echo hi > out.txt"
                          :cursor-pos 17
                          :suggestion nil)
          (expect :suggest-update :to-be target-output)))))

  (it "input-state-alt-right-at-eol-accepts-compact-fd-redirection"
    (with-expected-suggestion-reduction (new-state output)
        ("grep error log" 14 " 2>&1 | less" :alt-right)
        "grep error log 2>&1"
        19
        " | less"
        :suggest-update))

  (it "input-state-alt-right-at-eol-accepts-multi-digit-fd-redirection"
    (with-expected-suggestion-reduction (new-state output)
        ("grep error log" 14 " 2>&10 | less" :alt-right)
        "grep error log 2>&10"
        20
        " | less"
        :suggest-update))

  (it "input-state-alt-right-at-eol-accepts-closed-fd-redirection"
    (with-expected-suggestion-reduction (new-state output)
        ("grep error log" 14 " 2>&- | less" :alt-right)
        "grep error log 2>&-"
        19
        " | less"
        :suggest-update))

  (it "input-state-alt-right-at-eol-accepts-attached-redirection-target"
    (with-expected-suggestion-reduction (new-state output)
        ("echo hi" 7 " >out.txt && cat out.txt" :alt-right)
        "echo hi >out.txt"
        16
        " && cat out.txt"
        :suggest-update))
  (it "suggestion-redirection-helpers-cover-aggregate-and-invalid-targets" "Redirection acceptance keeps aggregate operators and malformed fd targets atomic." (expect 2 :to-equal (nshell.presentation::suggestion-redirection-operator-end "&>" 0)) (expect 2 :to-equal (nshell.presentation::suggestion-redirection-operator-end ">>" 0)) (expect 2 :to-equal (nshell.presentation::suggestion-compact-redirection-end "2>&x" 0)) (expect 5 :to-equal (nshell.presentation::suggestion-compact-redirection-end "2>&10" 0)))

  (it "input-state-copy-explicit-nil-clears-suggestion"
    (let* ((state (input-state
                   :buffer "git"
                   :cursor-pos 3
                   :suggestion " status"))
           (new-state (nshell.presentation::copy-input-state-with
                       state
                       :suggestion nil)))
      (is-input-state new-state :suggestion nil)))

  (it "input-state-normalize-clamps-cursor-and-keeps-other-slots"
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
        (expect "g" :to-equal (nshell.presentation:input-state-search-query normalized)))))

  (it "input-state-ctrl-g-cancels-visible-suggestion-without-editing"
    (with-expected-suggestion-reduction (new-state output)
        ("git" 2 " status" :ctrl-g)
        "git"
        2
        nil
        :redraw))

  (it "input-state-suggestion-acceptance-stays-behind-public-projections"
    "Autosuggestion acceptance should expose value objects, not raw split indexes."
    (let* ((suggestion " status --short")
           (segment (nshell.presentation::suggestion-next-acceptance-segment
                     suggestion))
           (acceptance (nshell.presentation::next-suggestion-acceptance
                        suggestion)))
      (expect (fboundp 'nshell.presentation::%make-suggestion-acceptance-segment) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%suggestion-acceptance-segment-end) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::suggestion-acceptance-segment-end) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::suggestion-next-acceptance-segment) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::make-suggestion-acceptance-segment) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::%suggestion-next-word-end) :to-be-falsy)
      (expect (nshell.presentation::%suggestion-acceptance-segment-p segment) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::suggestion-acceptance-segment-p) :to-be-falsy)
      (expect 7 :to-equal (nshell.presentation::suggestion-acceptance-segment-end segment))
      (expect (fboundp 'nshell.presentation::%make-suggestion-acceptance) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%suggestion-acceptance-accepted) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%suggestion-acceptance-remaining) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::make-suggestion-acceptance) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::suggestion-acceptance-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::suggestion-next-word-end) :to-be-falsy)
      (expect " status" :to-equal (nshell.presentation::suggestion-acceptance-accepted acceptance))
      (expect " --short" :to-equal (nshell.presentation::suggestion-acceptance-remaining acceptance))
      (expect (nshell.presentation::%suggestion-acceptance-accepted acceptance) :to-equal (nshell.presentation::suggestion-acceptance-accepted acceptance))
      (expect (nshell.presentation::%suggestion-acceptance-remaining acceptance) :to-equal (nshell.presentation::suggestion-acceptance-remaining acceptance))))

  (it "input-state-suggestion-append-edit-stays-behind-public-projections"
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
      (expect (fboundp 'nshell.presentation::%make-suggestion-append-plan) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%suggestion-append-plan-splice) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%make-suggestion-append-edit) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%suggestion-append-edit-plan) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::make-suggestion-append-plan) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-suggestion-append-edit) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::suggestion-append-edit-splice) :to-be-falsy)
      (let ((plan (nshell.presentation::suggestion-append-edit-plan edit)))
        (expect (nshell.presentation::%suggestion-append-plan-p plan) :to-be-truthy)
        (expect (fboundp 'nshell.presentation::suggestion-append-plan-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::suggestion-append-edit-p) :to-be-falsy)
        (expect (nshell.presentation::%buffer-splice-p
             (nshell.presentation::suggestion-append-plan-splice plan)) :to-be-truthy))
      (expect (fboundp 'nshell.presentation::buffer-splice-p) :to-be-falsy)
      (expect "git status" :to-equal (nshell.presentation::suggestion-append-edit-buffer
                    edit
                    (nshell.presentation:input-state-buffer state)))
      (expect 10 :to-equal (nshell.presentation::suggestion-append-edit-cursor-pos edit))
      (expect " --short" :to-equal (nshell.presentation::suggestion-append-edit-remaining edit))
      (let ((finished-edit
              (nshell.presentation::suggestion-append-edit-for-state
               state
               (nshell.presentation:input-state-suggestion state)
               "")))
        (expect (nshell.presentation::suggestion-append-edit-remaining
                   finished-edit) :to-be-null))))

  (it "input-state-suggestion-acceptance-commit-applies-state-transition"
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
      (expect (fboundp 'nshell.presentation::commit-suggestion-acceptance) :to-be-truthy)
      (is-input-state new-state
                      :buffer "git status"
                      :cursor-pos 10
                      :suggestion " --short"
                      :completion-index -1
                      :completion-base-buffer nil
                      :completion-base-cursor nil
                      :last-candidates nil)))

  (it "input-state-suggestion-accepts-contiguous-word-tokens"
    "Adjacent word-like tokens form one acceptance segment."
    (let ((first-token (nshell.domain.parsing:make-token :word "git" 0 3))
          (second-token (nshell.domain.parsing:make-token :word "status" 3 9)))
      (expect 9 :to-equal
        (nshell.presentation::suggestion-token-accept-end
         (list first-token second-token)
         first-token))))

  (it "input-state-suggestion-word-like-token-p-returns-canonical-booleans"
    (expect t :to-be (nshell.presentation::suggestion-word-like-token-p
               (nshell.domain.parsing:make-token :word "git")))
    (expect t :to-be (nshell.presentation::suggestion-word-like-token-p
               (nshell.domain.parsing:make-token :error "git")))
    (expect (nshell.presentation::suggestion-word-like-token-p
               (nshell.domain.parsing:make-token :pipe "|")) :to-be-null)))
