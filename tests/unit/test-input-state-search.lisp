(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-ctrl-r-enters-search-mode
  (with-reduced-input-state (new-state output)
      (reduce-once (input-state :buffer "abc" :cursor-pos 3)
                   :ctrl-r)
    (is-search-state new-state
                     :mode :search
                     :query ""
                     :original-buffer "abc"
                     :index 0)
    (is (eq :search-start output))))

(test input-state-ctrl-s-enters-search-mode
  (with-reduced-input-state (new-state output)
      (reduce-once (input-state :buffer "abc" :cursor-pos 3)
                   :ctrl-s)
    (is-search-state new-state
                     :mode :search
                     :query ""
                     :original-buffer "abc"
                     :index 0)
    (is (eq :search-start output))))

(test input-state-ctrl-r-clears-completion-session
  (let ((state (input-state
                :buffer "g"
                :cursor-pos 1
                :completion-index 0
                :completion-base-buffer "g"
                :completion-base-cursor 1
                :last-candidates '("git" "grep"))))
    (with-reduced-input-state (new-state output) (reduce-once state :ctrl-r)
      (is-search-state-with-completion-cleared new-state
                                               :mode :search)
      (is (eq :search-start output)))))

(test input-state-history-search-state-preserves-zero-completion-metadata
  (let ((state (history-search-state
                :buffer "g"
                :query "g"
                :original-buffer "g"
                :index 0
                :completion-index 0
                :completion-base-buffer ""
                :completion-base-cursor 0
                :last-candidates '("git"))))
    (is-search-state state
                     :mode :search
                     :query "g"
                     :original-buffer "g"
                     :index 0)
    (is-input-state state
                    :completion-index 0
                    :completion-base-buffer ""
                    :completion-base-cursor 0
                    :last-candidates '("git"))))

(test input-state-history-search-input-clears-stale-completion-session
  (let ((state (history-search-state
                :buffer "git"
                :query ""
                :original-buffer "git"
                :completion-index 0
                :completion-base-buffer "g"
                :completion-base-cursor 1
                :last-candidates '("git" "grep"))))
    (with-reduced-input-state (new-state output) (reduce-once state :char #\s)
      (is-search-state-with-completion-cleared new-state
                                               :mode :search
                                               :query "s"
                                               :original-buffer "git"
                                               :index 0)
      (is (eq :search-update output)))))

(test input-state-history-search-edits-query-not-buffer
  (with-reduced-input-state (search-state)
      (reduce-once (input-state :buffer "git" :cursor-pos 3)
                   :ctrl-r)
    (with-reduced-input-state (s-state s-output)
        (reduce-once search-state :char #\s)
      (is (string= "git" (nshell.presentation:input-state-buffer s-state)))
      (is-search-state s-state :mode :search :query "s")
      (is (eq :search-update s-output))
      (with-reduced-input-state (t-state)
          (reduce-once s-state :char #\t)
        (is (string= "st"
                     (nshell.presentation:input-state-search-query t-state)))
        (with-reduced-input-state (back-state back-output)
            (reduce-once t-state :backspace)
          (is (string= "s"
                       (nshell.presentation:input-state-search-query back-state)))
          (is (eq :search-update back-output)))))))

(test input-state-history-search-paste-edits-query-not-buffer
  (let ((state (history-search-state
                :buffer "git"
                :query "st"
                :original-buffer "git"
                :index 2
                :completion-index 0
                :completion-base-buffer "g"
                :completion-base-cursor 1
                :last-candidates '("git" "grep")
                :suggestion " ignored")))
    (with-reduced-input-state (new-state output)
        (reduce-once state :paste nil nil
                     '(:protocol :bracketed :text "atus --short"))
      (is-search-state-with-completion-cleared new-state
                                               :mode :search
                                               :query "status --short"
                                               :original-buffer "git"
                                               :index 0)
      (is (string= "git" (nshell.presentation:input-state-buffer new-state)))
      (is (eq :search-update output)))))

(test input-state-history-search-cycles-and-applies-results
  (let* ((state (history-search-state
                 :query "git"
                 :original-buffer "g"
                 :index 1
                 :completion-index 0
                 :completion-base-buffer "gi"
                 :completion-base-cursor 2
                 :last-candidates '("git" "grep")))
         (matches '("git status" "git log"))
         (applied
           (nshell.presentation:apply-history-search-results-to-input-state
            state matches)))
    (is (string= "git log" (nshell.presentation:input-state-buffer applied)))
    (is (= 7 (nshell.presentation:input-state-cursor-pos applied)))
    (is-completion-session-cleared applied)
    (with-reduced-input-state (older older-output) (reduce-once applied :ctrl-r)
      (is (= 2 (nshell.presentation:input-state-search-index older)))
      (is (eq :search-update older-output))
      (let ((wrapped
              (nshell.presentation:apply-history-search-results-to-input-state
               older matches)))
        (is (string= "git status"
                     (nshell.presentation:input-state-buffer wrapped)))))
    (with-reduced-input-state (older older-output) (reduce-once applied :ctrl-p)
      (is (= 2 (nshell.presentation:input-state-search-index older)))
      (is (eq :search-update older-output)))
    (with-reduced-input-state (newer newer-output) (reduce-once applied :ctrl-n)
      (is (= 0 (nshell.presentation:input-state-search-index newer)))
      (is (eq :search-update newer-output)))))

(test input-state-history-search-ignores-non-string-results
  (let ((state (history-search-state
                :query "git"
                :original-buffer "g"
                :index 1)))
    (let ((applied
            (nshell.presentation:apply-history-search-results-to-input-state
             state '(42 "git status" :ignored "git log"))))
      (is (string= "git log" (nshell.presentation:input-state-buffer applied)))
      (is (= 7 (nshell.presentation:input-state-cursor-pos applied)))
      (is-search-state applied
                       :mode :search
                       :query "git"
                       :original-buffer "g"
                       :index 1))))

(test input-state-history-search-leaves-non-search-state-unchanged
  (let ((state (input-state :buffer "git" :cursor-pos 3)))
    (let ((applied
            (nshell.presentation:apply-history-search-results-to-input-state
             state '("git status" "git log"))))
      (is (equalp state applied))
      (is (string= "git" (nshell.presentation:input-state-buffer applied)))
      (is (= 3 (nshell.presentation:input-state-cursor-pos applied))))))

(test input-state-history-search-ctrl-s-moves-to-newer-result
  (let ((state (history-search-state
                :buffer "git status"
                :query "git"
                :original-buffer "g"
                :index 2)))
    (with-reduced-input-state (newer output) (reduce-once state :ctrl-s)
      (is (= 1 (nshell.presentation:input-state-search-index newer)))
      (is (eq :search-update output)))))

(test input-state-history-search-empty-results-restore-original-cursor
  (let ((state (history-search-state
                :buffer "git status"
                :query "nomatch"
                :original-buffer "git status"
                :original-cursor 4
                :index 2)))
    (let ((restored
            (nshell.presentation:apply-history-search-results-to-input-state
             state '())))
      (is (string= "git status" (nshell.presentation:input-state-buffer restored)))
      (is (= 4 (nshell.presentation:input-state-cursor-pos restored)))
      (is-search-state restored
                       :mode :search
                       :query "nomatch"
                       :original-buffer "git status"
                       :original-cursor 4
                       :index 2))))
