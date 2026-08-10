(in-package #:nshell/test)

(describe "builtin-tests"
  (it "complete-builtin-adds-command-and-argument-completions"
    "complete updates the session knowledge base used by interactive completion."
    (with-builtins-context (context)
      (assert-builtin-call (context "complete"
                                 '("-c" "deploy" "-f" "--dry-run" "-f" "--target"
                                   "-d" "release service"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "complete"
                                 '("--command" "deploy" "--flag" "--dry-run"
                                   "--flag" "--target" "--description" "release service"))
        :code 0
        :output-null t)
      (let* ((kb (nshell.application:shell-context-knowledge-base context))
             (command (find "deploy"
                            (nshell.domain.completion:complete kb "dep")
                            :key #'nshell.domain.completion:candidate-text
                            :test #'string=))
             (arguments (mapcar #'nshell.domain.completion:candidate-text
                                (nshell.domain.completion:complete kb "deploy --"))))
        (expect (null command) :to-be-falsy)
        (expect "release service" :to-equal (nshell.domain.completion:candidate-description command))
        (expect '("--dry-run" "--target") :to-equal arguments))
      (assert-builtin-call (context "complete"
                                 '("-c" "deploy" "-l" "color" "-s" "o"
                                   "-a" "always auto never"))
        :code 0
        :output-null t)
      (let* ((kb (nshell.application:shell-context-knowledge-base context))
             (candidates (nshell.domain.completion:complete kb "deploy --color=")))
        (expect '("--color=always" "--color=auto" "--color=never") :to-equal (mapcar #'nshell.domain.completion:candidate-text candidates)))
      (let* ((kb (nshell.application:shell-context-knowledge-base context))
             (candidates (nshell.domain.completion:complete kb "deploy --color a")))
        (expect '("always" "auto") :to-equal (mapcar #'nshell.domain.completion:candidate-text candidates)))
      (let* ((kb (nshell.application:shell-context-knowledge-base context))
             (candidates (nshell.domain.completion:complete kb "deploy -o n")))
        (expect '("never") :to-equal (mapcar #'nshell.domain.completion:candidate-text candidates)))))

  (it "complete-builtin-rejects-missing-command"
    "complete requires an explicit command name."
    (with-builtins-context (context)
      (assert-builtin-call (context "complete" '("-f" "--bad"))
        :code 1
        :contains '("usage"))))

  (it "complete-builtin-erases-command-completions"
    "complete -e removes session completion metadata for a command."
    (with-builtins-context (context)
      (let ((command "__nshell-deploy"))
        (assert-builtin-call (context "complete"
                                   (list "-c" command "-f" "--dry-run"
                                         "-l" "color" "-a" "always auto"
                                         "-d" "test-only deploy command"))
          :code 0
          :output-null t)
        (let ((kb (nshell.application:shell-context-knowledge-base context)))
          (expect (nshell.domain.completion:kb-command-present-p kb command) :to-be-truthy))
        (assert-builtin-call (context "complete" (list "-c" command "--erase"))
          :code 0
          :output-null t)
        (let ((kb (nshell.application:shell-context-knowledge-base context)))
          (expect (nshell.domain.completion:kb-command-present-p kb command) :to-be-falsy)
          (expect (member command
                           (mapcar #'nshell.domain.completion:candidate-text
                                   (nshell.domain.completion:complete
                                    kb "__nshell-"))
                           :test #'string=) :to-be-falsy)))))

  (it "complete-builtin-rejects-missing-arguments"
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
  (it "complete-builtin-parses-option-terminator-and-rejects-unknown-options"
    "complete stops option parsing at -- and reports unknown options before command finalization."
    (with-builtins-context (context)
      (assert-builtin-call
       (context "complete" (list "-c" "deploy" "--" "ignored"))
       :code 0 :output-null t)
      (assert-builtin-call
       (context "complete" (list "-c" "deploy" "--unknown"))
       :code 2
       :contains (list "complete: unknown option --unknown"))
      (assert-builtin-call
       (context "complete" (list "deploy"))
       :code 1
       :contains (list "complete: usage:"))))

  (it "function-builtin-stores-and-manages-inline-body"
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

  (it "history-builtin-searches-deletes-clears-and-reports-size"
    "history builtin exposes fish-style in-memory history management."
    (let* ((context (make-test-builtins-context))
           (history (nshell.application:shell-context-history context)))
      (history-kit:history-add history "Git status")
      (history-kit:history-add history "git status")
      (history-kit:history-add history "docker ps")
      (history-kit:history-add history "git commit")
      (history-kit:history-add history "git status --short")
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
      (expect 0 :to-equal (history-kit:history-count history)))))
