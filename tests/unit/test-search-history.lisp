(in-package #:nshell/test)

(describe "search-history-service-tests"
  (it "history-suggestion-returns-suffix-and-publishes-completion-event"
    "Suggestions return only the completion suffix for the newest prefix match."
    (with-history (history "git status" "git stash" "echo done")
      (let ((dispatcher (nshell.application:make-event-dispatcher)))
        (with-event-capture (events dispatcher :completion-triggered)
            (nshell.domain.events:domain-event-type event)
          (expect " stash" :to-equal (nshell.application:history-suggestion history "git" dispatcher))
          (expect (nshell.application:drain-events dispatcher) :to-be-null)
          (expect '(:completion-triggered) :to-equal (nreverse events))))))

  (it "history-suggestion-returns-nil-without-match"
    "Suggestions are NIL when no command has the requested prefix."
    (with-history (history "git status" "echo done")
      (expect (nshell.application:history-suggestion history "make") :to-be-null)))

  (it "history-suggestion-returns-nil-for-exact-match"
    "Exact history matches should not produce a zero-length suggestion."
    (with-history (history "git status" "echo done")
      (expect (nshell.application:history-suggestion history "git status") :to-be-null)))

  (it "history-suggestion-prefers-successful-match-over-newer-failure"
    "Autosuggestion should not prefer a recent failed typo over an older success."
    (let ((history (nshell.domain.history:make-command-history)))
      (nshell.domain.history:history-add history "git status" 0)
      (nshell.domain.history:history-add history "git stahs" 1)
      (expect "tus" :to-equal (nshell.application:history-suggestion history "git sta"))))

  (it "history-suggestion-falls-back-to-failed-match"
    "Failed entries remain suggestible when no non-failing match exists."
    (let ((history (nshell.domain.history:make-command-history)))
      (nshell.domain.history:history-add history "git stahs" 1)
      (expect "hs" :to-equal (nshell.application:history-suggestion history "git sta"))))

  (it "history-suggestion-uses-continuation-line-prefix"
    "Autosuggestion can complete the current line from a multiline history entry."
    (with-history (history "echo setup
git status --short"
                           "printf 'not a prefix git'")
      (expect "atus --short" :to-equal (nshell.application:history-suggestion history "git st"))))

  (it "history-suggestion-does-not-return-prefix-before-continuation-line"
    "Continuation-line suggestions expose only the matching line suffix."
    (with-history (history "echo setup
git status")
      (expect " status" :to-equal (nshell.application:history-suggestion history "git"))))

  (it "history-suggestion-returns-nil-for-exact-continuation-line-match"
    "Exact continuation-line matches should not produce a zero-length suggestion."
    (with-history (history "echo setup
git status")
      (expect (nshell.application:history-suggestion history "git status") :to-be-null)))

  (it "history-suggestion-ignores-blank-input"
    "Empty prompts should not ghost the newest command from history."
    (with-history (history "git status" "echo done")
      (let ((dispatcher (nshell.application:make-event-dispatcher)))
        (with-event-capture (events dispatcher :completion-triggered)
            (nshell.domain.events:domain-event-type event)
          (expect (nshell.application:history-suggestion history "" dispatcher) :to-be-null)
          (expect (nshell.application:history-suggestion history "   " dispatcher) :to-be-null)
          (expect (nshell.application:history-suggestion history "|" dispatcher) :to-be-null)
          (expect (nshell.application:history-suggestion history "&&" dispatcher) :to-be-null)
          (expect events :to-be-null)))))

  (it "search-history-use-case-delegates-mode-and-publishes-event"
    "The search use case supports domain search modes and emits a search event."
    (with-history (history "git status" "make test" "grep status log")
      (let ((dispatcher (nshell.application:make-event-dispatcher)))
        (with-event-capture (events dispatcher :history-searched)
            (nshell.domain.events:domain-event-type event)
          (let ((results (nshell.application:search-history-use-case
                          history "status" :contains dispatcher)))
            (expect 2 :to-equal (length results))
            (let ((matching 0))
              (dolist (entry results)
                (when (search "status" (nshell.domain.history:entry-text entry))
                  (incf matching)))
              (expect 2 :to-equal matching)))
          (expect (nshell.application:drain-events dispatcher) :to-be-null)
          (expect '(:history-searched) :to-equal (nreverse events))))))

  (it "interactive-history-search-prefers-line-prefix-before-contains"
    "Interactive reverse search ranks command-line starts before incidental substrings."
    (with-history (history "echo setup
git status"
                           "printf 'not a prefix git'"
                           "git push")
      (let ((dispatcher (nshell.application:make-event-dispatcher)))
        (with-event-capture (events dispatcher :history-searched)
            (nshell.domain.events:domain-event-type event)
          (let ((results (nshell.application:interactive-history-search-use-case
                          history "git" dispatcher)))
            (expect '("git push"
                         "echo setup
git status"
                         "printf 'not a prefix git'") :to-equal (nshell.domain.history:history-entry-texts results)))
          (expect (nshell.application:drain-events dispatcher) :to-be-null)
          (expect '(:history-searched) :to-equal (nreverse events))))))

  (it "interactive-history-search-handles-large-gapped-history"
    "Interactive reverse search keeps ranking with many nonmatching entries."
    (let ((history (nshell.domain.history:make-command-history :max-entries 7000)))
      (nshell.domain.history:history-add history "echo setup
git old")
      (loop for index below 1500
            do (nshell.domain.history:history-add
                history
                (format nil "make target-~d" index)))
      (nshell.domain.history:history-add history "printf GIT middle")
      (loop for index below 1500
            do (nshell.domain.history:history-add
                history
                (format nil "cargo test-~d" index)))
      (nshell.domain.history:history-add history "git newest")
      (loop for index below 1500
            do (nshell.domain.history:history-add
                history
                (format nil "echo unrelated-~d" index)))
      (expect '("git newest"
                   "echo setup
git old"
                   "printf GIT middle") :to-equal (nshell.domain.history:history-entry-texts
                  (nshell.application:interactive-history-search-use-case
                   history
                   "git")))))

  (it "interactive-history-search-ignores-blank-query"
    "Interactive reverse search should not preselect history before the user types."
    (with-history (history "git status" "docker ps")
      (let ((dispatcher (nshell.application:make-event-dispatcher)))
        (with-event-capture (events dispatcher :history-searched)
            (nshell.domain.events:domain-event-type event)
          (expect (nshell.application:interactive-history-search-use-case
                     history "" dispatcher) :to-be-null)
          (expect (nshell.application:interactive-history-search-use-case
                     history "|" dispatcher) :to-be-null)
          (expect (nshell.application:interactive-history-search-use-case
                     history "&&" dispatcher) :to-be-null)
          (expect (nshell.application:drain-events dispatcher) :to-be-null)
          (expect '(:history-searched :history-searched :history-searched) :to-equal (nreverse events)))))))
