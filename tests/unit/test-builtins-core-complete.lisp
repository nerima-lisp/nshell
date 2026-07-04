(in-package #:nshell/test)
(in-suite builtin-tests)

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
        (is (nshell.domain.completion:kb-command-present-p kb command)))
      (multiple-value-bind (output code)
          (call-builtin context "complete" (list "-c" command "--erase"))
        (is (null output))
        (is (= 0 code)))
      (let ((kb (nshell.application:shell-context-knowledge-base context)))
        (is (not (nshell.domain.completion:kb-command-present-p kb command)))
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
