;;; Tests for src/main.lisp: the command-line surface of the nshell binary.
(in-package #:nshell/test)

(defparameter +usage-synopsis-line+ "Usage: nshell [OPTIONS] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]"
  "The synopsis %PRINT-USAGE must emit verbatim.

Held as a constant because the literal is longer than the 100-column line
limit, and a string literal cannot be broken across source lines without
changing its value.")

(describe "nshell-tests"
  (it "smoke-test"
    "Basic sanity check that the test framework and project are loaded correctly."
    (expect 1 :to-equal 1)
    (expect "nshell" :to-equal "nshell"))

  (it "main-cli-action"
    "The command-line feature should classify flags, commands, and invalid inputs."
    (labels ((parse (args)
               (nth-value 0
                          (nshell::%parse-cli-arguments args)))
             (usage-error-p (args)
               (nth-value 1
                          (nshell::%parse-cli-arguments args))))
      ;; Help / version flags (short and long).
      (expect (cl-cli:option-value
               (parse '("--help")) :show-help) :to-be-truthy)
      (expect (cl-cli:option-value
               (parse '("-h")) :show-help) :to-be-truthy)
      (expect (cl-cli:option-value
               (parse '("--version")) :show-version) :to-be-truthy)
      (expect (cl-cli:option-value
               (parse '("-V")) :show-version) :to-be-truthy)
      ;; -c / --command carry the command string; the tail becomes $argv.
      (expect "echo hello" :to-equal
              (cl-cli:option-value
               (parse '("-c" "echo hello")) :command))
      (expect "echo hello" :to-equal
              (cl-cli:option-value
               (parse '("--command" "echo hello")) :command))
      (expect '("a" "b") :to-equal
              (cl-cli:positional-value
               (parse '("-c" "cmd" "a" "b")) :command-args))
      ;; No arguments: no flags set (MAIN then chooses interactive vs batch).
      (expect (cl-cli:option-value
               (parse nil) :command) :to-be-falsy)
      ;; A leading non-flag argument is a SCRIPT, handled before cl-cli parsing.
      (expect (nshell::%flag-argument-p "script") :to-be-falsy)
      (expect (nshell::%flag-argument-p "script.nsh") :to-be-falsy)
      ;; Missing -c value and unknown flags are usage errors (exit 1 in MAIN).
      (expect (usage-error-p '("-c")) :to-be-truthy)
      (expect (usage-error-p '("--unknown")) :to-be-truthy)))

  (it "main-cli-output"
    "Top-level text should include a usage line and version banner."
    (let ((usage (with-output-to-string (stream)
                   (nshell::%print-usage stream)))
          (version (with-output-to-string (stream)
                     (nshell::%print-version stream))))
      (expect (search +usage-synopsis-line+ usage) :to-be-truthy)
      (expect (search "stdin is a terminal" usage) :to-be-truthy)
      (expect (search "With -c/--command" usage) :to-be-truthy)
      (expect (search "nshell v" version) :to-be-truthy)))

  (it "main-invocation-dispatch"
  "Dispatch parsed CLI actions and select the TTY or batch default path."
  (labels ((parse (arguments)
             (nth-value 0
                        (nshell::%parse-cli-arguments arguments))))
    (let ((help-output
            (with-output-to-string (*standard-output*)
              (expect 0 :to-equal
                      (nshell::%run-parsed-invocation (parse (list "--help"))))))
          (version-output
            (with-output-to-string (*standard-output*)
              (expect 0 :to-equal
                      (nshell::%run-parsed-invocation (parse (list "--version")))))))
      (expect (search +usage-synopsis-line+ help-output) :to-be-truthy)
      (expect (search "nshell v" version-output) :to-be-truthy))
    (let ((batch-call nil))
      (with-temporary-function
          ((quote nshell.presentation:run-repl-batch)
           (lambda (&key line script-args)
             (setf batch-call (list line script-args))
             23))
        (expect 23 :to-equal
                (nshell::%run-parsed-invocation
                 (parse (list "-c" "echo ready" "literal" "--not-an-option"))))
        (expect (list "echo ready" (list "literal" "--not-an-option"))
                :to-equal batch-call)))
    (with-temporary-function
        ((quote nshell::%run-default-invocation)
         (lambda (&rest ignored)
           (declare (ignore ignored))
           29))
      (expect 29 :to-equal (nshell::%run-parsed-invocation (parse nil)))))
    (let ((error-output
            (with-output-to-string (*error-output*)
              (expect 1 :to-equal
                      (nshell::%run-parsed-invocation
                       (nth-value 0
                                  (nshell::%parse-cli-arguments
                                   (list "--no-config" "--config" "custom.rc"))))))))
      (expect (search "--config and --no-config" error-output) :to-be-truthy))
    (let ((error-output
            (with-output-to-string (*error-output*)
              (expect 1 :to-equal
                      (nshell::%run-parsed-invocation
                       (nth-value 0
                                  (nshell::%parse-cli-arguments
                                   (list "--interactive" "-c" "echo no"))))))))
      (expect (search "--interactive cannot be combined" error-output) :to-be-truthy))
  (let ((repl-called nil))
    (with-temporary-function
        ((quote nshell::tty-p) (lambda () t))
      (with-temporary-function
          ((quote nshell.presentation:run-repl)
           (lambda () (setf repl-called t)))
        (expect 0 :to-equal (nshell::%run-default-invocation))))
    (expect repl-called :to-be-truthy))
  (let ((repl-call nil))
    (with-temporary-function
        ((quote nshell.presentation:run-repl)
         (lambda (&rest arguments)
           (setf repl-call arguments)))
      (expect 0 :to-equal
              (nshell::%run-default-invocation
               :interactive-p t
               :load-config-p nil
               :config-path "custom.rc"
               :history-p nil)))
    (expect '(:load-config-p nil :config-path "custom.rc" :history-p nil)
            :to-equal repl-call))
  (let ((batch-called nil))
    (with-temporary-function
        ((quote nshell::tty-p) (lambda () nil))
      (with-temporary-function
          ((quote nshell.presentation:run-repl-batch)
           (lambda (&rest ignored)
             (declare (ignore ignored))
             (setf batch-called t)
             43))
        (expect 43 :to-equal (nshell::%run-default-invocation))))
    (expect batch-called :to-be-truthy)))

  (it "main-command-line-contract"
  "MAIN preserves public dispatch and error exit-code contracts."
  (labels ((invoke (arguments)
             (let* ((exit-status nil)
                    (nshell::*main-exit-function*
                      (lambda (&key unix-status &allow-other-keys)
                        (setf exit-status unix-status)
                        unix-status)))
               (with-temporary-functions
                   (('nshell::%current-process-arguments
                     (lambda () arguments)))
                 (values (nshell::main) exit-status)))))
    (with-temporary-function
        ((quote nshell::%run-default-invocation) (lambda () 17))
      (expect (list 17 17) :to-equal
              (multiple-value-list (invoke nil))))
    (let ((script-call nil))
      (with-temporary-function
          ((quote nshell.presentation:run-repl-script)
           (lambda (path arguments)
             (setf script-call (list path arguments))
             23))
        (expect (list 23 23) :to-equal
                (multiple-value-list
                 (invoke (list "fixture.nsh" "literal" "--not-an-option"))))
        (expect (list "fixture.nsh" (list "literal" "--not-an-option"))
                :to-equal script-call)))
    (let* ((result nil)
           (error-output
             (with-output-to-string (*error-output*)
               (setf result
                     (multiple-value-list (invoke (list "--unknown")))))))
      (expect (list 1 1) :to-equal result)
      (expect (search +usage-synopsis-line+ error-output) :to-be-truthy))
    (let* ((result nil)
           (error-output
             (with-output-to-string (*error-output*)
               (with-temporary-function
                   ((quote nshell::%run-default-invocation)
                    (lambda () (error "dispatch failed")))
                 (setf result (multiple-value-list (invoke nil)))))))
      (expect (list 1 1) :to-equal result)
      (expect (search "Fatal error: dispatch failed" error-output)
              :to-be-truthy))))
)
