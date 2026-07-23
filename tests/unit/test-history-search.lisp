(in-package #:nshell/test)

(describe "history-domain-tests"
  (it "history-prefix-search"
    "Prefix search finds matching entries."
    (let* ((history (history-with-lines "git status" "git push" "ls -la"))
           (results (nshell.domain.history:history-search history "git" :mode :prefix)))
      (expect 2 :to-equal (length results))))

  (it "history-contains-search"
    "Contains search finds substring matches."
    (let* ((history (history-with-lines "docker-compose up" "docker ps" "ls"))
           (results (nshell.domain.history:history-search history "docker" :mode :contains)))
      (expect 2 :to-equal (length results))))

  (it "history-line-prefix-search-matches-continuation-lines"
    "Line-prefix search finds matches after a newline in a multi-line entry."
      (let* ((history (history-with-lines "echo setup
git status"
                                        "printf 'not a prefix git'"
                                        "git push"))
           (results (nshell.domain.history:history-search history "git" :mode :line-prefix)))
      (expect '("git push" "echo setup
git status") :to-equal (nshell.domain.history:history-entry-texts results))))

  (it "history-line-prefix-search-respects-smartcase"
    "Line-prefix smartcase keeps uppercase queries case-sensitive."
      (let* ((history (history-with-lines "echo setup
git status"
                                        "Git status"))
           (results (nshell.domain.history:history-search history "Git"
                                                          :mode :line-prefix
                                                          :smartcase t)))
      (expect '("Git status") :to-equal (nshell.domain.history:history-entry-texts results))))

  (it "history-smartcase"
    "Smartcase makes uppercase queries case-sensitive."
    (let* ((history (history-with-lines "Git Status" "git push"))
           (results (nshell.domain.history:history-search history "Git"
                                                          :mode :prefix
                                                          :smartcase t)))
      (expect 1 :to-equal (length results))
      (expect "Git Status" :to-equal (nshell.domain.history:entry-text (first results))))))
