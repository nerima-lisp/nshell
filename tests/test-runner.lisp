;;; nshell test runner
;;; Aggregates and runs all test suites

(in-package #:nshell/test)

(defun in-hermetic-sandbox-p ()
  "True in hermetic Nix builds, not in impure nix develop shells.
Real OS process and PTY integration tests are skipped only when the surrounding
environment is expected to hide facilities such as /bin/sh, /bin/cat, or PTYs."
  (and (uiop:getenv "NIX_BUILD_TOP")
       (not (string= (or (uiop:getenv "IN_NIX_SHELL") "")
                     "impure"))))

(defmacro skip-in-sandbox (reason &body body)
  "Run BODY only when not in a hermetic sandbox; otherwise skip with REASON."
  `(if (in-hermetic-sandbox-p)
       (skip (format nil "~a (skipped in hermetic sandbox)" ,reason))
       (progn ,@body)))

(defmacro skip-when-pty-round-trip-unreliable (reason &body body)
  "Run BODY only where raw PTY master/slave round-trip I/O is reliable.

Reading bytes straight back through a PTY depends on the terminal line
discipline, which differs across platforms and is not honored by hosted CI
runners, so skip both the hermetic sandbox and CI."
  `(if (or (in-hermetic-sandbox-p) (uiop:getenv "CI"))
       (skip (format nil "~a (skipped in sandbox/CI)" ,reason))
       (progn ,@body)))

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
      (expect (search "Usage: nshell [--help] [--version] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]" usage) :to-be-truthy)
      (expect (search "stdin is a terminal" usage) :to-be-truthy)
      (expect (search "With -c/--command" usage) :to-be-truthy)
      (expect (search "nshell v" version) :to-be-truthy))))

(defun run-tests ()
  "Run all nshell tests through cl-weave.

Runs single-threaded: many suites share process-global state (mock command
tables, abbreviation/alias/history registries, dynamic completion hooks), so
concurrent execution would race.  This mirrors how the FiveAM suite ran."
  (run-all :reporter :spec :max-workers 1))
