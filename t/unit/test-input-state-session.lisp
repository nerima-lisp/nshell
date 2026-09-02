(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-finalize-transition-keeps-ctrl-l-session-state"
    (let ((state (input-state
                  :buffer "git st"
                  :cursor-pos 6
                  :completion-index 2
                  :completion-base-buffer "git st"
                  :completion-base-cursor 6
                  :last-candidates '("status" "stash")
                  :suggestion "status"
                  :last-yank-start 1
                  :last-yank-end 2
                  :last-yank-index 3
                  :last-argument-start 4
                  :last-argument-end 5
                  :last-argument-index 6)))
      (let ((finalized (nshell.presentation::finalize-input-state-transition
                        state
                        state
                        (input-key-event :ctrl-l))))
        (expect state :to-be finalized)
        (is-input-state finalized
                        :buffer "git st"
                        :cursor-pos 6
                        :completion-index 2
                        :completion-base-buffer "git st"
                        :completion-base-cursor 6
                        :last-candidates '("status" "stash")
                        :suggestion "status")
        (expect 1 :to-equal (nshell.presentation::input-state-last-yank-start finalized))
        (expect 2 :to-equal (nshell.presentation::input-state-last-yank-end finalized))
        (expect 3 :to-equal (nshell.presentation::input-state-last-yank-index finalized))
        (expect 4 :to-equal (nshell.presentation:input-state-last-argument-start finalized))
        (expect 5 :to-equal (nshell.presentation:input-state-last-argument-end finalized))
        (expect 6 :to-equal (nshell.presentation:input-state-last-argument-index finalized)))))

  (it "input-state-session-transition-policy-classifies-control-l"
    (let* ((state (input-state
                   :buffer "git st"
                   :cursor-pos 6
                   :completion-index 2
                   :completion-base-buffer "git st"
                   :completion-base-cursor 6
                   :last-candidates '("status" "stash")))
           (policy (nshell.presentation::input-session-transition-policy-for-key-event
                    state
                    state
                    (input-key-event :ctrl-l))))
      (expect (nshell.presentation::%input-session-transition-policy-p policy) :to-be-truthy)
      (expect (nshell.presentation::input-session-transition-policy-preserve-all-p policy) :to-be-truthy)
      (expect (nshell.presentation::input-session-transition-policy-preserve-completion-p policy) :to-be-truthy)
      (expect (nshell.presentation::input-session-transition-policy-preserve-yank-session-p policy) :to-be-falsy)
      (expect (nshell.presentation::input-session-transition-policy-preserve-argument-session-p policy) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::input-session-transition-policy-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-input-session-transition-policy) :to-be-falsy)))

  (it "input-state-session-reduction-is-private-value"
    (let* ((state (input-state :buffer "ab" :cursor-pos 2))
           (reduction (nshell.presentation::input-session-reduction-for-key-event
                       state
                       (input-key-event :char #\c))))
      (expect (nshell.presentation::%input-session-reduction-p reduction) :to-be-truthy)
      (expect (listp reduction) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::input-session-reduction-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-input-session-reduction) :to-be-falsy)
      (expect :suggest-update :to-be (nshell.presentation::input-session-reduction-output reduction))
      (is-input-state (nshell.presentation::input-session-reduction-state reduction)
                      :buffer "abc"
                      :cursor-pos 3)))

  (it "input-state-session-reduction-preserves-state-and-output"
    (let* ((state (input-state :buffer "ready" :cursor-pos 5))
           (reduction (nshell.presentation::input-session-reduction state :redraw)))
      (expect state :to-be (nshell.presentation::input-session-reduction-state reduction))
      (expect :redraw :to-be (nshell.presentation::input-session-reduction-output reduction))))

  (it "input-state-yank-session-clear-is-private-value"
    (let* ((state (input-state
                   :buffer "git st"
                   :cursor-pos 6
                   :last-yank-start 1
                   :last-yank-end 2
                   :last-yank-index 3
                   :last-argument-start 4
                   :last-argument-end 5
                   :last-argument-index 6))
           (clear (nshell.presentation::yank-session-clear))
           (cleared (nshell.presentation::apply-yank-session-clear state clear)))
      (expect (nshell.presentation::%transient-session-clear-p clear) :to-be-truthy)
      (expect :yank :to-be (nshell.presentation::%transient-session-clear-kind clear))
      (expect (listp clear) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-transient-session-clear) :to-be-falsy)
      (is-input-state cleared
                      :buffer "git st"
                      :cursor-pos 6
                      :last-argument-start 4
                      :last-argument-end 5
                      :last-argument-index 6)
      (expect (nshell.presentation::input-state-last-yank-start cleared) :to-be-null)
      (expect (nshell.presentation::input-state-last-yank-end cleared) :to-be-null)
      (expect (nshell.presentation::input-state-last-yank-index cleared) :to-be-null)))

  (it "input-state-argument-session-clear-is-private-value"
    (let* ((state (input-state
                   :buffer "git st"
                   :cursor-pos 6
                   :last-yank-start 1
                   :last-yank-end 2
                   :last-yank-index 3
                   :last-argument-start 4
                   :last-argument-end 5
                   :last-argument-index 6))
           (clear (nshell.presentation::argument-session-clear))
           (cleared (nshell.presentation::apply-argument-session-clear state clear)))
      (expect (nshell.presentation::%transient-session-clear-p clear) :to-be-truthy)
      (expect :argument :to-be (nshell.presentation::%transient-session-clear-kind clear))
      (expect (listp clear) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-transient-session-clear) :to-be-falsy)
      (is-input-state cleared
                      :buffer "git st"
                      :cursor-pos 6)
      (expect 1 :to-equal (nshell.presentation::input-state-last-yank-start cleared))
      (expect 2 :to-equal (nshell.presentation::input-state-last-yank-end cleared))
      (expect 3 :to-equal (nshell.presentation::input-state-last-yank-index cleared))
      (expect (nshell.presentation:input-state-last-argument-start cleared) :to-be-null)
      (expect (nshell.presentation:input-state-last-argument-end cleared) :to-be-null)
      (expect (nshell.presentation:input-state-last-argument-index cleared) :to-be-null)))

  (it "input-state-transient-session-clear-rejects-wrong-kind"
    (expect (lambda () (nshell.presentation::apply-yank-session-clear
       (input-state)
       (nshell.presentation::argument-session-clear))) :to-throw 'error)
    (expect (lambda () (nshell.presentation::apply-argument-session-clear
       (input-state)
       (nshell.presentation::yank-session-clear))) :to-throw 'error))

  (it "input-state-finalize-transition-clears-transient-session-state-on-edit"
    (let ((state (input-state
                  :buffer "git st"
                  :cursor-pos 6
                  :completion-index 2
                  :completion-base-buffer "git st"
                  :completion-base-cursor 6
                  :last-candidates '("status" "stash")
                  :last-yank-start 1
                  :last-yank-end 2
                  :last-yank-index 3
                  :last-argument-start 4
                  :last-argument-end 5
                  :last-argument-index 6)))
      (let ((finalized (nshell.presentation::finalize-input-state-transition
                        state
                        state
                        (input-key-event :char #\x))))
        (is-input-state-with-completion-cleared finalized
                                                :buffer "git st"
                                                :cursor-pos 6)
        (expect (nshell.presentation::input-state-last-yank-start finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-end finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-index finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-start finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-end finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-index finalized) :to-be-null))))

  (it "input-state-finalize-transition-preserves-yank-session-on-yank-cycle"
    (let ((state (input-state
                  :buffer "git st"
                  :cursor-pos 6
                  :completion-index 2
                  :completion-base-buffer "git st"
                  :completion-base-cursor 6
                  :last-candidates '("status" "stash")
                  :last-yank-start 1
                  :last-yank-end 2
                  :last-yank-index 3
                  :last-argument-start 4
                  :last-argument-end 5
                  :last-argument-index 6)))
      (let ((finalized (nshell.presentation::finalize-input-state-transition
                        state
                        state
                        (input-key-event :alt-y))))
        (is-input-state-with-completion-cleared finalized
                                                :buffer "git st"
                                                :cursor-pos 6)
        (expect 1 :to-equal (nshell.presentation::input-state-last-yank-start finalized))
        (expect 2 :to-equal (nshell.presentation::input-state-last-yank-end finalized))
        (expect 3 :to-equal (nshell.presentation::input-state-last-yank-index finalized))
        (expect (nshell.presentation:input-state-last-argument-start finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-end finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-index finalized) :to-be-null))))

  (it "input-state-finalize-transition-preserves-argument-session-on-last-argument-repeat"
    (let ((state (input-state
                  :buffer "git st"
                  :cursor-pos 6
                  :completion-index 2
                  :completion-base-buffer "git st"
                  :completion-base-cursor 6
                  :last-candidates '("status" "stash")
                  :last-yank-start 1
                  :last-yank-end 2
                  :last-yank-index 3
                  :last-argument-start 4
                  :last-argument-end 5
                  :last-argument-index 6)))
      (let ((finalized (nshell.presentation::finalize-input-state-transition
                        state
                        state
                        (input-key-event :alt-dot))))
        (is-input-state-with-completion-cleared finalized
                                                :buffer "git st"
                                                :cursor-pos 6)
        (expect (nshell.presentation::input-state-last-yank-start finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-end finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-index finalized) :to-be-null)
        (expect 4 :to-equal (nshell.presentation:input-state-last-argument-start finalized))
        (expect 5 :to-equal (nshell.presentation:input-state-last-argument-end finalized))
        (expect 6 :to-equal (nshell.presentation:input-state-last-argument-index finalized)))))

  (it "input-state-finalize-transition-preserves-completion-session-on-tab"
    (let ((state (input-state
                  :buffer "git st"
                  :cursor-pos 6
                  :completion-index 2
                  :completion-base-buffer "git st"
                  :completion-base-cursor 6
                  :last-candidates '("status" "stash")
                  :last-yank-start 1
                  :last-yank-end 2
                  :last-yank-index 3
                  :last-argument-start 4
                  :last-argument-end 5
                  :last-argument-index 6)))
      (let ((finalized (nshell.presentation::finalize-input-state-transition
                        state
                        state
                        (input-key-event :tab))))
        (is-input-state finalized
                        :buffer "git st"
                        :cursor-pos 6
                        :completion-index 2
                        :completion-base-buffer "git st"
                        :completion-base-cursor 6
                        :last-candidates '("status" "stash"))
        (expect (nshell.presentation::input-state-last-yank-start finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-end finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-index finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-start finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-end finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-index finalized) :to-be-null))))

  (it "input-state-finalize-transition-preserves-suggestion-driven-completion-session"
    (let ((state (input-state
                  :buffer "git st"
                  :cursor-pos 6
                  :completion-index 2
                  :completion-base-buffer "git st"
                  :completion-base-cursor 6
                  :last-candidates '("status" "stash")
                  :suggestion "status"
                  :last-yank-start 1
                  :last-yank-end 2
                  :last-yank-index 3
                  :last-argument-start 4
                  :last-argument-end 5
                  :last-argument-index 6)))
      (let ((finalized (nshell.presentation::finalize-input-state-transition
                        state
                        state
                        (input-key-event :char #\x))))
        (is-input-state finalized
                        :buffer "git st"
                        :cursor-pos 6
                        :completion-index 2
                        :completion-base-buffer "git st"
                        :completion-base-cursor 6
                        :last-candidates '("status" "stash")
                        :suggestion "status")
        (expect (nshell.presentation::input-state-last-yank-start finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-end finalized) :to-be-null)
        (expect (nshell.presentation::input-state-last-yank-index finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-start finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-end finalized) :to-be-null)
        (expect (nshell.presentation:input-state-last-argument-index finalized) :to-be-null)))))
