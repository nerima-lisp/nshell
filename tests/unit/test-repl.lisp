(in-package #:nshell/test)

(def-suite repl-tests
  :description "REPL presentation boundary tests"
  :in nshell-tests)

(in-suite repl-tests)

(test repl-batch-returns-last-exit-code
  "Batch execution should return the last command status for process exit."
  (with-repl-test-state
    (let ((code (nshell.presentation::run-repl-batch :line "false")))
      (is (= 1 code))
      (is (= 1 nshell.presentation::*last-exit-code*)))))
