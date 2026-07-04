(in-package #:nshell/test)

(def-suite input-state-tests
  :description "Pure REPL input-state reducer tests"
  :in nshell-tests)

(in-suite input-state-tests)

(test input-state-raw-constructor-is-internal-boundary
  (let ((state (nshell.presentation:make-input-state :buffer "abc" :cursor-pos 2)))
    (is (nshell.presentation:input-state-p state))
    (is (string= "abc" (nshell.presentation:input-state-buffer state)))
    (is (= 2 (nshell.presentation:input-state-cursor-pos state)))
    (is (eq :insert (nshell.presentation:input-state-mode state)))
    (is (fboundp 'nshell.presentation::%make-input-state))))

(test input-state-copy-groups-use-private-values-before-initargs
  (flet ((present-p (name)
           (multiple-value-bind (symbol status)
               (find-symbol name '#:nshell.presentation)
             (and status symbol (or (fboundp symbol)
                                    (find-class symbol nil))))))
    (dolist (old-name '("%COPY-INPUT-STATE-COMPLETION-PLIST"
                        "%COPY-INPUT-STATE-TRANSIENT-PLIST"
                        "%COPY-INPUT-STATE-SESSION-PLIST"))
      (is (not (present-p old-name))))
    (dolist (new-name '("%COPY-INPUT-STATE-COMPLETION-VALUES"
                        "%COPY-INPUT-STATE-TRANSIENT-VALUES"
                        "%COPY-INPUT-STATE-SESSION-VALUES"
                        "%COPY-INPUT-STATE-COMPLETION-INITARGS"
                        "%COPY-INPUT-STATE-TRANSIENT-INITARGS"
                        "%COPY-INPUT-STATE-SESSION-INITARGS"
                        "%INPUT-STATE-COMPLETION-COPY"
                        "%INPUT-STATE-TRANSIENT-COPY"
                        "%INPUT-STATE-SESSION-COPY"))
      (is (present-p new-name)))))

(test input-state-copy-initargs-assemble-group-values
  (let ((completion
          (nshell.presentation::%make-input-state-completion-copy
           :completion-index 3
           :completion-base-buffer "base"
           :completion-base-cursor 4
           :last-candidates '("one" "two")
           :suggestion "suggest"))
        (transient
          (nshell.presentation::%make-input-state-transient-copy
           :mode :vi-c
           :vi-count 9
           :vi-visual-anchor 7
           :abbreviation-expander 'expand
           :kill-ring '("kill")
           :last-yank-start 1
           :last-yank-end 2
           :last-yank-index 3
           :last-argument-start 4
           :last-argument-end 5
           :last-argument-index 6))
        (session
          (nshell.presentation::%make-input-state-session-copy
           :search-query "query"
           :search-original-buffer "original"
           :search-original-cursor 8
           :search-index 11
           :undo-stack '(:undo)
           :redo-stack '(:redo))))
    (is (equal '(:buffer "text"
                 :cursor-pos 2
                 :completion-index 3
                 :completion-base-buffer "base"
                 :completion-base-cursor 4
                 :last-candidates ("one" "two")
                 :suggestion "suggest"
                 :mode :vi-c
                 :vi-count 9
                 :vi-visual-anchor 7
                 :abbreviation-expander expand
                 :kill-ring ("kill")
                 :last-yank-start 1
                 :last-yank-end 2
                 :last-yank-index 3
                 :last-argument-start 4
                 :last-argument-end 5
                 :last-argument-index 6
                 :search-query "query"
                 :search-original-buffer "original"
                 :search-original-cursor 8
                 :search-index 11
                 :undo-stack (:undo)
                :redo-stack (:redo))
               (nshell.presentation::%copy-input-state-initargs
                "text"
                2
                completion
                transient
                session)))))

(test input-state-copy-with-preserves-and-clears-optional-fields
  (let ((state (input-state
                :buffer "abc"
                :cursor-pos 1
                :completion-index 2
                :completion-base-buffer "base"
                :completion-base-cursor 2
                :last-candidates '("one" "two")
                :suggestion "hint"
                :mode :search
                :vi-visual-anchor 3
                :kill-ring '("kill")
                :search-query "query"
                :search-original-buffer "origin"
                :search-original-cursor 4
                :search-index 9)))
    (let ((preserved (nshell.presentation::copy-input-state-with
                      state
                      :search-index 10))
          (cleared (nshell.presentation::copy-input-state-with
                    state
                    :completion-base-buffer :clear
                    :completion-base-cursor :clear
                    :last-candidates :clear
                    :suggestion :clear
                    :vi-visual-anchor :clear
                    :kill-ring :clear
                    :search-query :clear
                    :search-original-buffer :clear
                    :search-original-cursor :clear)))
      (is-input-state preserved
                      :buffer "abc"
                      :cursor-pos 1
                      :completion-index 2
                      :completion-base-buffer "base"
                      :completion-base-cursor 2
                      :last-candidates '("one" "two")
                      :suggestion "hint"
                      :mode :search
                      :vi-visual-anchor 3
                      :kill-ring '("kill")
                      :search-query "query"
                      :search-original-buffer "origin"
                      :search-original-cursor 4
                      :search-index 10)
      (is-input-state cleared
                      :buffer "abc"
                      :cursor-pos 1
                      :completion-index 2
                      :completion-base-buffer nil
                      :completion-base-cursor nil
                      :last-candidates nil
                      :suggestion nil
                      :mode :search
                      :vi-visual-anchor nil
                      :kill-ring nil
                      :search-query ""
                      :search-original-buffer ""
                      :search-original-cursor nil
                      :search-index 9))))

(test input-edit-snapshot-is-private-value
  (let* ((state (nshell.presentation:make-input-state :buffer "abc"
                                                      :cursor-pos 2))
         (snapshot (nshell.presentation::input-edit-snapshot state)))
    (is (nshell.presentation::%input-edit-snapshot-p snapshot))
    (is (not (listp snapshot)))
    (is (string= "abc"
                 (nshell.presentation::%input-edit-snapshot-buffer snapshot)))
    (is (= 2
           (nshell.presentation::%input-edit-snapshot-cursor-pos snapshot)))))

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
    (is (nshell.presentation::input-session-transition-policy-p policy))
    (is (nshell.presentation::input-session-transition-policy-preserve-all-p policy))
    (is (nshell.presentation::input-session-transition-policy-preserve-completion-p policy))
    (is (not (nshell.presentation::input-session-transition-policy-preserve-yank-session-p policy)))
    (is (not (nshell.presentation::input-session-transition-policy-preserve-argument-session-p policy)))
    (is (not (fboundp 'nshell.presentation::make-input-session-transition-policy)))))

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
