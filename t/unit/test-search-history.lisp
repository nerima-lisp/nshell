(in-package #:nshell/test)

(describe "search-history-service-tests"
  (it "history-suggestion-returns-suffix"
    "Suggestions include the rest of a multiline entry after the matching prefix."
    (with-history (history "git status" "git stash" "echo done")
      (expect " stash" :to-equal (nshell.application:history-suggestion history "git")))
    (with-history (history "if true
echo I04_MULTILINE_TAIL
end")
      (expect (format nil " true~%echo I04_MULTILINE_TAIL~%end")
              :to-equal
              (nshell.application:history-suggestion history "if"))))

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
    (let ((history (history-kit:make-history)))
      (history-kit:history-add history "git status" :exit-code 0)
      (history-kit:history-add history "git stahs" :exit-code 1)
      (expect "tus" :to-equal (nshell.application:history-suggestion history "git sta"))))
  (it "history-suggestion-ranks-current-cwd-before-other-cwds"
    "The exact current cwd ranks first while success and recency remain ordered."
    (let ((history (history-kit:make-history)))
      (add-history-record history "git status --short" :cwd "/repo" :exit-code 0)
      (add-history-record history "git status --porcelain" :cwd "/repo" :exit-code 0)
      (add-history-record history "git status --verbose" :cwd "/repo" :exit-code 1)
      (add-history-record history "git status --branch" :cwd "/elsewhere" :exit-code 0)
      (expect " --porcelain"
              :to-equal
              (nshell.application:history-suggestion
               history "git status" :cwd "/repo"))))
  (it "history-suggestion-falls-back-when-no-current-cwd-matches"
    "Entries remain suggestible when none has exact cwd metadata for this prompt."
    (let ((history (history-kit:make-history)))
      (add-history-record history "git status --branch" :cwd "/elsewhere" :exit-code 0)
      (expect " --branch"
              :to-equal
              (nshell.application:history-suggestion
               history "git status" :cwd "/repo"))))

  (it "history-suggestion-falls-back-to-failed-match"
    "Failed entries remain suggestible when no non-failing match exists."
    (let ((history (history-kit:make-history)))
      (history-kit:history-add history "git stahs" :exit-code 1)
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
      (expect (nshell.application:history-suggestion history "") :to-be-null)
      (expect (nshell.application:history-suggestion history "   ") :to-be-null)
      (expect (nshell.application:history-suggestion history "|") :to-be-null)
      (expect (nshell.application:history-suggestion history "&&") :to-be-null)))

  (it "search-history-use-case-delegates-mode"
    "The search use case supports domain search modes."
    (with-history (history "git status" "make test" "grep status log")
      (let ((results (nshell.application:search-history-use-case
                      history "status" :contains)))
        (expect 2 :to-equal (length results))
        (let ((matching 0))
          (dolist (entry results)
            (when (search "status" (history-kit:history-entry-text entry))
              (incf matching)))
          (expect 2 :to-equal matching)))))

  (it "search-history-use-case-filters-failed-records"
    "The search use case can restrict results to nonzero exit codes."
    (let ((history (history-kit:make-history)))
      (add-history-record history "git status" :exit-code 0 :origin :typed)
      (add-history-record history "git deploy" :exit-code 7 :origin :agent)
      (expect '("git deploy")
              :to-equal
              (mapcar #'history-kit:history-entry-text
                      (nshell.application:search-history-use-case
                       history "git" :contains :exit-code :failed)))))

  (it "interactive-history-search-filters-failed-records"
    "Ctrl-R query tokens can restrict matches by exit status."
    (let ((history (history-kit:make-history)))
      (add-history-record history "git status" :exit-code 0 :origin :typed)
      (add-history-record history "git deploy" :exit-code 7 :origin :agent)
      (expect '("git deploy")
              :to-equal
              (history-kit:history-entry-texts
               (nshell.application:interactive-history-search-use-case
                history "status:failed git")))))
  (it "interactive-history-search-filters-host-and-duration-bounds"
    "Ctrl-R host and duration tokens use exact hosts and inclusive bounds."
    (let ((history (history-kit:make-history)))
      (add-history-record history "echo lower bound" :host "alpha" :duration-ms 100)
      (add-history-record history "echo middle" :host "alpha" :duration-ms 125)
      (add-history-record history "echo upper bound" :host "alpha" :duration-ms 150)
      (add-history-record history "echo too fast" :host "alpha" :duration-ms 99)
      (add-history-record history "echo too slow" :host "alpha" :duration-ms 151)
      (add-history-record history "echo no duration" :host "alpha")
      (add-history-record history "echo other host" :host "beta" :duration-ms 125)
      (expect (list "echo lower bound" "echo middle" "echo upper bound")
              :to-equal
              (sort
               (history-kit:history-entry-texts
                (nshell.application:interactive-history-search-use-case
                 history "host:alpha duration-min:100 duration-max:150"))
               (function string<)))))
  (it "interactive-history-search-supports-quoted-metadata-values"
    "Quoted token values preserve whitespace and combine with free-text terms."
    (let ((history (history-kit:make-history)))
      (add-history-record history "echo target" :cwd "/workspace/My Project")
      (add-history-record history "printf target" :cwd "/workspace/My Project")
      (add-history-record history "echo elsewhere" :cwd "/workspace/Other")
      (expect '("echo target")
              :to-equal
              (history-kit:history-entry-texts
               (nshell.application:interactive-history-search-use-case
                history "cwd:\"/workspace/My Project\" echo")))
      (expect '("echo target" "printf target")
              :to-equal
              (sort
               (history-kit:history-entry-texts
                (nshell.application:interactive-history-search-use-case
                 history "cwd:\"/workspace/My Project\""))
               #'string<))
      (expect '("echo elsewhere")
              :to-equal
              (history-kit:history-entry-texts
               (nshell.application:interactive-history-search-use-case
                history "cwd:\"/workspace/My Project\" cwd:/workspace/Other")))))
  (it "history-builtin-filters-metadata-and-renders-utc-timestamps"
    "The history builtin supports host and duration filters and displays UTC timestamps on request."
    (with-builtins-context (context)
      (let* ((history (nshell.application:shell-context-history context))
             (timestamp (encode-universal-time 5 4 3 2 1 2000 0)))
        (add-history-record history "history lower" :host "alpha"
                            :duration-ms 100 :timestamp timestamp)
        (add-history-record history "history upper" :host "alpha"
                            :duration-ms 150 :timestamp nil)
        (add-history-record history "history other host" :host "beta"
                            :duration-ms 125 :timestamp timestamp)
        (add-history-record history "history too fast" :host "alpha"
                            :duration-ms 99 :timestamp timestamp)
        (add-history-record history "history too slow" :host "alpha"
                            :duration-ms 151 :timestamp timestamp)
        (add-history-record history "history missing duration" :host "alpha"
                            :timestamp timestamp)
        (assert-builtin-call
         (context "history"
                  (list "--host" "alpha" "--duration-min=100"
                        "--duration-max" "150"))
         :code 0
         :output (format nil "history lower~%history upper~%"))
        (assert-builtin-call
         (context "history"
                  (list "--timestamps" "--host=alpha" "--duration-min" "100"
                        "--duration-max=150"))
         :code 0
         :output (format nil
                         "2000-01-02T03:04:05Z history lower~%- history upper~%"))
        (assert-builtin-call
         (context "history" (list "--host" "--timestamps"))
         :code 1
         :contains (list "usage")))))

  (it "interactive-history-search-prefers-line-prefix-before-contains"
    "Interactive reverse search ranks command-line starts before incidental substrings."
    (with-history (history "echo setup
git status"
                           "printf 'not a prefix git'"
                           "git push")
      (let ((results (nshell.application:interactive-history-search-use-case
                      history "git")))
        (expect '("git push"
                     "echo setup
git status"
                     "printf 'not a prefix git'") :to-equal (history-kit:history-entry-texts results)))))

  (it "interactive-history-search-handles-large-gapped-history"
    "Interactive reverse search keeps ranking with many nonmatching entries."
    (let ((history (history-kit:make-history :capacity 7000)))
      (history-kit:history-add history "echo setup
git old")
      (loop for index below 1500
            do (history-kit:history-add
                history
                (format nil "make target-~d" index)))
      (history-kit:history-add history "printf GIT middle")
      (loop for index below 1500
            do (history-kit:history-add
                history
                (format nil "cargo test-~d" index)))
      (history-kit:history-add history "git newest")
      (loop for index below 1500
            do (history-kit:history-add
                history
                (format nil "echo unrelated-~d" index)))
      (expect '("git newest"
                   "echo setup
git old"
                   "printf GIT middle") :to-equal (history-kit:history-entry-texts
                  (nshell.application:interactive-history-search-use-case
                   history
                   "git")))))

  (it "interactive-history-search-ignores-blank-query"
    "Interactive reverse search should not preselect history before the user types."
    (with-history (history "git status" "docker ps")
      (expect (nshell.application:interactive-history-search-use-case
                 history "") :to-be-null)
      (expect (nshell.application:interactive-history-search-use-case
                 history "|") :to-be-null)
      (expect (nshell.application:interactive-history-search-use-case
                 history "&&") :to-be-null))))
