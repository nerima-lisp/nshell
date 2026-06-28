(in-package #:nshell/test)
(in-suite builtin-tests)

(test read-stores-stdin-line-in-current-environment
  "read consumes one stdin line and stores it as a shell variable."
  (with-builtins-context (context)
    (with-input-from-string (*standard-input* (format nil "hello world~%"))
      (multiple-value-bind (output code) (call-builtin context "read" '("answer"))
        (is (null output))
        (is (= 0 code))))
    (is (string= "hello world"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "answer")))))

(test set-supports-fish-style-options-and-multiple-values
  "set supports fish-style export, erase, query, listing, and multi-token values."
  (with-builtins-context (context)
    (assert-builtin-cases (context "set")
      (("--export" "NSHELL_TEST_EXPORTED" "one" "two")
       :code 0
       :output-null t)
      (("NSHELL_TEST_LOCAL" "alpha" "beta")
       :code 0
       :output-null t)
      (("NSHELL_TEST_EMPTY")
       :code 0
       :output-null t))
    (let ((env (nshell.application:shell-context-environment context)))
      (is (string= "one two"
                   (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED")))
      (is (equal '("one" "two")
                 (nshell.domain.environment:env-get-values env "NSHELL_TEST_EXPORTED")))
      (is (string= "alpha beta"
                   (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL")))
      (is (equal '("alpha" "beta")
                 (nshell.domain.environment:env-get-values env "NSHELL_TEST_LOCAL")))
      (is (string= ""
                   (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY")))
      (is (null (nshell.domain.environment:env-get-values env "NSHELL_TEST_EMPTY")))
      (is (equal '("NSHELL_TEST_EXPORTED" . "one two")
                 (assoc "NSHELL_TEST_EXPORTED"
                        (nshell.domain.environment:env-list env)
                        :test #'string=))))
    (assert-builtin-cases (context "set")
      (("--query" "NSHELL_TEST_EXPORTED" "NSHELL_TEST_LOCAL")
       :code 0
       :output-null t)
      (("--query" "NSHELL_TEST_MISSING")
       :code 1
       :output-null t)
      (nil
       :code 0
       :contains '("set -x NSHELL_TEST_EXPORTED one two"
                   "set NSHELL_TEST_LOCAL alpha beta"
                   "set NSHELL_TEST_EMPTY "))
      (("--erase"
        "NSHELL_TEST_EXPORTED"
        "NSHELL_TEST_LOCAL"
        "NSHELL_TEST_EMPTY")
       :code 0
       :output-null t))
    (let ((env (nshell.application:shell-context-environment context)))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED")))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL")))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY"))))))

(test alias-adds-lists-queries-and-erases-expansions
  "alias stores fish-style multi-token command expansions in the current context."
  (with-builtins-context (context)
    (assert-fish-style-table-builtin-roundtrip
        (context "alias" (nshell.application:shell-context-alias-table context)
                 "ll" "ls -l /tmp" '("ll" "ls" "-l" "/tmp")
                 "alias ll=ls -l /tmp"
                 "alias: -e requires a name
"
                 '("-e" "ll")
                 "missing"))))

(test alias-accepts-inline-name-value-assignment
  "alias accepts the familiar name=value form while preserving remaining tokens."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "alias" '("gs=git" "status" "--short"))
      (is (null output))
      (is (= 0 code)))
    (is (string= "git status --short"
                 (gethash "gs"
                          (nshell.application:shell-context-alias-table
                           context))))))

(test source-expands-multi-token-aliases-from-context
  "source execution expands aliases before dispatching commands."
  (with-builtins-context (context)
    (call-builtin context "alias" '("say" "echo" "from" "alias"))
    (with-called-source (output code context '("say script"))
      (is (= 0 code))
      (is (string= (format nil "from alias script~%") output)))))

(test abbr-adds-lists-queries-and-erases-expansions
  "abbr stores fish-style multi-token expansions in the current shell context."
  (with-builtins-context (context)
    (assert-fish-style-table-builtin-roundtrip
        (context "abbr" (nshell.application:shell-context-abbreviation-table context)
                 "gco" "git checkout" '("-a" "gco" "git" "checkout")
                 "abbr -a gco git checkout"
                 "abbr: -e requires a name
"
                 '("-e" "gco")
                 "missing"))))

(test abbr-accepts-fish-style-long-options
  "abbr accepts long option names for add, query, list, show, and erase."
  (with-builtins-context (context)
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--add" "gst" "git" "status")))))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--query" "gst")))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--list"))
      (is (= 0 code))
      (is (search "gst" output))
      (is (not (search "git status" output))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a gst git status" output)))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--erase" "gst")))))
    (is (= 1 (nth-value 1 (call-builtin context "abbr"
                                         '("--query" "gst")))))))

(test abbr-adds-position-scoped-expansions
  "abbr stores optional fish-style position metadata for expansion-time checks."
  (with-builtins-context (context)
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--add" "--position" "command"
                                           "gco" "git" "checkout")))))
    (let ((value (gethash "gco"
                          (nshell.application:shell-context-abbreviation-table
                           context))))
      (is (nshell.domain.abbreviation:abbreviation-p value))
      (is (string= "git checkout"
                   (nshell.domain.abbreviation:abbreviation-expansion value)))
      (is (eq :command
              (nshell.domain.abbreviation:abbreviation-position value))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a --position command gco git checkout" output)))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("-a" "-p" "anywhere"
                                           "gst" "git" "status")))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a --position anywhere gst git status" output)))))

(test abbr-rejects-invalid-position-option
  "abbr rejects missing or unknown --position values."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "abbr" '("-a" "--position" "middle"
                                       "gco" "git" "checkout"))
      (is (= 2 code))
      (is (search "command or anywhere" output)))
    (multiple-value-bind (output code)
        (call-builtin context "abbr" '("-a" "-p"))
      (is (= 2 code))
      (is (search "requires" output)))))

(test complete-builtin-adds-command-and-argument-completions
  "complete updates the session knowledge base used by interactive completion."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "complete"
                      '("-c" "deploy" "-f" "--dry-run" "-f" "--target"
                        "-d" "release service"))
      (is (null output))
      (is (= 0 code)))
    (multiple-value-bind (output code)
        (call-builtin context "complete"
                      '("--command" "deploy" "--flag" "--dry-run"
                        "--flag" "--target" "--description" "release service"))
      (is (null output))
      (is (= 0 code)))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (command (find "deploy"
                          (nshell.domain.completion:complete kb "dep")
                          :key #'nshell.domain.completion:candidate-text
                          :test #'string=))
           (arguments (mapcar #'nshell.domain.completion:candidate-text
                              (nshell.domain.completion:complete kb "deploy --"))))
      (is (not (null command)))
      (is (string= "release service"
                   (nshell.domain.completion:candidate-description command)))
      (is (equal '("--dry-run" "--target") arguments)))
    (multiple-value-bind (output code)
        (call-builtin context "complete"
                      '("-c" "deploy" "-l" "color" "-s" "o"
                        "-a" "always auto never"))
      (is (null output))
      (is (= 0 code)))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (candidates (nshell.domain.completion:complete kb "deploy --color=")))
      (is (equal '("--color=always" "--color=auto" "--color=never")
                 (mapcar #'nshell.domain.completion:candidate-text candidates))))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (candidates (nshell.domain.completion:complete kb "deploy --color a")))
      (is (equal '("always" "auto")
                 (mapcar #'nshell.domain.completion:candidate-text candidates))))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (candidates (nshell.domain.completion:complete kb "deploy -o n")))
      (is (equal '("never")
                 (mapcar #'nshell.domain.completion:candidate-text candidates))))))

(test complete-builtin-rejects-missing-command
  "complete requires an explicit command name."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "complete" '("-f" "--bad"))
      (is (= 1 code))
      (is (search "usage" output)))))

(test complete-builtin-erases-command-completions
  "complete -e removes session completion metadata for a command."
  (with-builtins-context (context)
    (let ((command "__nshell-deploy"))
      (multiple-value-bind (output code)
          (call-builtin context "complete"
                        (list "-c" command "-f" "--dry-run"
                              "-l" "color" "-a" "always auto"
                              "-d" "test-only deploy command"))
        (is (null output))
        (is (= 0 code)))
      (let ((kb (nshell.application:shell-context-knowledge-base context)))
        (is (not (null (nshell.domain.completion:kb-query kb command)))))
      (multiple-value-bind (output code)
          (call-builtin context "complete" (list "-c" command "--erase"))
        (is (null output))
        (is (= 0 code)))
      (let ((kb (nshell.application:shell-context-knowledge-base context)))
        (is (null (nshell.domain.completion:kb-query kb command)))
        (is (not (member command
                         (mapcar #'nshell.domain.completion:candidate-text
                                 (nshell.domain.completion:complete
                                  kb "__nshell-"))
                         :test #'string=)))))))

(test complete-builtin-rejects-missing-arguments
  "complete reports missing arguments for each required option."
  (with-builtins-context (context)
    (assert-builtin-cases (context "complete")
      (("-c") :code 2 :output (format nil "complete: -c requires command~%"))
      (("--command") :code 2 :output (format nil "complete: --command requires command~%"))
      (("-f") :code 2 :output (format nil "complete: -f requires flag~%"))
      (("--flag") :code 2 :output (format nil "complete: --flag requires flag~%"))
      (("-l") :code 2 :output (format nil "complete: -l requires option~%"))
      (("--long-option") :code 2 :output (format nil "complete: --long-option requires option~%"))
      (("-s") :code 2 :output (format nil "complete: -s requires option~%"))
      (("--short-option") :code 2 :output (format nil "complete: --short-option requires option~%"))
      (("-a") :code 2 :output (format nil "complete: -a requires arguments~%"))
      (("--arguments") :code 2 :output (format nil "complete: --arguments requires arguments~%"))
      (("-d") :code 2 :output (format nil "complete: -d requires description~%"))
      (("--description") :code 2 :output (format nil "complete: --description requires description~%")))))

(test function-builtin-stores-and-manages-inline-body
  "function builtin stores inline fish-style bodies and exposes management operations."
  (with-builtins-context (context)
    (assert-fish-style-table-builtin-roundtrip
        (context "function" (nshell.application:shell-context-function-table context)
                 "hi" '("echo hello")
                 '("hi" "echo" "hello" "end")
                 "function hi"
                 "function: -e requires a name
"
                 '("-e" "hi")
                 "missing"
                 :body-contains ("  echo hello" "end")))))

(test history-builtin-searches-deletes-clears-and-reports-size
  "history builtin exposes fish-style in-memory history management."
  (let* ((context (make-test-builtins-context))
         (history (nshell.application:shell-context-history context)))
    (nshell.domain.history:history-add history "Git status")
    (nshell.domain.history:history-add history "git status")
    (nshell.domain.history:history-add history "docker ps")
    (nshell.domain.history:history-add history "git commit")
    (nshell.domain.history:history-add history "git status --short")
    (assert-builtin-cases (context "history")
      (nil :code 0 :output (format nil "Git status~%git status~%docker ps~%git commit~%git status --short~%"))
      ('("search" "git") :code 0 :output (format nil "git status --short~%git commit~%git status~%Git status~%"))
      ('("search" "--prefix" "git") :code 0 :output (format nil "git status --short~%git commit~%git status~%Git status~%"))
      ('("search" "--case-sensitive" "git") :code 0
       :output (format nil "git status --short~%git commit~%git status~%"))
      ('("search" "--contains" "status --") :code 0
       :output (format nil "git status --short~%"))
      ('("search" "--exact" "--case-sensitive" "Git status") :code 0
       :output (format nil "Git status~%"))
      ('("delete" "docker" "ps") :code 0 :output (format nil "1~%"))
      ('("size") :code 0 :output (format nil "4~%"))
      ('("clear") :code 0 :output-null t)
      ('("bogus") :code 1
       :output (format nil "history: usage: history [search [--prefix|--contains|--exact|--case-sensitive] query | delete command | clear | size]~%")))
    (is (= 0 (nshell.domain.history:history-size history)))))
