(in-package #:nshell/test)

(describe "history-domain-tests"
  (it "history-navigation-reuses-original-prefix"
    "Repeated previous navigation keeps matching the prefix typed before cycling."
    (let ((history (history-with-lines "git commit" "grep needle" "git status")))
      (expect "git status" :to-equal (nshell.domain.history:history-previous history "git"))
      (expect "git commit" :to-equal (nshell.domain.history:history-previous history "git status"))))

  (it "history-navigation-next-restores-original-input"
    "Navigating down past the newest match restores the originally typed input."
    (let ((history (history-with-lines "git commit" "grep needle" "git status")))
      (expect "git status" :to-equal (nshell.domain.history:history-previous history "git"))
      (expect "git commit" :to-equal (nshell.domain.history:history-previous history "git status"))
      (expect "git status" :to-equal (nshell.domain.history:history-next history))
      (expect "git" :to-equal (nshell.domain.history:history-next history))
      (expect (nshell.domain.history:history-next history) :to-be-null)))

  (it "history-navigation-next-clears-stale-prefix"
    "Exhausting next navigation clears the previous prefix before a fresh search."
    (let ((history (history-with-lines "git commit" "grep needle" "git status")))
      (expect "git status" :to-equal (nshell.domain.history:history-previous history "git"))
      (expect "git" :to-equal (nshell.domain.history:history-next history))
      (expect (nshell.domain.history:history-next history) :to-be-null)
      (expect "grep needle" :to-equal (nshell.domain.history:history-previous history "grep"))))

  (it "history-reset-navigation-starts-next-search-from-current-prefix"
    "Resetting navigation lets the next previous search use the edited buffer."
    (let ((history (history-with-lines "git commit" "grep needle" "git status")))
      (expect "git status" :to-equal (nshell.domain.history:history-previous history "git"))
      (nshell.domain.history:history-reset-navigation history)
      (expect (nshell.domain.history:history-previous history "git status!") :to-be-null)))

  (it "history-navigation-matches-continuation-line-prefix"
    "Previous navigation matches prefixes at the beginning of any history line."
    (let ((history (history-with-lines "echo setup
git status"
                                       "printf 'not a prefix git'")))
      (expect "echo setup
git status" :to-equal (nshell.domain.history:history-previous history "git"))))

  (it "history-navigation-respects-smartcase"
    "Uppercase navigation prefixes match case-sensitively."
    (let ((history (history-with-lines "echo setup
git status"
                                       "Git status")))
      (expect "Git status" :to-equal (nshell.domain.history:history-previous history "Git"))
      (expect (nshell.domain.history:history-previous history "Git status") :to-be-null)))

  (it "history-navigation-handles-large-gapped-prefix-search"
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
      (expect "git newer" :to-equal (nshell.domain.history:history-previous history "git"))
      (expect "git old" :to-equal (nshell.domain.history:history-previous history "git newer"))
      (expect "git newer" :to-equal (nshell.domain.history:history-next history))
      (expect "git" :to-equal (nshell.domain.history:history-next history)))))
