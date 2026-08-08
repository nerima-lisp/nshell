(in-package #:nshell/test)

(describe "completion-rules-tests"
  (it "cd-completes-directories-integration"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "cd ")))
      (expect 1 :to-equal (length candidates))
      (expect :directory :to-be (nshell.domain.completion:candidate-kind (first candidates)))))

  (it "command-flags-are-completed"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "ls --")))
      (assert-completion-texts-include candidates "--help")))

  (it "type-command-flags-are-completed"
    (with-seeded-completion-knowledge-base (kb)
      (let ((candidates (nshell.domain.completion:complete
                         kb
                         "type --")))
        (assert-completion-texts-include candidates "--query" "--help"))
      (let ((candidates (nshell.domain.completion:complete
                         kb
                         "type -")))
        (assert-completion-texts-include candidates "-q" "-t"))))

  (it "builtin-command-metadata-follows-runtime-specs"
    (with-seeded-completion-knowledge-base (kb)
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string co")
        "collect")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string re")
        "replace" "repeat")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string su")
        "sub")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string --co")
        "--count")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string -N")
        "-N")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "alias -")
        "-e" "-q")
      (assert-completion-texts-for
          '("--color=always" "--color=auto")
          kb
          "type --color=a")))

  (it "complete-command-flags-are-completed"
    (with-seeded-completion-knowledge-base (kb)
      (let ((long-options (completion-texts
                           (nshell.domain.completion:complete kb "complete --")))
            (short-options (completion-texts
                            (nshell.domain.completion:complete kb "complete -"))))
        (assert-texts-include long-options
          "--long-option" "--short-option" "--arguments" "--erase")
        (assert-texts-include short-options
          "-l" "-s" "-a" "-e"))))

  (it "command-completion-includes-type"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "ty")))
      (assert-completion-texts-include candidates "type")
      (assert-completion-candidate "type" candidates
                                   :kind :command
                                   :description "show command type")))

  (it "command-completion-includes-common-builtins"
    (dolist (case '(("he" "help" "show help")
                    ("his" "history" "show and manage command history")
                    ("str" "string" "manipulate strings")
                    ("ec" "echo" "print arguments")
                    ("pw" "pwd" "print working directory")
                    ("ex" "exit" "exit the shell")
                    ("so" "source" "execute commands from file")
                    ("re" "read" "read line of input")
                    ("fu" "function" "manage functions")
                    ("co" "contains" "test whether a value is present")
                    ("no" "not" "invert command status")))
      (destructuring-bind (prefix text description) case
        (let ((candidates (nshell.domain.completion:rule-complete
                           nshell.domain.completion::*built-in-rule-knowledge-base*
                           prefix)))
          (assert-completion-texts-include candidates text)
                        (expect description :to-equal (nshell.domain.completion:candidate-description
                        (completion-candidate-by-text text candidates)))))))

  (it "command-completion-includes-runtime-aliases-and-functions"
    (let ((aliases (make-hash-table :test #'equal))
          (functions (make-hash-table :test #'equal)))
      (setf (gethash "ll" aliases) "ls -l"
            (gethash "local-tool" functions) "() { echo ok; }")
      (let ((candidates
              (nshell.domain.completion:complete
               (nshell.domain.completion:make-empty-knowledge-base)
               "l"
               :alias-table aliases
               :function-table functions)))
        (assert-completion-candidate "ll" candidates
                                     :kind :command
                                     :description "alias")
        (assert-completion-candidate "local-tool" candidates
                                     :kind :command
                                     :description "function"))))

  (it "rule-completion-candidates-carry-descriptions"
    (let* ((candidates (nshell.domain.completion:rule-complete
                        nshell.domain.completion::*built-in-rule-knowledge-base*
                        "git st")))
      (assert-completion-candidate "status" candidates
                                   :kind :option
                                   :description "show working tree status")))

  (it "rule-completion-includes-common-external-command-metadata"
    (let* ((commands (nshell.domain.completion:rule-complete
                      nshell.domain.completion::*built-in-rule-knowledge-base*
                      "ku"))
           (kubectl (completion-candidate-by-text "kubectl" commands))
           (subcommands (completion-texts
                         (nshell.domain.completion:rule-complete
                          nshell.domain.completion::*built-in-rule-knowledge-base*
                          "git sw")))
           (gh-subcommands (completion-texts
                            (nshell.domain.completion:rule-complete
                             nshell.domain.completion::*built-in-rule-knowledge-base*
                             "gh pr")))
           (flags (completion-texts
                   (nshell.domain.completion:rule-complete
                    nshell.domain.completion::*built-in-rule-knowledge-base*
                    "docker --t")))
           (curl-flags (completion-texts
                        (nshell.domain.completion:rule-complete
                         nshell.domain.completion::*built-in-rule-knowledge-base*
                         "curl --req")))
           (rg-flags (completion-texts
                      (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "rg --colo"))))
      (expect (null kubectl) :to-be-falsy)
      (expect "control Kubernetes clusters" :to-equal (nshell.domain.completion:candidate-description kubectl))
      (assert-texts-include subcommands "switch")
      (assert-texts-include gh-subcommands "pr")
      (assert-texts-include flags "--tls" "--tlscert")
      (assert-texts-include curl-flags "--request")
      (assert-texts-include rg-flags "--color")))

  (it "repl-completion-includes-common-external-option-values"
    (with-seeded-completion-knowledge-base (kb)
      (assert-completion-texts-cases kb
        (:input "cargo --color=a" :expected ("--color=always" "--color=auto"))
        (:input "kubectl -o=y" :expected ("-o=yaml"))
        (:input "curl --request=D" :expected ("--request=DELETE"))
        (:input "rg --color=a" :expected ("--color=always" "--color=ansi" "--color=auto")))))

  (it "repl-completion-includes-common-external-separate-option-values"
    (with-seeded-completion-knowledge-base (kb)
      (assert-completion-texts-cases kb
        (:input "cargo --color a" :expected ("always" "auto"))
        (:input "kubectl -o y" :expected ("yaml"))
        (:input "curl -X D" :expected ("DELETE"))
        (:input "rg --color a" :expected ("always" "ansi" "auto")))))

  (it "help-derived-command-metadata-feeds-knowledge-base-completion"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command-from-help
       kb
       "zz-helped"
       (format nil "Usage: zz-helped [OPTIONS] <COMMAND>~%~
                  Commands:~%~
                    run                   execute the task~%~
                    test                  verify the task~%~
                  Options:~%~
                    -h, --help            Show help~%~
                    -o, --output FILE     Write output~%~
                        --color=WHEN      Color mode (always|auto|never)~%")
       :description "help-derived test command")
      (expect (member "zz-helped"
                  (completion-texts-for kb "zz-h")
                  :test #'string=) :to-be-truthy)
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped r")
        "run")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped t")
        "test")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped --h")
        "--help")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped -")
        "-o")
      (assert-completion-texts-cases kb
        (:input "zz-helped --color=a" :expected ("--color=always" "--color=auto"))
        (:input "zz-helped --color n" :expected ("never")))))

  (it "repl-completion-warms-catalogued-command-help-and-reuses-the-cache"
    (let ((help-text (format nil "Usage: cargo [OPTIONS]~%~
                                 Options:~%~
                                 -h, --help            Show help~%~
                                 -o, --output FILE     Write output~%~
                                 --color=WHEN      Color mode (always|auto|never)~%")))
      (with-repl-completion-help-fetcher (fetch-count help-text)
        (with-repl-completion-refresh (state candidates "cargo -")
          (declare (ignore state))
          (expect 1 :to-equal fetch-count)
          (assert-completion-candidate "--help" candidates :kind :option)
          (assert-completion-candidate "-o" candidates :kind :option))
        (with-repl-completion-refresh (state candidates "cargo --color a")
          (declare (ignore state))
          (expect 1 :to-equal fetch-count)
          (assert-completion-texts-include candidates "always" "auto")))))

  (it "repl-completion-enriches-catalogued-external-command-help"
    (let ((help-text (format nil "Usage: git [OPTIONS] [COMMAND]~%~
                                 Options:~%~
                                 -h, --help            Show help~%~
                                 --dry-run        Preview changes without applying them~%")))
      (with-repl-completion-help-fetcher (fetch-count help-text)
        (with-repl-completion-refresh (state candidates "git --d")
          (declare (ignore state))
          (expect 1 :to-equal fetch-count)
          (assert-completion-candidate "--dry-run" candidates :kind :option)))))

  (it "repl-completion-caches-missing-command-help-lookups"
    (let ((catalog (make-hash-table :test #'equal)))
      (setf (gethash "zz-missing" catalog) t)
      (let ((nshell.presentation::*completion-help-catalog-command-cache* catalog))
        (with-repl-completion-help-fetcher
            (fetch-count "zz-missing: command completed without help metadata" :exit-code 1)
          (with-repl-completion-refresh (state candidates "zz-missing --")
            (declare (ignore state candidates))
            (expect 1 :to-equal fetch-count))
          (with-repl-completion-refresh (state candidates "zz-missing --")
            (declare (ignore state candidates))
            (expect 1 :to-equal fetch-count))))))

  (it "repl-completion-does-not-fetch-help-for-uncatalogued-commands"
    (with-repl-completion-help-fetcher
        (fetch-count "Usage: should-not-run")
      (with-repl-completion-refresh (state candidates "zz-uncatalogued --")
        (declare (ignore state candidates))
        (expect 0 :to-equal fetch-count))))

  (it "repl-completion-rejects-oversized-help-output-before-parsing"
    (with-repl-test-state
      (let ((nshell.presentation::*completion-help-max-output-chars* 16)
            (help-text (format nil "Usage: zz-large~%~a"
                               (make-string 32 :initial-element #\x))))
        (expect :missing :to-equal
          (nshell.presentation::%completion-help-cache-help-text
           "zz-large" help-text 0))
        (expect nil :to-be
          (nshell.domain.completion:kb-command-present-p
           nshell.presentation::*kb* "zz-large")))))

  (it "repl-completion-does-not-fetch-help-for-unavailable-commands"
    (with-repl-completion-help-fetcher
        (fetch-count "Usage: should-not-run"
         :command-available-p
         (function
           (lambda (command)
             (declare (ignore command))
             nil)))
      (with-repl-completion-refresh (state candidates "zz-unavailable --")
        (declare (ignore state candidates))
        (expect 0 :to-equal fetch-count))))

  (it "repl-completion-hides-common-external-mutually-exclusive-options"
    (with-seeded-completion-knowledge-base (kb)
      (let ((after-quiet (completion-texts
                          (nshell.domain.completion:complete kb "cargo --quiet -"))))
        (assert-texts-exclude after-quiet "--verbose" "-v")
        (assert-texts-include after-quiet "--help"))
      (let ((after-all-namespaces
              (completion-texts
               (nshell.domain.completion:complete kb "kubectl --all-namespaces --"))))
        (assert-texts-exclude after-all-namespaces "--namespace")
        (assert-texts-include after-all-namespaces "--output"))))

  (it "builtin-rule-facts-are-single-sourced-from-catalogs"
    (let ((seen (make-hash-table :test #'equal))
          (duplicates '()))
      (dolist (fact (nshell.domain.completion::builtin-rule-facts))
        (let ((key (prin1-to-string fact)))
          (if (gethash key seen)
              (pushnew key duplicates :test #'string=)
              (setf (gethash key seen) t))))
      (expect duplicates :to-be-null))
    (let ((git-status (completion-texts
                       (nshell.domain.completion:rule-complete
                        nshell.domain.completion::*built-in-rule-knowledge-base*
                        "git st")))
          (ls-help (completion-texts
                    (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "ls --"))))
      (assert-texts-include git-status "status")
      (assert-texts-include ls-help "--help")))

  (it "rule-completion-dedupes-multiple-proof-paths"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::completes
                                           :args '("git" "status")))
      (nshell.domain.completion:assert-rule!
       kb
       (nshell.domain.completion:make-rule :head '(nshell.domain.completion::completes
                                                   "git"
                                                   "status")
                                           :body '()))
      (let ((candidates (nshell.domain.completion:rule-complete kb "git st")))
        (expect '("status") :to-equal (completion-texts candidates)))))

  (it "complete-uses-provided-rule-knowledge-base"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::completes
                                           :args '("zz-only" "--custom")))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::describes
                                           :args '("zz-only" "custom command")))
      (expect '("zz-only") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "zz-o")))
      (expect '("--custom") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "zz-only --")))
      (expect (nshell.domain.completion:complete kb "git st") :to-be-null)))

  (it "rule-completion-skips-leading-assignment-words"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "FOO=bar git st")))
      (assert-completion-texts-include candidates "status")))

  (it "rule-completion-completes-command-after-leading-assignment-words"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "FOO=bar gi")))
      (assert-completion-texts-include candidates "git")
      (assert-completion-texts-exclude candidates "status")))

  (it "rule-completion-uses-current-pipeline-command"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "echo ready | git st")))
      (assert-completion-texts-include candidates "status")))

  (it "rule-completion-treats-redirection-targets-as-files"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "git > st")))
      (expect 1 :to-equal (length candidates))
      (expect "st" :to-equal (nshell.domain.completion:candidate-text (first candidates)))
      (expect :file :to-be (nshell.domain.completion:candidate-kind (first candidates)))
      (assert-completion-texts-exclude candidates "status")))

  (it "rule-completion-treats-empty-redirection-targets-as-files"
    (dolist (line '("git >" "git > " "git >> " "git < "))
      (let ((candidates (nshell.domain.completion:rule-complete
                         nshell.domain.completion::*built-in-rule-knowledge-base*
                         line)))
        (expect 1 :to-equal (length candidates))
        (expect :file :to-be (nshell.domain.completion:candidate-kind (first candidates))))))

  (it "complete-redirection-targets-from-filesystem"
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"stderr.log" #p"stdout.txt" #p"notes.txt"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"staging/")))
      (let* ((candidates (nshell.domain.completion:complete
                          nshell.domain.completion::*built-in-rule-knowledge-base*
                          "echo > st"))
             (texts (completion-texts candidates))
             (kinds (mapcar #'nshell.domain.completion:candidate-kind candidates)))
        (expect '("staging/" "stderr.log" "stdout.txt") :to-equal texts)
        (expect '(:directory :file :file) :to-equal kinds))))

  (it "complete-cd-targets-from-filesystem-directories-only"
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"src.log"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"src/" #p"sandbox/")))
      (let* ((candidates (nshell.domain.completion:complete
                          nshell.domain.completion::*built-in-rule-knowledge-base*
                          "cd s"))
             (texts (completion-texts candidates))
             (kinds (mapcar #'nshell.domain.completion:candidate-kind candidates)))
        (expect '("sandbox/" "src/") :to-equal texts)
        (expect (every (lambda (kind) (eq kind :directory)) kinds) :to-be-truthy))))

  (it "complete-path-like-command-arguments-from-filesystem"
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p".env" #p"~config" #p"main.lisp"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"module/")))
      (let ((slash-texts
              (completion-texts
               (nshell.domain.completion:complete
                nshell.domain.completion::*built-in-rule-knowledge-base*
                "echo src/m")))
            (dot-texts
              (completion-texts
               (nshell.domain.completion:complete
                nshell.domain.completion::*built-in-rule-knowledge-base*
                "echo .e")))
            (tilde-texts
              (completion-texts
               (nshell.domain.completion:complete
                nshell.domain.completion::*built-in-rule-knowledge-base*
                "echo ~c"))))
        (expect '("src/module/" "src/main.lisp") :to-equal slash-texts)
        (expect '(".env") :to-equal dot-texts)
        (expect '("~config") :to-equal tilde-texts))))

  (it "complete-source-targets-from-filesystem"
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"init.lisp" #p"install.sh" #p"readme.md"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"included/")))
      (dolist (line '("source in" ". in"))
        (let ((texts (completion-texts
                      (nshell.domain.completion:complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       line))))
          (expect '("included/" "init.lisp" "install.sh") :to-equal texts)))))

  (it "complete-source-targets-from-filesystem-after-trailing-space"
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"init.lisp" #p"install.sh" #p"readme.md"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"included/")))
      (dolist (line '("source " ". "))
        (let ((texts (completion-texts
                      (nshell.domain.completion:complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       line))))
          (expect '("included/" "init.lisp" "install.sh" "readme.md") :to-equal texts)))))

  (it "rule-completion-keeps-quoted-arguments-out-of-prefix"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "git commit -m \"hello world\" --")))
      (assert-completion-texts-include candidates "--help")))

  (it "rule-completion-keeps-escaped-arguments-out-of-prefix"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "git add my\\ file st")))
      (assert-completion-texts-include candidates "status")))

  (it "rule-completion-preserves-descriptions-for-multiple-candidates"
    (let ((kb (make-empty-rule-kb)))
      (dolist (command (quote ("git" "gitk")))
        (nshell.domain.completion:assert-fact!
          kb
          (nshell.domain.completion:make-fact
            :predicate (quote nshell.domain.completion:completes)
            :args (list command ""))))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate (quote nshell.domain.completion:describes)
          :args (quote ("git" "version control"))))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate (quote nshell.domain.completion:describes)
          :args (quote ("gitk" "graphical history browser"))))
      (let ((candidates (nshell.domain.completion:rule-complete kb "git")))
        (expect (quote ("git" "gitk")) :to-equal (completion-texts candidates))
        (expect "version control" :to-equal
          (nshell.domain.completion:candidate-description (first candidates)))
        (expect "graphical history browser" :to-equal
          (nshell.domain.completion:candidate-description (second candidates))))))
)
