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
                        "%COPY-INPUT-STATE-SESSION-PLIST"
                        "%COPY-INPUT-STATE-OR-CURRENT"
                        "%COPY-INPUT-STATE-CLEARABLE-OR-CURRENT"
                        "%COPY-INPUT-STATE-CLEARABLE-VALUE-OR-CURRENT"
                        "%COPY-INPUT-STATE-CLAMPED-ANCHOR-OR-CURRENT"
                        "INPUT-STATE-COPY-OVERRIDE"))
      (is (not (present-p old-name))))
    (dolist (new-name '("%COPY-INPUT-STATE-COMPLETION-VALUES"
                        "%COPY-INPUT-STATE-TRANSIENT-VALUES"
                        "%COPY-INPUT-STATE-SESSION-VALUES"
                        "%COPY-INPUT-STATE-COMPLETION-INITARGS"
                        "%COPY-INPUT-STATE-TRANSIENT-INITARGS"
                        "%COPY-INPUT-STATE-SESSION-INITARGS"
                        "%INPUT-STATE-COPY-OVERRIDE"
                        "%MAKE-INPUT-STATE-COPY-OVERRIDE"
                        "INPUT-STATE-COPY-OVERRIDE-KIND"
                        "INPUT-STATE-COPY-OVERRIDE-VALUE"
                        "INPUT-STATE-COPY-OVERRIDE-FOR"
                        "INPUT-STATE-COPY-OPTIONAL-VALUE-OVERRIDE"
                        "INPUT-STATE-COPY-OVERRIDE-RESOLVE"
                        "INPUT-STATE-COPY-ANCHOR-OVERRIDE-RESOLVE"
                        "%INPUT-STATE-COPY-SPEC"
                        "%INPUT-STATE-COMPLETION-COPY"
                        "%INPUT-STATE-TRANSIENT-COPY"
                        "%INPUT-STATE-SESSION-COPY"))
      (is (present-p new-name)))))

(test input-state-copy-override-values-resolve-copy-decisions
  (let ((current (nshell.presentation::input-state-copy-override-for nil "ignored"))
        (clear (nshell.presentation::input-state-copy-override-for t :clear))
        (value (nshell.presentation::input-state-copy-override-for t "new"))
        (optional-current
          (nshell.presentation::input-state-copy-optional-value-override nil)))
    (is (nshell.presentation::%input-state-copy-override-p current))
    (is (not (fboundp 'nshell.presentation::input-state-copy-override-p)))
    (is (eq :current
            (nshell.presentation::input-state-copy-override-kind current)))
    (is (eq :clear
            (nshell.presentation::input-state-copy-override-kind clear)))
    (is (eq :value
            (nshell.presentation::input-state-copy-override-kind value)))
    (is (string= "old"
                 (nshell.presentation::input-state-copy-override-resolve
                  current
                  "old")))
    (is (null (nshell.presentation::input-state-copy-override-resolve
               clear
               "old")))
    (is (string= "new"
                 (nshell.presentation::input-state-copy-override-resolve
                  value
                  "old"
                  :acceptp #'stringp)))
    (is (string= "old"
                 (nshell.presentation::input-state-copy-override-resolve
                  value
                  "old"
                  :acceptp #'integerp)))
    (is (string= "old"
                 (nshell.presentation::input-state-copy-override-resolve
                  optional-current
                  "old")))
    (is (= 3
           (nshell.presentation::input-state-copy-anchor-override-resolve
            (nshell.presentation::input-state-copy-override-for t 99)
            0
            "abc")))))

(test input-state-copy-initargs-assemble-group-values
  (let* ((completion
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
            :redo-stack '(:redo)))
         (spec
           (nshell.presentation::%make-input-state-copy-spec
            :buffer "text"
            :cursor-pos 2
            :completion completion
            :transient transient
            :session session)))
    (is (nshell.presentation::%input-state-copy-spec-p spec))
    (is (not (listp spec)))
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
                spec)))))

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

(test input-undo-stack-step-is-private-value
  (let* ((base (nshell.presentation:make-input-state :buffer "ab"
                                                     :cursor-pos 2))
         (previous-state (nshell.presentation:make-input-state :buffer "a"
                                                               :cursor-pos 1))
         (next-state (nshell.presentation:make-input-state :buffer "abc"
                                                           :cursor-pos 3))
         (previous (nshell.presentation::input-edit-snapshot previous-state))
         (next (nshell.presentation::input-edit-snapshot next-state))
         (undo-state (nshell.presentation::copy-input-state-with
                      base
                      :undo-stack (list previous)
                      :redo-stack nil))
         (redo-state (nshell.presentation::copy-input-state-with
                      base
                      :undo-stack nil
                      :redo-stack (list next)))
         (undo-step (nshell.presentation::undo-stack-step-for-direction
                     undo-state
                     :undo))
         (redo-step (nshell.presentation::undo-stack-step-for-direction
                     redo-state
                     :redo)))
    (is (nshell.presentation::%undo-stack-step-p undo-step))
    (is (not (listp undo-step)))
    (is (eq previous
            (nshell.presentation::%undo-stack-step-snapshot undo-step)))
    (is (null (nshell.presentation::%undo-stack-step-undo-stack undo-step)))
    (is (= 1
           (length (nshell.presentation::%undo-stack-step-redo-stack
                    undo-step))))
    (is (nshell.presentation::%input-edit-snapshot-p
         (first (nshell.presentation::%undo-stack-step-redo-stack
                 undo-step))))
    (is (nshell.presentation::%undo-stack-step-p redo-step))
    (is (not (listp redo-step)))
    (is (eq next
            (nshell.presentation::%undo-stack-step-snapshot redo-step)))
    (is (= 1
           (length (nshell.presentation::%undo-stack-step-undo-stack
                    redo-step))))
    (is (null (nshell.presentation::%undo-stack-step-redo-stack redo-step)))
    (is (not (fboundp 'nshell.presentation::make-undo-stack-step)))))

(test input-undo-recording-step-is-private-value
  (let* ((old-state (nshell.presentation:make-input-state :buffer "ab"
                                                          :cursor-pos 2))
         (new-state (nshell.presentation:make-input-state :buffer "abc"
                                                          :cursor-pos 3))
         (existing-state (nshell.presentation:make-input-state :buffer "a"
                                                               :cursor-pos 1))
         (redo-state (nshell.presentation:make-input-state :buffer "abcd"
                                                           :cursor-pos 4))
         (existing (nshell.presentation::input-edit-snapshot existing-state))
         (redo (nshell.presentation::input-edit-snapshot redo-state))
         (new-state-with-history
           (nshell.presentation::copy-input-state-with
            new-state
            :undo-stack (list existing)
            :redo-stack (list redo)))
         (recorded-transition
           (nshell.presentation::undo-recording-transition
            old-state
            new-state-with-history
            :suggest-update
            (input-key-event :char #\c)))
         (ignored-transition
           (nshell.presentation::undo-recording-transition
            old-state
            new-state-with-history
            :suggest-update
            (input-key-event :ctrl-underscore)))
         (step (nshell.presentation::undo-recording-step-for-transition
                recorded-transition))
         (recorded (nshell.presentation::apply-undo-recording-step
                     new-state-with-history
                     step))
         (ignored (nshell.presentation::undo-recording-step-for-transition
                   ignored-transition)))
    (is (nshell.presentation::%undo-recording-transition-p
         recorded-transition))
    (is (not (listp recorded-transition)))
    (is (nshell.presentation::%undo-recording-step-p step))
    (is (not (listp step)))
    (is (= 2
           (length (nshell.presentation::%undo-recording-step-undo-stack
                    step))))
    (is (string= "ab"
                 (nshell.presentation::%input-edit-snapshot-buffer
                  (first (nshell.presentation::%undo-recording-step-undo-stack
                          step)))))
    (is (eq existing
            (second (nshell.presentation::%undo-recording-step-undo-stack
                     step))))
    (is (null (nshell.presentation::%undo-recording-step-redo-stack step)))
    (is (= 2
           (length (nshell.presentation::input-state-undo-stack recorded))))
    (is (null (nshell.presentation::input-state-redo-stack recorded)))
    (is (null ignored))
    (is (not (fboundp 'nshell.presentation::make-undo-recording-transition)))
    (is (not (fboundp 'nshell.presentation::make-undo-recording-step)))))
