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
