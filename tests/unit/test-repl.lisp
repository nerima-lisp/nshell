(in-package #:nshell/test)

(describe "repl-tests"
  (it "repl-entrypoints-are-public"
    "CLI-facing REPL entrypoints should be exported presentation APIs."
    (expect (fboundp 'nshell.presentation:run-repl) :to-be-truthy)
    (expect (fboundp 'nshell.presentation:run-repl-batch) :to-be-truthy)
    (expect (fboundp 'nshell.presentation:run-repl-script) :to-be-truthy))

  (it "repl-batch-returns-last-exit-code"
    "Batch execution should return the last command status for process exit."
    (with-repl-test-state
      (let ((code (nshell.presentation:run-repl-batch :line "false")))
        (expect 1 :to-equal code)
        (expect 1 :to-equal nshell.presentation::*last-exit-code*)))))
