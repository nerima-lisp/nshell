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
    (is (member "--help" (completion-texts candidates)
                :test #'string=))))

(test type-command-flags-are-completed
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((candidates (nshell.domain.completion:complete
                       kb
                       "type --")))
      (is (member "--query" (completion-texts candidates)
                  :test #'string=))
      (is (member "--help" (completion-texts candidates)
                  :test #'string=)))
    (let ((candidates (nshell.domain.completion:complete
                       kb
                       "type -")))
      (is (member "-q" (completion-texts candidates)
                  :test #'string=))
      (is (member "-t" (completion-texts candidates)
                  :test #'string=)))))

(test builtin-command-metadata-follows-runtime-specs
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((string-collect (completion-texts
                           (nshell.domain.completion:complete kb "string co")))
          (string-repeat (completion-texts
                          (nshell.domain.completion:complete kb "string re")))
          (string-sub (completion-texts
                       (nshell.domain.completion:complete kb "string su")))
          (string-count (completion-texts
                         (nshell.domain.completion:complete kb "string --co")))
          (string-newline (completion-texts
                           (nshell.domain.completion:complete kb "string -N")))
          (alias-flags (completion-texts
                        (nshell.domain.completion:complete kb "alias -"))))
      (is (member "collect" string-collect :test #'string=))
      (is (member "replace" string-repeat :test #'string=))
      (is (member "repeat" string-repeat :test #'string=))
      (is (member "sub" string-sub :test #'string=))
      (is (member "--count" string-count :test #'string=))
      (is (member "-N" string-newline :test #'string=))
      (is (member "-e" alias-flags :test #'string=))
      (is (member "-q" alias-flags :test #'string=)))
    (is (equal '("--color=always" "--color=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "type --color=a"))))))

(test complete-command-flags-are-completed
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((long-options (completion-texts
                         (nshell.domain.completion:complete kb "complete --")))
          (short-options (completion-texts
                          (nshell.domain.completion:complete kb "complete -"))))
      (is (member "--long-option" long-options :test #'string=))
      (is (member "--short-option" long-options :test #'string=))
      (is (member "--arguments" long-options :test #'string=))
      (is (member "--erase" long-options :test #'string=))
      (is (member "-l" short-options :test #'string=))
      (is (member "-s" short-options :test #'string=))
      (is (member "-a" short-options :test #'string=))
      (is (member "-e" short-options :test #'string=)))))

(test command-completion-includes-type
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "ty")))
    (is (member "type" (completion-texts candidates)
                :test #'string=))
    (is (string= "show command type"
                 (nshell.domain.completion:candidate-description
                  (completion-candidate-by-text "type" candidates))))))

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
        (is (member text (completion-texts candidates)
                    :test #'string=)
            prefix)
        (is (string= description
                     (nshell.domain.completion:candidate-description
                      (completion-candidate-by-text text candidates)))
            prefix)))))

(test rule-completion-candidates-carry-descriptions
  (let* ((candidates (nshell.domain.completion:rule-complete
                      nshell.domain.completion::*built-in-rule-knowledge-base*
                      "git st"))
         (status (completion-candidate-by-text "status" candidates)))
    (is (not (null status)))
    (is (eq :option (nshell.domain.completion:candidate-kind status)))
    (is (string= "show working tree status"
                 (nshell.domain.completion:candidate-description status)))))

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
    (is (member "switch" subcommands :test #'string=))
    (is (member "pr" gh-subcommands :test #'string=))
    (is (member "--tls" flags :test #'string=))
    (is (member "--tlscert" flags :test #'string=))
    (is (member "--request" curl-flags :test #'string=))
    (is (member "--color" rg-flags :test #'string=))))

(test repl-completion-includes-common-external-option-values
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (is (equal '("--color=always" "--color=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "cargo --color=a"))))
    (is (equal '("-o=yaml")
               (completion-texts
                (nshell.domain.completion:complete kb "kubectl -o=y"))))
    (is (equal '("--request=DELETE")
               (completion-texts
                (nshell.domain.completion:complete kb "curl --request=D"))))
    (is (equal '("--color=always" "--color=ansi" "--color=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "rg --color=a"))))))

(test repl-completion-includes-common-external-separate-option-values
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (is (equal '("always" "auto")
               (completion-texts
                (nshell.domain.completion:complete kb "cargo --color a"))))
    (is (equal '("yaml")
               (completion-texts
                (nshell.domain.completion:complete kb "kubectl -o y"))))
    (is (equal '("DELETE")
               (completion-texts
                (nshell.domain.completion:complete kb "curl -X D"))))
    (is (equal '("always" "ansi" "auto")
               (completion-texts
                (nshell.domain.completion:complete kb "rg --color a"))))))

(test help-derived-command-metadata-feeds-knowledge-base-completion
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command-from-help
     kb
     "zz-helped"
     (format nil "Usage: zz-helped [OPTIONS]~%~
                  Options:~%~
                    -h, --help            Show help~%~
                    -o, --output FILE     Write output~%~
                        --color=WHEN      Color mode (always|auto|never)~%")
     :description "help-derived test command")
    (is (member "zz-helped"
                (completion-texts
                 (nshell.domain.completion:complete kb "zz-h"))
                :test #'string=))
    (is (member "--help"
                (completion-texts
                 (nshell.domain.completion:complete kb "zz-helped --h"))
                :test #'string=))
    (is (member "-o"
                (completion-texts
                 (nshell.domain.completion:complete kb "zz-helped -"))
                :test #'string=))
    (is (equal '("--color=always" "--color=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "zz-helped --color=a"))))
    (is (equal '("never")
               (completion-texts
                (nshell.domain.completion:complete kb "zz-helped --color n"))))))

(test repl-completion-hides-common-external-mutually-exclusive-options
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((after-quiet (completion-texts
                        (nshell.domain.completion:complete kb "cargo --quiet -"))))
      (is (not (member "--verbose" after-quiet :test #'string=)))
      (is (not (member "-v" after-quiet :test #'string=)))
      (is (member "--help" after-quiet :test #'string=)))
    (let ((after-all-namespaces
            (completion-texts
             (nshell.domain.completion:complete kb "kubectl --all-namespaces --"))))
      (is (not (member "--namespace" after-all-namespaces :test #'string=)))
      (is (member "--output" after-all-namespaces :test #'string=)))))

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
    (is (member "status" git-status :test #'string=))
    (is (member "--help" ls-help :test #'string=))))

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
    (is (member "status" (completion-texts candidates)
                :test #'string=))))

(test rule-completion-completes-command-after-leading-assignment-words
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "FOO=bar gi")))
    (is (member "git" (completion-texts candidates)
                :test #'string=))
    (is (not (member "status" (completion-texts candidates)
                     :test #'string=)))))

(test rule-completion-uses-current-pipeline-command
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "echo ready | git st")))
    (is (member "status" (completion-texts candidates)
                :test #'string=))))

(test rule-completion-treats-redirection-targets-as-files
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "git > st")))
    (is (= 1 (length candidates)))
    (is (string= "st" (nshell.domain.completion:candidate-text (first candidates))))
    (is (eq :file (nshell.domain.completion:candidate-kind (first candidates))))
    (is (not (member "status" (completion-texts candidates)
                     :test #'string=)))))

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
    (is (member "--help" (completion-texts candidates)
                :test #'string=))))

(test rule-completion-keeps-escaped-arguments-out-of-prefix
  (let ((candidates (nshell.domain.completion:rule-complete
                     nshell.domain.completion::*built-in-rule-knowledge-base*
                     "git add my\\ file st")))
    (is (member "status" (completion-texts candidates)
                :test #'string=))))
