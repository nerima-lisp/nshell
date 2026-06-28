(in-package #:nshell/test)

(in-suite history-domain-tests)

(test history-navigation-reuses-original-prefix
  "Repeated previous navigation keeps matching the prefix typed before cycling."
  (let ((history (history-with-lines "git commit" "grep needle" "git status")))
    (is (string= "git status"
                 (nshell.domain.history:history-previous history "git")))
    (is (string= "git commit"
                 (nshell.domain.history:history-previous history "git status")))))

(test history-navigation-next-restores-original-input
  "Navigating down past the newest match restores the originally typed input."
  (let ((history (history-with-lines "git commit" "grep needle" "git status")))
    (is (string= "git status"
                 (nshell.domain.history:history-previous history "git")))
    (is (string= "git commit"
                 (nshell.domain.history:history-previous history "git status")))
    (is (string= "git status"
                 (nshell.domain.history:history-next history)))
    (is (string= "git"
                 (nshell.domain.history:history-next history)))
    (is (null (nshell.domain.history:history-next history)))))

(test history-navigation-next-clears-stale-prefix
  "Exhausting next navigation clears the previous prefix before a fresh search."
  (let ((history (history-with-lines "git commit" "grep needle" "git status")))
    (is (string= "git status"
                 (nshell.domain.history:history-previous history "git")))
    (is (string= "git"
                 (nshell.domain.history:history-next history)))
    (is (null (nshell.domain.history:history-next history)))
    (is (string= "grep needle"
                 (nshell.domain.history:history-previous history "grep")))))

(test history-reset-navigation-starts-next-search-from-current-prefix
  "Resetting navigation lets the next previous search use the edited buffer."
  (let ((history (history-with-lines "git commit" "grep needle" "git status")))
    (is (string= "git status"
                 (nshell.domain.history:history-previous history "git")))
    (nshell.domain.history:history-reset-navigation history)
    (is (null (nshell.domain.history:history-previous history "git status!")))))

(test history-navigation-matches-continuation-line-prefix
  "Previous navigation matches prefixes at the beginning of any history line."
  (let ((history (history-with-lines "echo setup
git status"
                                     "printf 'not a prefix git'")))
    (is (string= "echo setup
git status"
                 (nshell.domain.history:history-previous history "git")))))

(test history-navigation-respects-smartcase
  "Uppercase navigation prefixes match case-sensitively."
  (let ((history (history-with-lines "echo setup
git status"
                                     "Git status")))
    (is (string= "Git status"
                 (nshell.domain.history:history-previous history "Git")))
    (is (null (nshell.domain.history:history-previous history "Git status")))))

(test history-navigation-handles-large-gapped-prefix-search
  "Previous and next navigation remain correct when matches are far apart."
  (let ((history (nshell.domain.history:make-command-history :max-entries 7000)))
    (nshell.domain.history:history-add history "git old")
    (loop for i below 3000
          do (nshell.domain.history:history-add
              history
              (format nil "echo ~4,'0D" i)))
    (nshell.domain.history:history-add history "git newer")
    (loop for i below 3000
          do (nshell.domain.history:history-add
              history
              (format nil "make ~4,'0D" i)))
    (is (string= "git newer"
                 (nshell.domain.history:history-previous history "git")))
    (is (string= "git old"
                 (nshell.domain.history:history-previous history "git newer")))
    (is (string= "git newer"
                 (nshell.domain.history:history-next history)))
    (is (string= "git"
                 (nshell.domain.history:history-next history)))))
