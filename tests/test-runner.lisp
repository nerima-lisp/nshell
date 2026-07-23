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

(describe "nshell-tests"
  (it "smoke-test"
    "Basic sanity check that the test framework and project are loaded correctly."
    (expect 1 :to-equal 1)
    (expect "nshell" :to-equal "nshell"))

  (it "main-cli-action"
    "CLI argument dispatch should recognize help, version, and invalid inputs."
    (expect :help :to-be (nshell::%cli-action '("--help")))
    (expect :help :to-be (nshell::%cli-action '("-h")))
    (expect :version :to-be (nshell::%cli-action '("--version")))
    (expect :version :to-be (nshell::%cli-action '("-V")))
    (expect :command :to-be (nshell::%cli-action '("-c" "echo hello")))
    (expect :command :to-be (nshell::%cli-action '("--command" "echo hello")))
    (expect :run :to-be (nshell::%cli-action nil))
    ;; A leading non-flag argument names a script file (with optional $argv).
    (expect :script :to-be (nshell::%cli-action '("script")))
    (expect :script :to-be (nshell::%cli-action '("script.nsh" "arg1" "arg2")))
    (expect :invalid :to-be (nshell::%cli-action '("-c")))
    (expect :invalid :to-be (nshell::%cli-action '("--unknown"))))

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
