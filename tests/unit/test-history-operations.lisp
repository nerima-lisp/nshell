(in-package #:nshell/test)

(describe "history-domain-tests"
  (it "history-add-and-retrieve"
    "Commands added to history can be retrieved."
    (let ((history (history-with-lines "ls -la" "git status")))
      (expect 2 :to-equal (nshell.domain.history:history-size history))
      (expect (nshell.domain.history:history-empty-p history) :to-be-falsy)))

  (it "history-empty"
    "New history is empty."
    (let ((history (nshell.domain.history:make-command-history)))
      (expect (nshell.domain.history:history-empty-p history) :to-be-truthy)
      (expect 0 :to-equal (nshell.domain.history:history-size history))))

  (it "history-dedup"
    "Adding same command twice keeps only most recent."
    (let ((history (history-with-lines "ls" "ls")))
      (expect 1 :to-equal (nshell.domain.history:history-size history))))

  (it "history-max-entries"
    "History respects max-entries limit."
    (let ((history (nshell.domain.history:make-command-history :max-entries 3)))
      (dolist (line '("cmd1" "cmd2" "cmd3" "cmd4"))
        (nshell.domain.history:history-add history line))
      (expect 3 :to-equal (nshell.domain.history:history-size history))
      (expect '("cmd4" "cmd3" "cmd2") :to-equal (nshell.domain.history:history-entry-texts
                  (nshell.domain.history:history-all history)))))

  (it "history-merge"
    "History merge keeps newest-first order and deduplicates by text."
    (let ((history (history-with-lines "local" "shared"))
          (incoming (history-with-lines "shared" "remote")))
      (nshell.domain.history:history-merge
       history
       (nshell.domain.history:history-all incoming))
      (expect 3 :to-equal (nshell.domain.history:history-size history))
      (expect '("remote" "shared" "local") :to-equal (nshell.domain.history:history-entry-texts
                  (nshell.domain.history:history-all history)))))

  (it "history-delete-and-clear"
    "History entries can be deleted exactly and cleared."
    (let ((history (history-with-lines "git status" "git commit")))
      (expect 1 :to-equal (nshell.domain.history:history-delete history "git status"))
      (expect 1 :to-equal (nshell.domain.history:history-size history))
      (expect '("git commit") :to-equal (nshell.domain.history:history-entry-texts
                  (nshell.domain.history:history-all history)))
      (nshell.domain.history:history-clear history)
      (expect (nshell.domain.history:history-empty-p history) :to-be-truthy)))

  (it "history-command-line-last-argument-extracts-final-argument"
    "The last-argument helper ignores the command word and keeps source quoting."
    (expect "--short" :to-equal (nshell.domain.history:command-line-last-argument
                  "git status --short"))
    (expect "\"hello world\"" :to-equal (nshell.domain.history:command-line-last-argument
                  "git commit -m \"hello world\""))
    (expect "my\\ file" :to-equal (nshell.domain.history:command-line-last-argument
                  "echo my\\ file"))
    (expect "\"hello\"world" :to-equal (nshell.domain.history:command-line-last-argument
                  "echo \"hello\"world"))
    (expect (nshell.domain.history:command-line-last-argument "ls") :to-be-null)
    (expect "two" :to-equal (nshell.domain.history:command-line-last-argument
                  "echo one | grep two"))
    (expect "\"two\"words" :to-equal (nshell.domain.history:command-line-last-argument
                  "echo one | grep \"two\"words"))
    (expect "hi" :to-equal (nshell.domain.history:command-line-last-argument
                  "echo hi > out")))

  (it "history-command-line-last-argument-skips-logical-redirection-targets"
    "Redirect targets are skipped as logical shell words, including quoted fragments."
    (expect "kept" :to-equal (nshell.domain.history:command-line-last-argument
                  "printf kept > \"out\"file"))
    (expect "next" :to-equal (nshell.domain.history:command-line-last-argument
                  "printf kept > out\\ file next")))

  (it "history-last-argument-scan-cursor-projects-token-and-word-boundaries"
    "Last-argument scanning keeps token lookahead separate from logical shell words."
    (let* ((tokens (nshell.domain.parsing:tokenization-result-tokens
                    (nshell.domain.parsing:tokenize "echo \"hello\"world > out")))
           (word-token (second tokens))
           (window (nshell.domain.history::%history-token-window-from-remaining
                    (rest tokens)))
           (cursor (nshell.domain.history::%make-history-logical-word-cursor
                    (nshell.domain.history::%history-logical-words tokens)))
           (command-word (nshell.domain.history::%history-logical-word-cursor-consume-matching-token
                          cursor
                          (first tokens)))
           (argument-word (nshell.domain.history::%history-logical-word-cursor-consume-matching-token
                           cursor
                           word-token)))
      (expect (fboundp 'nshell.domain.history::copy-%history-token-window) :to-be-falsy)
      (expect (fboundp 'nshell.domain.history::copy-%history-logical-word-cursor) :to-be-falsy)
      (expect (fboundp 'nshell.domain.history::copy-%history-last-argument-scan-state) :to-be-falsy)
      (expect word-token :to-be (nshell.domain.history::%history-token-window-current window))
      (expect (third tokens) :to-be (nshell.domain.history::%history-token-window-next window))
      (expect "echo" :to-equal (nshell.domain.history::%history-word-source
                    "echo \"hello\"world > out"
                    command-word))
      (expect "\"hello\"world" :to-equal (nshell.domain.history::%history-word-source
                    "echo \"hello\"world > out"
                    argument-word))))

  (it "history-command-line-last-argument-skips-file-descriptor-redirection-prefixes"
    "File-descriptor prefixes immediately before redirects are not treated as arguments."
    (expect "hi" :to-equal (nshell.domain.history:command-line-last-argument
                  "echo hi 2>out.txt"))
    (expect "next" :to-equal (nshell.domain.history:command-line-last-argument
                  "echo hi 2>out.txt next"))
    (expect "log" :to-equal (nshell.domain.history:command-line-last-argument
                  "grep error log 2>&1")))

  (it "history-command-line-last-argument-skips-leading-assignments"
    "Leading shell assignments are not mistaken for the insertable last argument."
    (expect "--short" :to-equal (nshell.domain.history:command-line-last-argument
                  "A=1 B=2 git status --short"))
    (expect (nshell.domain.history:command-line-last-argument
               "A=1 B=2") :to-be-null))

  (it "history-command-line-last-argument-respects-command-separators"
    "Earlier command segments do not leak into the last argument lookup."
    (dolist (case '(("echo ignored && git" nil)
                    ("echo ignored || git status --short" "--short")
                    ("echo ignored ; git" nil)
                    ("echo ignored & git status --short" "--short")))
      (destructuring-bind (line expected) case
        (expect (if expected
                (string= expected
                         (nshell.domain.history:command-line-last-argument line))
                (null (nshell.domain.history:command-line-last-argument line))) :to-be-truthy))))

  (it "history-last-argument-at-zero-skips-entries-without-arguments"
    "Alt-dot history lookup uses the newest command that has an argument."
    (let ((history (history-with-lines "echo kept" "pwd")))
      (expect "kept" :to-equal (nshell.domain.history:history-last-argument-at history 0))))

  (it "history-last-argument-at-skips-empty-commands"
    "Indexed Alt-dot history lookup skips commands without insertable arguments."
    (let ((history (history-with-lines "echo older"
                                       "git status --short"
                                       "pwd")))
      (expect "--short" :to-equal (nshell.domain.history:history-last-argument-at history 0))
      (expect "older" :to-equal (nshell.domain.history:history-last-argument-at history 1))
      (expect (nshell.domain.history:history-last-argument-at history 2) :to-be-null)
      (expect (nshell.domain.history:history-last-argument-at history -1) :to-be-null)))

  (it "pbt-history-consecutive-duplicate-keeps-size"
    "Adding the same command twice in a row leaves the size as after one add."
    (check-property (:trials 50)
        ((cmd (gen-shell-command) #'shrink-shell-word))
      (let ((history (nshell.domain.history:make-command-history)))
        (nshell.domain.history:history-add history cmd)
        (let ((size-after-one (nshell.domain.history:history-size history)))
          (nshell.domain.history:history-add history cmd)
          (= size-after-one (nshell.domain.history:history-size history))))))

  (it "pbt-history-size-never-exceeds-capacity"
    "Size never exceeds max-entries, however many commands are added."
    (check-property (:trials 30)
        ((n (gen-in-range 1 20) #'shrink-integer))
      (let ((history (nshell.domain.history:make-command-history :max-entries 5)))
        (dotimes (i n)
          (nshell.domain.history:history-add history (format nil "cmd~d" i)))
        (<= (nshell.domain.history:history-size history) 5)))))
