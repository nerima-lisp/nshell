(in-package #:nshell/test)

(describe "builtin-tests"
  (it "function-receives-arguments-via-argv"
    "A called function sees its arguments through $argv (forwarded as words)."
    (with-builtins-source-ok (output code context
                                     '("function greet"
                                       "echo hi $argv"
                                       "end"
                                       "greet world and friends"))
        (format nil "hi world and friends~%")))

  (it "function-argv-indexing-selects-single-argument"
    "$argv[N] selects the Nth (1-based) argument inside a function body."
    (with-builtins-source-ok (output code context
                                     '("function pick"
                                       "echo got $argv[2]"
                                       "end"
                                       "pick one two three"))
        (format nil "got two~%")))

  (it "function-argv-ranges-forward-multiple-arguments"
    "$argv[A..B] expands to separate arguments inside source-loaded functions."
    (with-builtins-source-ok (output code context
                                     '("function pick"
                                       "count $argv[1..2]"
                                       "echo last $argv[-1]"
                                       "echo reverse $argv[-1..1]"
                                       "end"
                                       "pick one two three"))
        (format nil "2~%last three~%reverse three two one~%")))

  (it "function-argv-compound-ranges-expand-as-fields"
    "Compound unquoted $argv ranges produce one field per list value."
    (with-builtins-source-ok (output code context
                                     '("function decorate"
                                       "count pre-$argv[1..2].txt"
                                       "echo pre-$argv[1..2].txt"
                                       "end"
                                       "decorate alpha beta gamma"))
        (format nil "2~%pre-alpha.txt pre-beta.txt~%")))

  (it "source-variable-list-compound-ranges-expand-as-fields"
    "Compound unquoted indexed variables produce one field per list value."
    (with-builtins-source-ok (output code _context
                                     '("set files alpha beta gamma"
                                       "count pre-$files[1..2].txt"
                                       "echo pre-$files[1..2].txt"))
        (format nil "2~%pre-alpha.txt pre-beta.txt~%")))

  (it "source-for-loop-expands-command-substitution-values"
    "source lets fish-style for loops iterate over command substitution lines."
    (with-builtins-source-ok (output code context
                                     '("function values"
                                       "echo one"
                                       "echo two"
                                       "end"
                                       "for item in (values)"
                                       "echo item=$item"
                                       "end"))
        (format nil "item=one~%item=two~%")))

  (it "source-while-skips-body-when-condition-fails"
    "source does not execute a while body when the condition fails before entry."
    (with-builtins-source-ok (output code context
                                     '("while false"
                                       "echo skipped"
                                       "end"
                                       "echo after"))
        (format nil "after~%")))

  (it "source-while-repeats-while-condition-succeeds"
    "source repeats fish-style while loops until the condition returns non-zero."
    (let ((condition-codes '(0 0 1))
          (calls nil))
      (let ((context (make-test-builtins-context
                      :external-capture-runner
                      (lambda (command args)
                        (expect args :to-be-null)
                        (push command calls)
                        (cond
                          ((string= command "condition")
                           (values "ignored-condition-output" (pop condition-codes)))
                          ((string= command "body")
                           (values (format nil "body~%") 0))
                          (t
                           (values "" 127)))))))
        (with-called-source (output code context
                                    '("while condition"
                                      "body"
                                      "end"))
          (expect 0 :to-equal code)
          (expect (format nil "body~%body~%") :to-equal output)
          (expect '("condition" "body" "condition" "body" "condition") :to-equal (nreverse calls))))))

  (it "source-while-returns-last-body-status"
    "source while returns the last executed body status, not the failing condition status."
    (let ((condition-codes '(0 1)))
      (let ((context (make-test-builtins-context
                      :external-capture-runner
                      (lambda (command args)
                        (expect args :to-be-null)
                        (cond
                          ((string= command "condition")
                           (values nil (pop condition-codes)))
                          ((string= command "body")
                           (values nil 7))
                          (t
                           (values nil 127)))))))
        (with-called-source (output code context
                                    '("while condition"
                                      "body"
                                      "end"))
          (expect 7 :to-equal code)
          (expect "" :to-equal output)))))

  (it "source-function-body-supports-nested-switch"
    "source keeps nested switch/case blocks inside function definitions."
    (with-builtins-source-ok (output code context
                                     '("function choose"
                                       "switch chocolate"
                                       "case chocolate"
                                       "echo function-sweet"
                                       "end"
                                       "echo after-switch"
                                       "end"
                                       "choose"))
        (format nil "function-sweet~%after-switch~%")
      (expect '("switch chocolate"
                   "case chocolate"
                   "echo function-sweet"
                   "end"
                   "echo after-switch") :to-equal (gethash "choose"
                          (nshell.application:shell-context-function-table
                           context)))))

  (it "source-function-body-supports-nested-begin"
    "source keeps nested begin/end blocks inside function definitions."
    (with-builtins-source-ok (output code context
                                     '("function wrap"
                                       "begin"
                                       "echo function-begin"
                                       "end"
                                       "echo after-begin"
                                       "end"
                                       "wrap"))
        (format nil "function-begin~%after-begin~%")
      (expect '("begin"
                   "echo function-begin"
                   "end"
                   "echo after-begin") :to-equal (gethash "wrap"
                          (nshell.application:shell-context-function-table
                           context)))))

  (it "source-begin-block-executes-body"
    "source executes top-level begin/end blocks in the current shell context."
    (with-builtins-source-ok (output code _context
                                     '("begin"
                                       "echo begin-one"
                                       "echo begin-two"
                                       "end"))
        (format nil "begin-one~%begin-two~%")))

  (it "source-begin-block-returns-last-body-status"
    "source returns the final status from a top-level begin/end block."
    (with-builtins-source (_output code _context
                                   '("begin"
                                     "true"
                                     "false"
                                     "end"))
      (declare (ignore _output))
      (expect 1 :to-equal code)))

  (it "source-begin-block-and-short-circuits-on-block-failure"
    "source applies && to the status of the entire begin/end block."
    (with-builtins-source-ok (output code _context
                                     '("begin"
                                       "false"
                                       "end && echo should-not-run"
                                       "echo after"))
        (format nil "after~%")))

  (it "source-begin-block-or-short-circuits-on-block-success"
    "source applies || to the status of the entire begin/end block."
    (with-builtins-source-ok (output code _context
                                     '("begin"
                                       "true"
                                       "end || echo should-not-run"
                                       "echo after"))
        (format nil "after~%")))

  (it "source-for-break-stops-the-current-loop"
    "break exits the nearest loop and resumes after its end marker."
    (with-builtins-source-ok (output code _context
                                     '("for item in one two"
                                       "echo before"
                                       "break"
                                       "echo skipped"
                                       "end"
                                       "echo after"))
        (format nil "before~%after~%")))

  (it "source-for-continue-skips-the-rest-of-the-body"
    "continue starts the next iteration without running later body commands."
    (with-builtins-source-ok (output code _context
                                     '("for item in one two"
                                       "echo before"
                                       "continue"
                                       "echo skipped"
                                       "end"
                                       "echo after"))
        (format nil "before~%before~%after~%")))

  (it "source-nested-break-count-propagates-through-loops"
    "break N exits N enclosing loops."
    (with-builtins-source-ok (output code _context
                                     '("for outer in one two"
                                       "for inner in one two"
                                       "echo inner"
                                       "break 2"
                                       "end"
                                       "echo outer"
                                       "end"
                                       "echo after"))
        (format nil "inner~%after~%")))

  (it "source-loop-control-outside-a-loop-reports-an-error"
    "break outside a loop leaves the shell running and returns a diagnostic."
    (with-builtins-source (output code _context
                                  '("break"
                                    "echo after"))
      (expect (format nil "break: only meaningful in a loop~%after~%")
              :to-equal output)
      (expect 0 :to-equal code))))
