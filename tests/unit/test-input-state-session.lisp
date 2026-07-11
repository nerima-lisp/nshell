(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-finalize-transition-keeps-ctrl-l-session-state
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
      (is (eq state finalized))
      (is-input-state finalized
                      :buffer "git st"
                      :cursor-pos 6
                      :completion-index 2
                      :completion-base-buffer "git st"
                      :completion-base-cursor 6
                      :last-candidates '("status" "stash")
                      :suggestion "status")
      (is (= 1 (nshell.presentation::input-state-last-yank-start finalized)))
      (is (= 2 (nshell.presentation::input-state-last-yank-end finalized)))
      (is (= 3 (nshell.presentation::input-state-last-yank-index finalized)))
      (is (= 4 (nshell.presentation:input-state-last-argument-start finalized)))
      (is (= 5 (nshell.presentation:input-state-last-argument-end finalized)))
      (is (= 6 (nshell.presentation:input-state-last-argument-index finalized))))))

(test input-state-session-transition-policy-classifies-control-l
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
    (is (nshell.presentation::%input-session-transition-policy-p policy))
    (is (nshell.presentation::input-session-transition-policy-preserve-all-p policy))
    (is (nshell.presentation::input-session-transition-policy-preserve-completion-p policy))
    (is (not (nshell.presentation::input-session-transition-policy-preserve-yank-session-p policy)))
    (is (not (nshell.presentation::input-session-transition-policy-preserve-argument-session-p policy)))
    (is (not (fboundp 'nshell.presentation::input-session-transition-policy-p)))
    (is (not (fboundp 'nshell.presentation::make-input-session-transition-policy)))))

(test input-state-session-reduction-is-private-value
  (let* ((state (input-state :buffer "ab" :cursor-pos 2))
         (reduction (nshell.presentation::input-session-reduction-for-key-event
                     state
                     (input-key-event :char #\c))))
    (is (nshell.presentation::%input-session-reduction-p reduction))
    (is (not (listp reduction)))
    (is (not (fboundp 'nshell.presentation::input-session-reduction-p)))
    (is (not (fboundp 'nshell.presentation::make-input-session-reduction)))
    (is (eq :suggest-update
            (nshell.presentation::input-session-reduction-output reduction)))
    (is-input-state (nshell.presentation::input-session-reduction-state reduction)
                    :buffer "abc"
                    :cursor-pos 3)))

(test input-state-yank-session-clear-is-private-value
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
    (is (nshell.presentation::%transient-session-clear-p clear))
    (is (eq :yank
            (nshell.presentation::%transient-session-clear-kind clear)))
    (is (not (listp clear)))
    (is (not (fboundp 'nshell.presentation::make-transient-session-clear)))
    (is-input-state cleared
                    :buffer "git st"
                    :cursor-pos 6
                    :last-argument-start 4
                    :last-argument-end 5
                    :last-argument-index 6)
    (is (null (nshell.presentation::input-state-last-yank-start cleared)))
    (is (null (nshell.presentation::input-state-last-yank-end cleared)))
    (is (null (nshell.presentation::input-state-last-yank-index cleared)))))

(test input-state-argument-session-clear-is-private-value
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
    (is (nshell.presentation::%transient-session-clear-p clear))
    (is (eq :argument
            (nshell.presentation::%transient-session-clear-kind clear)))
    (is (not (listp clear)))
    (is (not (fboundp 'nshell.presentation::make-transient-session-clear)))
    (is-input-state cleared
                    :buffer "git st"
                    :cursor-pos 6)
    (is (= 1 (nshell.presentation::input-state-last-yank-start cleared)))
    (is (= 2 (nshell.presentation::input-state-last-yank-end cleared)))
    (is (= 3 (nshell.presentation::input-state-last-yank-index cleared)))
    (is (null (nshell.presentation:input-state-last-argument-start cleared)))
    (is (null (nshell.presentation:input-state-last-argument-end cleared)))
    (is (null (nshell.presentation:input-state-last-argument-index cleared)))))

(test input-state-transient-session-clear-rejects-wrong-kind
  (signals error
    (nshell.presentation::apply-yank-session-clear
     (input-state)
     (nshell.presentation::argument-session-clear)))
  (signals error
    (nshell.presentation::apply-argument-session-clear
     (input-state)
     (nshell.presentation::yank-session-clear))))

(test input-state-finalize-transition-clears-transient-session-state-on-edit
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
      (is (null (nshell.presentation::input-state-last-yank-start finalized)))
      (is (null (nshell.presentation::input-state-last-yank-end finalized)))
      (is (null (nshell.presentation::input-state-last-yank-index finalized)))
      (is (null (nshell.presentation:input-state-last-argument-start finalized)))
      (is (null (nshell.presentation:input-state-last-argument-end finalized)))
      (is (null (nshell.presentation:input-state-last-argument-index finalized))))))

(test input-state-finalize-transition-preserves-yank-session-on-yank-cycle
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
      (is (= 1 (nshell.presentation::input-state-last-yank-start finalized)))
      (is (= 2 (nshell.presentation::input-state-last-yank-end finalized)))
      (is (= 3 (nshell.presentation::input-state-last-yank-index finalized)))
      (is (null (nshell.presentation:input-state-last-argument-start finalized)))
      (is (null (nshell.presentation:input-state-last-argument-end finalized)))
      (is (null (nshell.presentation:input-state-last-argument-index finalized))))))

(test input-state-finalize-transition-preserves-argument-session-on-last-argument-repeat
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
      (is (null (nshell.presentation::input-state-last-yank-start finalized)))
      (is (null (nshell.presentation::input-state-last-yank-end finalized)))
      (is (null (nshell.presentation::input-state-last-yank-index finalized)))
      (is (= 4 (nshell.presentation:input-state-last-argument-start finalized)))
      (is (= 5 (nshell.presentation:input-state-last-argument-end finalized)))
      (is (= 6 (nshell.presentation:input-state-last-argument-index finalized))))))

(test input-state-finalize-transition-preserves-completion-session-on-tab
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
      (is (null (nshell.presentation::input-state-last-yank-start finalized)))
      (is (null (nshell.presentation::input-state-last-yank-end finalized)))
      (is (null (nshell.presentation::input-state-last-yank-index finalized)))
      (is (null (nshell.presentation:input-state-last-argument-start finalized)))
      (is (null (nshell.presentation:input-state-last-argument-end finalized)))
      (is (null (nshell.presentation:input-state-last-argument-index finalized))))))

(test input-state-finalize-transition-preserves-suggestion-driven-completion-session
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
      (is (null (nshell.presentation::input-state-last-yank-start finalized)))
      (is (null (nshell.presentation::input-state-last-yank-end finalized)))
      (is (null (nshell.presentation::input-state-last-yank-index finalized)))
      (is (null (nshell.presentation:input-state-last-argument-start finalized)))
      (is (null (nshell.presentation:input-state-last-argument-end finalized)))
      (is (null (nshell.presentation:input-state-last-argument-index finalized))))))
