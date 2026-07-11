(in-package #:nshell/test)

(def-suite search-history-service-tests
  :description "Application history-search service tests"
  :in nshell-tests)

(in-suite search-history-service-tests)

(test history-suggestion-returns-suffix-and-publishes-completion-event
  "Suggestions return only the completion suffix for the newest prefix match."
  (with-history (history "git status" "git stash" "echo done")
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (with-event-capture (events dispatcher :completion-triggered)
          (nshell.domain.events:domain-event-type event)
        (is (string= " stash"
                     (nshell.application:history-suggestion history "git" dispatcher)))
        (is (null (nshell.application:drain-events dispatcher)))
        (is (equal '(:completion-triggered) (nreverse events)))))))

(test history-suggestion-returns-nil-without-match
  "Suggestions are NIL when no command has the requested prefix."
  (with-history (history "git status" "echo done")
    (is (null (nshell.application:history-suggestion history "make")))))

(test history-suggestion-returns-nil-for-exact-match
  "Exact history matches should not produce a zero-length suggestion."
  (with-history (history "git status" "echo done")
    (is (null (nshell.application:history-suggestion history "git status")))))

(test history-suggestion-prefers-successful-match-over-newer-failure
  "Autosuggestion should not prefer a recent failed typo over an older success."
  (let ((history (nshell.domain.history:make-command-history)))
    (nshell.domain.history:history-add history "git status" 0)
    (nshell.domain.history:history-add history "git stahs" 1)
    (is (string= "tus"
                 (nshell.application:history-suggestion history "git sta")))))

(test history-suggestion-falls-back-to-failed-match
  "Failed entries remain suggestible when no non-failing match exists."
  (let ((history (nshell.domain.history:make-command-history)))
    (nshell.domain.history:history-add history "git stahs" 1)
    (is (string= "hs"
                 (nshell.application:history-suggestion history "git sta")))))

(test history-suggestion-uses-continuation-line-prefix
  "Autosuggestion can complete the current line from a multiline history entry."
  (with-history (history "echo setup
git status --short"
                         "printf 'not a prefix git'")
    (is (string= "atus --short"
                 (nshell.application:history-suggestion history "git st")))))

(test history-suggestion-does-not-return-prefix-before-continuation-line
  "Continuation-line suggestions expose only the matching line suffix."
  (with-history (history "echo setup
git status")
    (is (string= " status"
                 (nshell.application:history-suggestion history "git")))))

(test history-suggestion-returns-nil-for-exact-continuation-line-match
  "Exact continuation-line matches should not produce a zero-length suggestion."
  (with-history (history "echo setup
git status")
    (is (null (nshell.application:history-suggestion history "git status")))))

(test history-suggestion-ignores-blank-input
  "Empty prompts should not ghost the newest command from history."
  (with-history (history "git status" "echo done")
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (with-event-capture (events dispatcher :completion-triggered)
          (nshell.domain.events:domain-event-type event)
        (is (null (nshell.application:history-suggestion history "" dispatcher)))
        (is (null (nshell.application:history-suggestion history "   " dispatcher)))
        (is (null (nshell.application:history-suggestion history "|" dispatcher)))
        (is (null (nshell.application:history-suggestion history "&&" dispatcher)))
        (is (null events))))))

(test search-history-use-case-delegates-mode-and-publishes-event
  "The search use case supports domain search modes and emits a search event."
  (with-history (history "git status" "make test" "grep status log")
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (with-event-capture (events dispatcher :history-searched)
          (nshell.domain.events:domain-event-type event)
        (let ((results (nshell.application:search-history-use-case
                        history "status" :contains dispatcher)))
          (is (= 2 (length results)))
          (let ((matching 0))
            (dolist (entry results)
              (when (search "status" (nshell.domain.history:entry-text entry))
                (incf matching)))
            (is (= 2 matching))))
        (is (null (nshell.application:drain-events dispatcher)))
        (is (equal '(:history-searched) (nreverse events)))))))

(test interactive-history-search-prefers-line-prefix-before-contains
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
          (is (equal '("git push"
                       "echo setup
git status"
                       "printf 'not a prefix git'")
                     (nshell.domain.history:history-entry-texts results))))
        (is (null (nshell.application:drain-events dispatcher)))
        (is (equal '(:history-searched) (nreverse events)))))))

(test interactive-history-search-handles-large-gapped-history
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
    (is (equal '("git newest"
                 "echo setup
git old"
                 "printf GIT middle")
               (nshell.domain.history:history-entry-texts
                (nshell.application:interactive-history-search-use-case
                 history
                 "git"))))))

(test interactive-history-search-ignores-blank-query
  "Interactive reverse search should not preselect history before the user types."
  (with-history (history "git status" "docker ps")
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (with-event-capture (events dispatcher :history-searched)
          (nshell.domain.events:domain-event-type event)
        (is (null (nshell.application:interactive-history-search-use-case
                   history "" dispatcher)))
        (is (null (nshell.application:interactive-history-search-use-case
                   history "|" dispatcher)))
        (is (null (nshell.application:interactive-history-search-use-case
                   history "&&" dispatcher)))
        (is (null (nshell.application:drain-events dispatcher)))
        (is (equal '(:history-searched :history-searched :history-searched)
                   (nreverse events)))))))
