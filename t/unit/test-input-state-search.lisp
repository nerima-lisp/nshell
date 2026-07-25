(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-ctrl-r-enters-search-mode"
    (with-reduced-input-state (new-state output)
        (reduce-once (input-state :buffer "abc" :cursor-pos 3)
                     :ctrl-r)
      (is-search-state new-state
                       :mode :search
                       :query ""
                       :original-buffer "abc"
                       :index 0)
      (expect :search-start :to-be output)))

  (it "input-state-ctrl-s-enters-search-mode"
    (with-reduced-input-state (new-state output)
        (reduce-once (input-state :buffer "abc" :cursor-pos 3)
                     :ctrl-s)
      (is-search-state new-state
                       :mode :search
                       :query ""
                       :original-buffer "abc"
                       :index 0)
      (expect :search-start :to-be output)))

  (it "input-state-ctrl-r-clears-completion-session"
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
        (expect :search-start :to-be output))))

  (it "input-state-history-search-state-preserves-zero-completion-metadata"
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

  (it "input-history-search-session-clear-is-private-value"
    (let* ((state (input-state
                   :buffer "git"
                   :cursor-pos 2
                   :search-query "g"
                   :search-original-buffer "git"
                   :search-original-cursor 3
                   :search-index 4
                   :completion-index 0
                   :completion-base-buffer "g"
                   :completion-base-cursor 1
                   :last-candidates '("git" "grep")))
           (clear (nshell.presentation::history-search-session-clear))
           (cleared (nshell.presentation::apply-history-search-session-clear
                     state clear)))
      (expect (nshell.presentation::%input-session-clear-p clear) :to-be-truthy)
      (expect :history-search :to-be (nshell.presentation::%input-session-clear-kind clear))
      (expect (listp clear) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-input-session-clear) :to-be-falsy)
      (is-input-state cleared
                      :buffer "git"
                      :cursor-pos 2
                      :completion-index 0
                      :completion-base-buffer "g"
                      :completion-base-cursor 1
                      :last-candidates '("git" "grep"))
      (expect "" :to-equal (nshell.presentation:input-state-search-query cleared))
      (expect "" :to-equal (nshell.presentation:input-state-search-original-buffer cleared))
      (expect (nshell.presentation:input-state-search-original-cursor cleared) :to-be-null)
      (expect 0 :to-equal (nshell.presentation:input-state-search-index cleared))))

  (it "input-history-search-session-clear-rejects-completion-clear"
    (expect (lambda () (nshell.presentation::apply-history-search-session-clear
       (input-state)
       (nshell.presentation::completion-session-clear))) :to-throw 'error))

  (it "input-state-history-search-input-clears-stale-completion-session"
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
        (expect :search-update :to-be output))))

  (it "input-state-history-search-edit-boundary-commits-session-intent"
    (let ((state (history-search-state
                  :buffer "git"
                  :query "st"
                  :original-buffer "git"
                  :index 2
                  :completion-index 0
                  :completion-base-buffer "g"
                  :completion-base-cursor 1
                  :last-candidates '("git" "grep"))))
      (let* ((query-edit
               (nshell.presentation::make-history-search-query-edit "atus"))
             (query-plan (nshell.presentation::history-search-edit-plan
                          query-edit)))
        (expect (nshell.presentation::%history-search-edit-p query-edit) :to-be-truthy)
        (expect (nshell.presentation::%history-search-edit-plan-p query-plan) :to-be-truthy)
        (expect :query :to-be (nshell.presentation::history-search-edit-plan-kind query-plan))
        (expect "atus" :to-equal (nshell.presentation::history-search-edit-plan-text
                      query-plan))
        (expect 0 :to-equal (nshell.presentation::history-search-edit-plan-delta query-plan))
        (expect (fboundp 'nshell.presentation::history-search-edit-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::history-search-edit-plan-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::make-history-search-edit-plan) :to-be-falsy))
      (with-reduced-input-state (query-state query-output)
          (nshell.presentation::commit-history-search-edit
           state
           (nshell.presentation::make-history-search-query-edit "atus"))
        (is-search-state-with-completion-cleared query-state
                                                 :mode :search
                                                 :query "status"
                                                 :original-buffer "git"
                                                 :index 0)
        (expect :search-update :to-be query-output)
        (let* ((selection-edit
                 (nshell.presentation::make-history-search-selection-edit 1))
               (selection-plan (nshell.presentation::history-search-edit-plan
                                selection-edit)))
          (expect :selection :to-be (nshell.presentation::history-search-edit-plan-kind
                   selection-plan))
          (expect 1 :to-equal (nshell.presentation::history-search-edit-plan-delta
                  selection-plan))
          (with-reduced-input-state (selection-state selection-output)
              (nshell.presentation::commit-history-search-edit
               query-state
               selection-edit)
            (expect 1 :to-equal (nshell.presentation:input-state-search-index
                      selection-state))
            (expect :search-update :to-be selection-output)))
        (let* ((backspace-edit
                 (nshell.presentation::make-history-search-backspace-edit))
               (backspace-plan (nshell.presentation::history-search-edit-plan
                                backspace-edit)))
          (expect :backspace :to-be (nshell.presentation::history-search-edit-plan-kind
                   backspace-plan))
          (with-reduced-input-state (backspace-state backspace-output)
              (nshell.presentation::commit-history-search-edit
               query-state
               backspace-edit)
            (is-search-state-with-completion-cleared backspace-state
                                                     :mode :search
                                                     :query "statu"
                                                     :original-buffer "git"
                                                     :index 0)
            (expect :search-update :to-be backspace-output))))))

  (it "input-state-history-search-query-insertion-truncates-to-buffer-limit"
    (let* ((limit nshell.presentation::+max-input-buffer-size+)
           (query (make-string (1- limit) :initial-element #\a))
           (insertion
             (nshell.presentation::history-search-query-insertion-for-text
              query
              "bcd")))
      (expect (nshell.presentation::%history-search-query-insertion-p insertion) :to-be-truthy)
      (expect (nshell.presentation::history-search-query-insertion-ignored-p
                insertion) :to-be-falsy)
      (expect "b" :to-equal (nshell.presentation::history-search-query-insertion-accepted-text
                    insertion))
      (expect limit :to-equal (length
              (nshell.presentation::history-search-query-insertion-query insertion)))
      (expect (concatenate 'string query "b") :to-equal (nshell.presentation::history-search-query-insertion-query
                    insertion))
      (expect (fboundp 'nshell.presentation::history-search-query-insertion-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-history-search-query-insertion) :to-be-falsy)))

  (it "input-state-history-search-query-insertion-ignores-invalid-or-full-input"
    (let* ((limit nshell.presentation::+max-input-buffer-size+)
           (full-query (make-string limit :initial-element #\q)))
      (dolist (case `(("git" nil)
                      ("git" "")
                      (,full-query "x")))
        (destructuring-bind (query text) case
          (let ((insertion
                  (nshell.presentation::history-search-query-insertion-for-text
                   query
                   text)))
            (expect (nshell.presentation::history-search-query-insertion-ignored-p
                 insertion) :to-be-truthy)
            (expect "" :to-equal (nshell.presentation::history-search-query-insertion-accepted-text
                          insertion))
            (expect query :to-equal (nshell.presentation::history-search-query-insertion-query
                          insertion)))))))

  (it "input-state-history-search-transition-commits-finish-and-cancel"
    "History-search finish/cancel output should pass through a typed transition boundary."
    (let ((state (history-search-state
                  :buffer "git status"
                  :cursor-pos 10
                  :query "st"
                  :original-buffer "git"
                  :original-cursor 3
                  :index 1)))
      (let ((finished (nshell.presentation::history-search-finished-transition
                       state :execute)))
        (expect (nshell.presentation::%history-search-transition-p finished) :to-be-truthy)
        (expect (fboundp 'nshell.presentation::%make-history-search-transition) :to-be-truthy)
        (expect (fboundp 'nshell.presentation::history-search-transition-p) :to-be-falsy)
        (expect (fboundp 'nshell.presentation::make-history-search-transition) :to-be-falsy)
        (expect :execute :to-be (nshell.presentation::history-search-transition-output finished))
        (expect :insert :to-be (nshell.presentation:input-state-mode
                 (nshell.presentation::history-search-transition-state finished)))
        (multiple-value-bind (finished-state finished-output)
            (nshell.presentation::commit-history-search-transition finished)
          (expect :execute :to-be finished-output)
          (is-input-state finished-state
                          :mode :insert
                          :buffer "git status"
                          :cursor-pos 10)
          (expect "" :to-equal (nshell.presentation:input-state-search-query
                        finished-state))))
      (let ((cancelled (nshell.presentation::history-search-cancelled-transition
                        state)))
        (expect (nshell.presentation::%history-search-transition-p cancelled) :to-be-truthy)
        (expect :suggest-update :to-be (nshell.presentation::history-search-transition-output
                 cancelled))
        (multiple-value-bind (cancelled-state cancelled-output)
            (nshell.presentation::commit-history-search-transition cancelled)
          (expect :suggest-update :to-be cancelled-output)
          (is-input-state cancelled-state
                          :mode :insert
                          :buffer "git"
                          :cursor-pos 3)
          (expect "" :to-equal (nshell.presentation:input-state-search-query
                        cancelled-state))))))

  (it "input-state-history-search-key-command-is-private-value"
    "History-search key events should translate to typed commands before mutation."
    (let ((typed (nshell.presentation::history-search-key-command-for-event
                  (input-key-event :char #\s)))
          (pasted (nshell.presentation::history-search-key-command-for-event
                   (input-key-event :paste nil nil
                                    '(:protocol :bracketed :text "ta"))))
          (older (nshell.presentation::history-search-key-command-for-event
                  (input-key-event :ctrl-r)))
          (execute (nshell.presentation::history-search-key-command-for-event
                    (input-key-event :enter))))
      (expect (nshell.presentation::%history-search-key-command-p typed) :to-be-truthy)
      (expect (listp typed) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::history-search-key-command-p) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-history-search-key-command) :to-be-falsy)
      (expect :query :to-be (nshell.presentation::history-search-key-command-kind typed))
      (expect "s" :to-equal (nshell.presentation::history-search-key-command-text typed))
      (expect :query :to-be (nshell.presentation::history-search-key-command-kind pasted))
      (expect "ta" :to-equal (nshell.presentation::history-search-key-command-text
                    pasted))
      (expect :selection :to-be (nshell.presentation::history-search-key-command-kind older))
      (expect 1 :to-equal (nshell.presentation::history-search-key-command-delta older))
      (expect :finish :to-be (nshell.presentation::history-search-key-command-kind execute))
      (expect :execute :to-be (nshell.presentation::history-search-key-command-output
               execute))))

  (it "input-state-history-search-edits-query-not-buffer"
    (with-reduced-input-state (search-state)
        (reduce-once (input-state :buffer "git" :cursor-pos 3)
                     :ctrl-r)
      (with-reduced-input-state (s-state s-output)
          (reduce-once search-state :char #\s)
        (expect "git" :to-equal (nshell.presentation:input-state-buffer s-state))
        (is-search-state s-state :mode :search :query "s")
        (expect :search-update :to-be s-output)
        (with-reduced-input-state (t-state)
            (reduce-once s-state :char #\t)
          (expect "st" :to-equal (nshell.presentation:input-state-search-query t-state))
          (with-reduced-input-state (back-state back-output)
              (reduce-once t-state :backspace)
            (expect "s" :to-equal (nshell.presentation:input-state-search-query back-state))
            (expect :search-update :to-be back-output))))))

  (it "input-state-history-search-paste-edits-query-not-buffer"
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
        (expect "git" :to-equal (nshell.presentation:input-state-buffer new-state))
        (expect :search-update :to-be output))))

  (it "input-state-history-search-cycles-and-applies-results"
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
      (expect "git log" :to-equal (nshell.presentation:input-state-buffer applied))
      (expect 7 :to-equal (nshell.presentation:input-state-cursor-pos applied))
      (is-completion-session-cleared applied)
      (with-reduced-input-state (older older-output) (reduce-once applied :ctrl-r)
        (expect 2 :to-equal (nshell.presentation:input-state-search-index older))
        (expect :search-update :to-be older-output)
        (let ((wrapped
                (nshell.presentation:apply-history-search-results-to-input-state
                 older matches)))
          (expect "git status" :to-equal (nshell.presentation:input-state-buffer wrapped))))
      (with-reduced-input-state (older older-output) (reduce-once applied :ctrl-p)
        (expect 2 :to-equal (nshell.presentation:input-state-search-index older))
        (expect :search-update :to-be older-output))
      (with-reduced-input-state (newer newer-output) (reduce-once applied :ctrl-n)
        (expect 0 :to-equal (nshell.presentation:input-state-search-index newer))
        (expect :search-update :to-be newer-output))))

  (it "input-state-history-search-ignores-non-string-results"
    (let ((state (history-search-state
                  :query "git"
                  :original-buffer "g"
                  :index 1)))
      (let ((applied
              (nshell.presentation:apply-history-search-results-to-input-state
               state '(42 "git status" :ignored "git log"))))
        (expect "git log" :to-equal (nshell.presentation:input-state-buffer applied))
        (expect 7 :to-equal (nshell.presentation:input-state-cursor-pos applied))
        (is-search-state applied
                         :mode :search
                         :query "git"
                         :original-buffer "g"
                         :index 1))))

  (it "input-state-history-search-leaves-non-search-state-unchanged"
    (let ((state (input-state :buffer "git" :cursor-pos 3)))
      (let ((applied
              (nshell.presentation:apply-history-search-results-to-input-state
               state '("git status" "git log"))))
        (expect state :to-equalp applied)
        (expect "git" :to-equal (nshell.presentation:input-state-buffer applied))
        (expect 3 :to-equal (nshell.presentation:input-state-cursor-pos applied)))))

  (it "input-state-history-search-ctrl-s-moves-to-newer-result"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "git"
                  :original-buffer "g"
                  :index 2)))
      (with-reduced-input-state (newer output) (reduce-once state :ctrl-s)
        (expect 1 :to-equal (nshell.presentation:input-state-search-index newer))
        (expect :search-update :to-be output))))

  (it "input-state-history-search-empty-results-restore-original-cursor"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "nomatch"
                  :original-buffer "git status"
                  :original-cursor 4
                  :index 2)))
      (let ((restored
              (nshell.presentation:apply-history-search-results-to-input-state
               state '())))
        (expect "git status" :to-equal (nshell.presentation:input-state-buffer restored))
        (expect 4 :to-equal (nshell.presentation:input-state-cursor-pos restored))
        (is-search-state restored
                         :mode :search
                         :query "nomatch"
                         :original-buffer "git status"
                         :original-cursor 4
                         :index 2)))))
