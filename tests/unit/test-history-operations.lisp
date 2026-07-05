(in-package #:nshell/test)

(in-suite history-domain-tests)

(test history-add-and-retrieve
  "Commands added to history can be retrieved."
  (let ((history (history-with-lines "ls -la" "git status")))
    (is (= 2 (nshell.domain.history:history-size history)))
    (is (not (nshell.domain.history:history-empty-p history)))))

(test history-empty
  "New history is empty."
  (let ((history (nshell.domain.history:make-command-history)))
    (is (nshell.domain.history:history-empty-p history))
    (is (= 0 (nshell.domain.history:history-size history)))))

(test history-dedup
  "Adding same command twice keeps only most recent."
  (let ((history (history-with-lines "ls" "ls")))
    (is (= 1 (nshell.domain.history:history-size history)))))

(test history-max-entries
  "History respects max-entries limit."
  (let ((history (nshell.domain.history:make-command-history :max-entries 3)))
    (dolist (line '("cmd1" "cmd2" "cmd3" "cmd4"))
      (nshell.domain.history:history-add history line))
    (is (= 3 (nshell.domain.history:history-size history)))
    (is (equal '("cmd4" "cmd3" "cmd2")
               (nshell.domain.history:history-entry-texts
                (nshell.domain.history:history-all history))))))

(test history-merge
  "History merge keeps newest-first order and deduplicates by text."
  (let ((history (history-with-lines "local" "shared"))
        (incoming (history-with-lines "shared" "remote")))
    (nshell.domain.history:history-merge
     history
     (nshell.domain.history:history-all incoming))
    (is (= 3 (nshell.domain.history:history-size history)))
    (is (equal '("remote" "shared" "local")
               (nshell.domain.history:history-entry-texts
                (nshell.domain.history:history-all history))))))

(test history-delete-and-clear
  "History entries can be deleted exactly and cleared."
  (let ((history (history-with-lines "git status" "git commit")))
    (is (= 1 (nshell.domain.history:history-delete history "git status")))
    (is (= 1 (nshell.domain.history:history-size history)))
    (is (equal '("git commit")
               (nshell.domain.history:history-entry-texts
                (nshell.domain.history:history-all history))))
    (nshell.domain.history:history-clear history)
    (is (nshell.domain.history:history-empty-p history))))

(test history-command-line-last-argument-extracts-final-argument
  "The last-argument helper ignores the command word and keeps source quoting."
  (is (string= "--short"
               (nshell.domain.history:command-line-last-argument
                "git status --short")))
  (is (string= "\"hello world\""
               (nshell.domain.history:command-line-last-argument
                "git commit -m \"hello world\"")))
  (is (string= "my\\ file"
               (nshell.domain.history:command-line-last-argument
                "echo my\\ file")))
  (is (string= "\"hello\"world"
               (nshell.domain.history:command-line-last-argument
                "echo \"hello\"world")))
  (is (null (nshell.domain.history:command-line-last-argument "ls")))
  (is (string= "two"
               (nshell.domain.history:command-line-last-argument
                "echo one | grep two")))
  (is (string= "\"two\"words"
               (nshell.domain.history:command-line-last-argument
                "echo one | grep \"two\"words")))
  (is (string= "hi"
               (nshell.domain.history:command-line-last-argument
                "echo hi > out"))))

(test history-command-line-last-argument-skips-logical-redirection-targets
  "Redirect targets are skipped as logical shell words, including quoted fragments."
  (is (string= "kept"
               (nshell.domain.history:command-line-last-argument
                "printf kept > \"out\"file")))
  (is (string= "next"
               (nshell.domain.history:command-line-last-argument
                "printf kept > out\\ file next"))))

(test history-last-argument-scan-cursor-projects-token-and-word-boundaries
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
    (is (not (fboundp 'nshell.domain.history::copy-%history-token-window)))
    (is (not (fboundp 'nshell.domain.history::copy-%history-logical-word-cursor)))
    (is (not (fboundp 'nshell.domain.history::copy-%history-last-argument-scan-state)))
    (is (eq word-token (nshell.domain.history::%history-token-window-current window)))
    (is (eq (third tokens) (nshell.domain.history::%history-token-window-next window)))
    (is (string= "echo"
                 (nshell.domain.history::%history-word-source
                  "echo \"hello\"world > out"
                  command-word)))
    (is (string= "\"hello\"world"
                 (nshell.domain.history::%history-word-source
                  "echo \"hello\"world > out"
                  argument-word)))))

(test history-command-line-last-argument-skips-file-descriptor-redirection-prefixes
  "File-descriptor prefixes immediately before redirects are not treated as arguments."
  (is (string= "hi"
               (nshell.domain.history:command-line-last-argument
                "echo hi 2>out.txt")))
  (is (string= "next"
               (nshell.domain.history:command-line-last-argument
                "echo hi 2>out.txt next")))
  (is (string= "log"
               (nshell.domain.history:command-line-last-argument
                "grep error log 2>&1"))))

(test history-command-line-last-argument-skips-leading-assignments
  "Leading shell assignments are not mistaken for the insertable last argument."
  (is (string= "--short"
               (nshell.domain.history:command-line-last-argument
                "A=1 B=2 git status --short")))
  (is (null (nshell.domain.history:command-line-last-argument
             "A=1 B=2"))))

(test history-command-line-last-argument-respects-command-separators
  "Earlier command segments do not leak into the last argument lookup."
  (dolist (case '(("echo ignored && git" nil)
                  ("echo ignored || git status --short" "--short")
                  ("echo ignored ; git" nil)
                  ("echo ignored & git status --short" "--short")))
    (destructuring-bind (line expected) case
      (is (if expected
              (string= expected
                       (nshell.domain.history:command-line-last-argument line))
              (null (nshell.domain.history:command-line-last-argument line)))))))

(test history-last-argument-at-zero-skips-entries-without-arguments
  "Alt-dot history lookup uses the newest command that has an argument."
  (let ((history (history-with-lines "echo kept" "pwd")))
    (is (string= "kept" (nshell.domain.history:history-last-argument-at history 0)))))

(test history-last-argument-at-skips-empty-commands
  "Indexed Alt-dot history lookup skips commands without insertable arguments."
  (let ((history (history-with-lines "echo older"
                                     "git status --short"
                                     "pwd")))
    (is (string= "--short"
                 (nshell.domain.history:history-last-argument-at history 0)))
    (is (string= "older"
                 (nshell.domain.history:history-last-argument-at history 1)))
    (is (null (nshell.domain.history:history-last-argument-at history 2)))
    (is (null (nshell.domain.history:history-last-argument-at history -1)))))
