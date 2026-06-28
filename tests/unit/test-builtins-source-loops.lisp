(in-package #:nshell/test)
(in-suite builtin-tests)

(test function-receives-arguments-via-argv
  "A called function sees its arguments through $argv (forwarded as words)."
  (with-builtins-source (output code context
                                 '("function greet"
                                   "echo hi $argv"
                                   "end"
                                   "greet world and friends"))
    (is (= 0 code))
    (is (string= (format nil "hi world and friends~%") output))))

(test function-argv-indexing-selects-single-argument
  "$argv[N] selects the Nth (1-based) argument inside a function body."
  (with-builtins-source (output code context
                                 '("function pick"
                                   "echo got $argv[2]"
                                   "end"
                                   "pick one two three"))
    (is (= 0 code))
    (is (string= (format nil "got two~%") output))))

(test function-argv-ranges-forward-multiple-arguments
  "$argv[A..B] expands to separate arguments inside source-loaded functions."
  (with-builtins-source (output code context
                                 '("function pick"
                                   "count $argv[1..2]"
                                   "echo last $argv[-1]"
                                   "echo reverse $argv[-1..1]"
                                   "end"
                                   "pick one two three"))
    (is (= 0 code))
    (is (string= (format nil "2~%last three~%reverse three two one~%") output))))

(test function-argv-compound-ranges-expand-as-fields
  "Compound unquoted $argv ranges produce one field per list value."
  (with-builtins-source (output code context
                                 '("function decorate"
                                   "count pre-$argv[1..2].txt"
                                   "echo pre-$argv[1..2].txt"
                                   "end"
                                   "decorate alpha beta gamma"))
    (is (= 0 code))
    (is (string= (format nil "2~%pre-alpha.txt pre-beta.txt~%") output))))

(test source-variable-list-compound-ranges-expand-as-fields
  "Compound unquoted indexed variables produce one field per list value."
  (with-builtins-source (output code _context
                               '("set files alpha beta gamma"
                                 "count pre-$files[1..2].txt"
                                 "echo pre-$files[1..2].txt"))
    (is (= 0 code))
    (is (string= (format nil "2~%pre-alpha.txt pre-beta.txt~%") output))))

(test source-for-loop-expands-command-substitution-values
  "source lets fish-style for loops iterate over command substitution lines."
  (with-builtins-source (output code context
                                 '("function values"
                                   "echo one"
                                   "echo two"
                                   "end"
                                   "for item in (values)"
                                   "echo item=$item"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "item=one~%item=two~%") output))))

(test source-while-skips-body-when-condition-fails
  "source does not execute a while body when the condition fails before entry."
  (with-builtins-source (output code context
                                 '("while false"
                                   "echo skipped"
                                   "end"
                                   "echo after"))
    (is (= 0 code))
    (is (string= (format nil "after~%") output))))

(test source-while-repeats-while-condition-succeeds
  "source repeats fish-style while loops until the condition returns non-zero."
  (let ((context (make-test-builtins-context))
        (condition-codes '(0 0 1))
        (calls nil))
    (with-temporary-function
        ('nshell.application::execute-ast-in-context
         (lambda (_context ast)
           (declare (ignore _context))
           (let ((command (nshell.domain.parsing:command-node-command ast)))
             (push command calls)
             (if (string= command "condition")
                 (values nil (pop condition-codes))
                 (values (format nil "~a~%" command) 0)))))
      (let ((ast (nshell.domain.parsing::make-while-node
                  (nshell.domain.parsing:make-command-node "condition" nil)
                  (list (nshell.domain.parsing:make-command-node "body" nil)))))
        (multiple-value-bind (output code)
            (nshell.application::%execute-while-node-in-context context ast)
          (is (= 0 code))
          (is (string= (format nil "body~%body~%") output))
          (is (equal '("condition" "body" "condition" "body" "condition")
                     (nreverse calls))))))))

(test source-while-returns-last-body-status
  "source while returns the last executed body status, not the failing condition status."
  (let ((context (make-test-builtins-context))
        (condition-codes '(0 1)))
    (with-temporary-function
        ('nshell.application::execute-ast-in-context
         (lambda (_context ast)
           (declare (ignore _context))
           (let ((command (nshell.domain.parsing:command-node-command ast)))
             (if (string= command "condition")
                 (values nil (pop condition-codes))
                 (values nil 7)))))
      (let ((ast (nshell.domain.parsing::make-while-node
                  (nshell.domain.parsing:make-command-node "condition" nil)
                  (list (nshell.domain.parsing:make-command-node "body" nil)))))
        (multiple-value-bind (output code)
            (nshell.application::%execute-while-node-in-context context ast)
          (is (= 7 code))
          (is (string= "" output)))))))

(test source-function-body-supports-nested-switch
  "source keeps nested switch/case blocks inside function definitions."
  (with-builtins-source (output code context
                                 '("function choose"
                                   "switch chocolate"
                                   "case chocolate"
                                   "echo function-sweet"
                                   "end"
                                   "echo after-switch"
                                   "end"
                                   "choose"))
    (is (= 0 code))
    (is (string= (format nil "function-sweet~%after-switch~%") output))
    (is (equal '("switch chocolate"
                 "case chocolate"
                 "echo function-sweet"
                 "end"
                 "echo after-switch")
               (gethash "choose"
                        (nshell.application:shell-context-function-table
                         context))))))

(test source-function-body-supports-nested-begin
  "source keeps nested begin/end blocks inside function definitions."
  (with-builtins-source (output code context
                                 '("function wrap"
                                   "begin"
                                   "echo function-begin"
                                   "end"
                                   "echo after-begin"
                                   "end"
                                   "wrap"))
    (is (= 0 code))
    (is (string= (format nil "function-begin~%after-begin~%") output))
    (is (equal '("begin"
                 "echo function-begin"
                 "end"
                 "echo after-begin")
               (gethash "wrap"
                        (nshell.application:shell-context-function-table
                         context))))))

(test source-begin-block-executes-body
  "source executes top-level begin/end blocks in the current shell context."
  (with-builtins-source (output code _context
                                 '("begin"
                                   "echo begin-one"
                                   "echo begin-two"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "begin-one~%begin-two~%") output))))

(test source-begin-block-returns-last-body-status
  "source returns the final status from a top-level begin/end block."
  (with-builtins-source (_output code _context
                                 '("begin"
                                   "true"
                                   "false"
                                   "end"))
    (declare (ignore _output))
    (is (= 1 code))))

(test source-begin-block-and-short-circuits-on-block-failure
  "source applies && to the status of the entire begin/end block."
  (with-builtins-source (output code _context
                                 '("begin"
                                   "false"
                                   "end && echo should-not-run"
                                   "echo after"))
    (is (= 0 code))
    (is (string= (format nil "after~%") output))))

(test source-begin-block-or-short-circuits-on-block-success
  "source applies || to the status of the entire begin/end block."
  (with-builtins-source (output code _context
                                 '("begin"
                                   "true"
                                   "end || echo should-not-run"
                                   "echo after"))
    (is (= 0 code))
    (is (string= (format nil "after~%") output))))

