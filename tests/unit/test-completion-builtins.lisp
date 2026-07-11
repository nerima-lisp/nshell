(in-package #:nshell/test)

(in-suite completion-rules-tests)

(test cd-completes-directories-integration
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "cd ")))
    (is (= 1 (length candidates)))
    (is (eq :directory (nshell.domain.completion:candidate-kind (first candidates))))))

(test command-flags-are-completed
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "ls --")))
    (assert-completion-texts-include candidates "--help")))

(test type-command-flags-are-completed
  (with-seeded-completion-knowledge-base (kb)
    (let ((candidates (nshell.domain.completion:complete
                       kb
                       "type --")))
      (assert-completion-texts-include candidates "--query" "--help"))
    (let ((candidates (nshell.domain.completion:complete
                       kb
                       "type -")))
      (assert-completion-texts-include candidates "-q" "-t"))))

(test builtin-command-metadata-follows-runtime-specs
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

(test complete-command-flags-are-completed
  (with-seeded-completion-knowledge-base (kb)
    (let ((long-options (completion-texts
                         (nshell.domain.completion:complete kb "complete --")))
          (short-options (completion-texts
                          (nshell.domain.completion:complete kb "complete -"))))
      (assert-texts-include long-options
        "--long-option" "--short-option" "--arguments" "--erase")
      (assert-texts-include short-options
        "-l" "-s" "-a" "-e"))))

(test command-completion-includes-type
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "ty")))
    (assert-completion-texts-include candidates "type")
    (assert-completion-candidate "type" candidates
                                 :kind :command
                                 :description "show command type")))

(test command-completion-includes-common-builtins
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
        (is (string= description
                     (nshell.domain.completion:candidate-description
                      (completion-candidate-by-text text candidates)))
            prefix)))))

(test rule-completion-candidates-carry-descriptions
  (let* ((candidates (nshell.domain.completion:rule-complete
                      nshell.domain.completion::*built-in-rule-knowledge-base*
                      "git st")))
    (assert-completion-candidate "status" candidates
                                 :kind :option
                                 :description "show working tree status")))

(test rule-completion-includes-common-external-command-metadata
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
    (is (not (null kubectl)))
    (is (string= "control Kubernetes clusters"
                 (nshell.domain.completion:candidate-description kubectl)))
    (assert-texts-include subcommands "switch")
    (assert-texts-include gh-subcommands "pr")
    (assert-texts-include flags "--tls" "--tlscert")
    (assert-texts-include curl-flags "--request")
    (assert-texts-include rg-flags "--color")))

(test repl-completion-includes-common-external-option-values
  (with-seeded-completion-knowledge-base (kb)
    (assert-completion-texts-cases kb
      (:input "cargo --color=a" :expected ("--color=always" "--color=auto"))
      (:input "kubectl -o=y" :expected ("-o=yaml"))
      (:input "curl --request=D" :expected ("--request=DELETE"))
      (:input "rg --color=a" :expected ("--color=always" "--color=ansi" "--color=auto")))))

(test repl-completion-includes-common-external-separate-option-values
  (with-seeded-completion-knowledge-base (kb)
    (assert-completion-texts-cases kb
      (:input "cargo --color a" :expected ("always" "auto"))
      (:input "kubectl -o y" :expected ("yaml"))
      (:input "curl -X D" :expected ("DELETE"))
      (:input "rg --color a" :expected ("always" "ansi" "auto")))))

(test help-derived-command-metadata-feeds-knowledge-base-completion
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
    (is (member "zz-helped"
                (completion-texts-for kb "zz-h")
                :test #'string=))
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

(test repl-completion-warms-command-help-and-reuses-the-cache
  (let ((help-text (format nil "Usage: zz-helped [OPTIONS]~%~
                                 Options:~%~
                                 -h, --help            Show help~%~
                                 -o, --output FILE     Write output~%~
                                 --color=WHEN      Color mode (always|auto|never)~%")))
    (with-repl-completion-help-fetcher (fetch-count help-text)
      (with-repl-completion-refresh (state candidates "zz-helped -")
        (declare (ignore state))
        (is (= 1 fetch-count))
        (assert-completion-candidate "--help" candidates :kind :option)
        (assert-completion-candidate "-o" candidates :kind :option))
      (with-repl-completion-refresh (state candidates "zz-helped --color a")
        (declare (ignore state))
        (is (= 1 fetch-count))
        (assert-completion-texts-include candidates "always" "auto")))))

(test repl-completion-enriches-catalogued-external-command-help
  (let ((help-text (format nil "Usage: git [OPTIONS] [COMMAND]~%~
                                 Options:~%~
                                 -h, --help            Show help~%~
                                 --dry-run        Preview changes without applying them~%")))
    (with-repl-completion-help-fetcher (fetch-count help-text)
      (with-repl-completion-refresh (state candidates "git --d")
        (declare (ignore state))
        (is (= 1 fetch-count))
        (assert-completion-candidate "--dry-run" candidates :kind :option)))))

(test repl-completion-caches-missing-command-help-lookups
  (with-repl-completion-help-fetcher
      (fetch-count "zz-missing: command completed without help metadata" :exit-code 1)
    (with-repl-completion-refresh (state candidates "zz-missing --")
      (declare (ignore state candidates))
      (is (= 1 fetch-count)))
    (with-repl-completion-refresh (state candidates "zz-missing --")
      (declare (ignore state candidates))
      (is (= 1 fetch-count)))))

(test repl-completion-hides-common-external-mutually-exclusive-options
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

(test builtin-rule-facts-are-single-sourced-from-catalogs
  (let ((seen (make-hash-table :test #'equal))
        (duplicates '()))
    (dolist (fact (nshell.domain.completion::builtin-rule-facts))
      (let ((key (prin1-to-string fact)))
        (if (gethash key seen)
            (pushnew key duplicates :test #'string=)
            (setf (gethash key seen) t))))
    (is (null duplicates) duplicates))
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

(test rule-completion-dedupes-multiple-proof-paths
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
      (is (equal '("status") (completion-texts candidates))))))

(test complete-uses-provided-rule-knowledge-base
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::completes
                                         :args '("zz-only" "--custom")))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::describes
                                         :args '("zz-only" "custom command")))
    (is (equal '("zz-only")
               (completion-texts
                (nshell.domain.completion:complete kb "zz-o"))))
    (is (equal '("--custom")
               (completion-texts
                (nshell.domain.completion:complete kb "zz-only --"))))
    (is (null (nshell.domain.completion:complete kb "git st")))))

(test rule-completion-skips-leading-assignment-words
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "FOO=bar git st")))
    (assert-completion-texts-include candidates "status")))

(test rule-completion-completes-command-after-leading-assignment-words
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "FOO=bar gi")))
    (assert-completion-texts-include candidates "git")
    (assert-completion-texts-exclude candidates "status")))

(test rule-completion-uses-current-pipeline-command
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "echo ready | git st")))
    (assert-completion-texts-include candidates "status")))

(test rule-completion-treats-redirection-targets-as-files
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "git > st")))
    (is (= 1 (length candidates)))
    (is (string= "st" (nshell.domain.completion:candidate-text (first candidates))))
    (is (eq :file (nshell.domain.completion:candidate-kind (first candidates))))
    (assert-completion-texts-exclude candidates "status")))

(test rule-completion-treats-empty-redirection-targets-as-files
  (dolist (line '("git >" "git > " "git >> " "git < "))
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       line)))
      (is (= 1 (length candidates)))
      (is (eq :file (nshell.domain.completion:candidate-kind (first candidates)))
          line))))

(test complete-redirection-targets-from-filesystem
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
      (is (equal '("staging/" "stderr.log" "stdout.txt") texts))
      (is (equal '(:directory :file :file) kinds)))))

(test complete-cd-targets-from-filesystem-directories-only
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
      (is (equal '("sandbox/" "src/") texts))
      (is (every (lambda (kind) (eq kind :directory)) kinds)))))

(test complete-source-targets-from-filesystem
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
        (is (equal '("included/" "init.lisp" "install.sh") texts) line)))))

(test complete-source-targets-from-filesystem-after-trailing-space
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
        (is (equal '("included/" "init.lisp" "install.sh" "readme.md") texts)
            line)))))

(test rule-completion-keeps-quoted-arguments-out-of-prefix
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "git commit -m \"hello world\" --")))
    (assert-completion-texts-include candidates "--help")))

(test rule-completion-keeps-escaped-arguments-out-of-prefix
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "git add my\\ file st")))
    (assert-completion-texts-include candidates "status")))
