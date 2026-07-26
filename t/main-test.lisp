;;; Tests for src/main.lisp: the command-line surface of the nshell binary.

(in-package #:nshell/test)

(defparameter +usage-synopsis-line+
  "Usage: nshell [--help] [--version] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]"
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
    "The cl-cli app spec should classify help, version, command, and invalid inputs."
    (labels ((parse (args)
               ;; Mirror MAIN: parse the flag-led surface through cl-cli.
               (cl-cli:parse-argv (nshell::%build-cli-app) (cons "nshell" args)))
             (usage-error-p (args)
               (handler-case (progn (parse args) nil)
                 (cl-cli:cli-usage-error () t))))
      ;; Help / version flags (short and long).
      (expect (cl-cli:option-value (parse '("--help")) :show-help) :to-be-truthy)
      (expect (cl-cli:option-value (parse '("-h")) :show-help) :to-be-truthy)
      (expect (cl-cli:option-value (parse '("--version")) :show-version) :to-be-truthy)
      (expect (cl-cli:option-value (parse '("-V")) :show-version) :to-be-truthy)
      ;; -c / --command carry the command string; the tail becomes $argv.
      (expect "echo hello" :to-equal
              (cl-cli:option-value (parse '("-c" "echo hello")) :command))
      (expect "echo hello" :to-equal
              (cl-cli:option-value (parse '("--command" "echo hello")) :command))
      (expect '("a" "b") :to-equal
              (cl-cli:positional-value (parse '("-c" "cmd" "a" "b")) :command-args))
      ;; No arguments: no flags set (MAIN then chooses interactive vs batch).
      (expect (cl-cli:option-value (parse nil) :command) :to-be-falsy)
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
      (expect (search "nshell v" version) :to-be-truthy))))
