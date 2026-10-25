(in-package #:nshell/test)

(describe "builtin-tests"
  (it "function-receives-arguments-via-argv"
    "An S-expression function receives all arguments through its rest parameter."
    (with-builtins-source-ok (output code context
                                     (list "(defun greet (&rest argv) (echo hi $argv))"
                                           "(greet \"world\" \"and\" \"friends\")"))
        (format nil "hi world and friends~%")))

  (it "function-argv-indexing-selects-single-argument"
    "$argv[N] selects the Nth (1-based) argument in an S-expression function."
    (with-builtins-source-ok (output code context
                                     (list "(defun pick (&rest argv) (echo got $argv[2]))"
                                           "(pick \"one\" \"two\" \"three\")"))
        (format nil "got two~%")))

  (it "function-argv-ranges-forward-multiple-arguments"
    "$argv ranges select multiple function arguments in an S-expression function."
    (with-builtins-source-ok (output code context
                                     (list "(defun pick (&rest argv) (count $argv[1..2]) (echo last $argv[-1]) (echo reverse $argv[-1..1]))"
                                           "(pick \"one\" \"two\" \"three\")"))
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

  (it "source-dolist-iterates-over-list-values"
    "An S-expression dolist runs once for each value in its source list."
    (with-builtins-source-ok (output code context
                                     (list "(dolist (item (list \"one\" \"two\")) (echo item=$item))"))
        (format nil "item=one~%item=two~%")))

  (it "source-dotimes-skips-body-at-zero"
    "A zero-count S-expression dotimes skips its body and continues with the next form."
    (with-builtins-source-ok (output code context
                                     (list "(progn (dotimes (i 0) (echo skipped)) (echo after))"))
        (format nil "after~%")))

  (it "source-exit-stops-before-later-conditional-branches"
    "An S-expression exit stops source before a later conditional branch can run."
    (dolist (status (list 7 0))
      (dolist (else-branch-p (list nil t))
        (with-builtins-source
            (output code context
                    (list (format nil "(exit ~D)" status)
                          (if else-branch-p
                              "(if t (echo unreachable-then) (echo unreachable-else))"
                              "(if t (echo unreachable-then))")
                          "(echo unreachable-after)"))
          (expect "" :to-equal output)
          (expect status :to-equal code)
          (expect status :to-equal
                  (nshell.application:shell-context-last-exit-code context))
          (expect (nshell.application:shell-context-running context) :to-be-falsy)))))

  (it "source-exit-stops-before-later-loop-forms"
    "An S-expression exit stops source before later loop forms and commands."
    (dolist (status (list 7 0))
      (with-builtins-source
          (output code context
                  (list (format nil "(exit ~D)" status)
                        "(dotimes (index 1) (echo unreachable-body))"
                        "(echo unreachable-after)"))
        (expect "" :to-equal output)
        (expect status :to-equal code)
        (expect status :to-equal
                (nshell.application:shell-context-last-exit-code context))
        (expect (nshell.application:shell-context-running context) :to-be-falsy))))

  (it "source-dotimes-runs-body-only-for-successful-conditions"
    "The S-expression loop runs its body for successful command conditions and skips a failing condition."
    (let ((condition-codes (list 0 0 1))
          (calls nil)
          (argument-calls nil))
      (let ((context (make-test-builtins-context)))
        (with-stubbed-command-builtin
            (("condition"
              (push "condition" calls)
              (push *stubbed-command-builtin-arguments* argument-calls)
              (values "ignored-condition-output" (pop condition-codes)))
             ("body"
              (push "body" calls)
              (push *stubbed-command-builtin-arguments* argument-calls)
              (values (format nil "body~%") 0)))
          (with-called-source
              (output code context
                      (list "(dotimes (iteration 3) (when (condition) (body)))"))
            (expect 0 :to-equal code)
            (expect (format nil "body~%body~%") :to-equal output)
            (expect (list "condition" "body" "condition" "body" "condition")
                    :to-equal (nreverse calls))
            (expect (list nil nil nil nil nil)
                    :to-equal (nreverse argument-calls)))))))

  (it "while-node-returns-last-body-status"
    "The while AST executor returns the last body status after its condition later fails."
    (let ((condition-codes (list 0 1)))
      (let ((context (make-test-builtins-context)))
        (with-test-external-capture-runner
            (lambda (command args)
              (expect args :to-be-null)
              (cond
                ((string= command "condition")
                 (values nil (pop condition-codes)))
                ((string= command "body")
                 (values nil 7))
                (t
                 (values nil 127))))
          (multiple-value-bind (output code)
              (nshell.application::%execute-while-node-in-context
               context
               (nshell.domain.parsing::make-while-node
                (nshell.domain.parsing:make-command-node "condition" nil)
                (list (nshell.domain.parsing:make-command-node "body" nil))))
            (expect "" :to-equal output)
            (expect 7 :to-equal code))))))

  (it "source-function-body-runs-nested-case"
    "An S-expression shell function executes a nested case form and continues through its body."
    (with-builtins-source-ok (output code context
                                     (list "(define-shell-function choose () (case 2 ((1) (echo plain)) ((2) (echo function-sweet)) (otherwise (echo default))) (echo after-switch))"
                                           "(choose)"))
        (format nil "function-sweet~%after-switch~%")
      (expect t :to-equal
              (nth-value
               1
               (nshell.application:lookup-shell-function
                (nshell.application:context-shell-function-registry context)
                "choose")))))

  (it "source-function-body-runs-nested-progn"
    "An S-expression shell function executes a nested progn and continues through its body."
    (with-builtins-source-ok (output code context
                                     (list "(define-shell-function wrap () (progn (echo function-begin) (echo after-begin)))"
                                           "(wrap)"))
        (format nil "function-begin~%after-begin~%")
      (expect t :to-equal
              (nth-value
               1
               (nshell.application:lookup-shell-function
                (nshell.application:context-shell-function-registry context)
                "wrap")))))

  (it "source-progn-executes-body"
    "The S-expression progn executes each body form in the current shell context."
    (with-builtins-source-ok (output code context
                                     (list "(progn (echo begin-one) (echo begin-two))"))
        (format nil "begin-one~%begin-two~%")))

  (it "source-progn-returns-last-body-status"
    "The S-expression progn returns the final body form status."
    (with-builtins-source (output code context
                                  (list "(progn (true) (false))"))
      (declare (ignore output))
      (expect 1 :to-equal code)))

  (it "source-and-short-circuits-after-failed-progn"
    "S-expression and skips its next form when a progn body returns failure."
    (with-builtins-source-ok (output code context
                                     (list "(and (progn (false)) (echo should-not-run))"
                                           "(echo after)"))
        (format nil "after~%")))

  (it "source-or-short-circuits-after-successful-progn"
    "S-expression or skips its next form when a progn body succeeds."
    (with-builtins-source-ok (output code context
                                     (list "(or (progn (true)) (echo should-not-run))"
                                           "(echo after)"))
        (format nil "after~%")))

  (it "for-node-break-stops-the-current-loop"
    "The for AST executor handles break in the current loop and resumes the outer command list."
    (let* ((context (make-test-builtins-context))
           (loop-node
             (nshell.domain.parsing::make-for-node
              "item"
              (list (nshell.domain.parsing:make-command-arg "one")
                    (nshell.domain.parsing:make-command-arg "two"))
              (list (nshell.domain.parsing:make-command-node "echo" (list "before"))
                    (nshell.domain.parsing:make-command-node "break" nil)
                    (nshell.domain.parsing:make-command-node "echo" (list "skipped")))))
           (after-node (nshell.domain.parsing:make-command-node "echo" (list "after"))))
      (multiple-value-bind (output code)
          (nshell.application::%execute-ast-list-in-context
           context (list loop-node after-node))
        (expect (format nil "before~%after~%") :to-equal output)
        (expect 0 :to-equal code))))

  (it "for-node-continue-skips-the-rest-of-the-body"
    "The for AST executor starts the next iteration after continue."
    (let* ((context (make-test-builtins-context))
           (loop-node
             (nshell.domain.parsing::make-for-node
              "item"
              (list (nshell.domain.parsing:make-command-arg "one")
                    (nshell.domain.parsing:make-command-arg "two"))
              (list (nshell.domain.parsing:make-command-node "echo" (list "before"))
                    (nshell.domain.parsing:make-command-node "continue" nil)
                    (nshell.domain.parsing:make-command-node "echo" (list "skipped")))))
           (after-node (nshell.domain.parsing:make-command-node "echo" (list "after"))))
      (multiple-value-bind (output code)
          (nshell.application::%execute-ast-list-in-context
           context (list loop-node after-node))
        (expect (format nil "before~%before~%after~%") :to-equal output)
        (expect 0 :to-equal code))))

  (it "for-node-nested-break-count-propagates-through-loops"
    "A counted break propagates from the inner loop through the requested outer loop."
    (let* ((context (make-test-builtins-context))
           (inner-node
             (nshell.domain.parsing::make-for-node
              "inner"
              (list (nshell.domain.parsing:make-command-arg "one")
                    (nshell.domain.parsing:make-command-arg "two"))
              (list (nshell.domain.parsing:make-command-node "echo" (list "inner"))
                    (nshell.domain.parsing:make-command-node "break" (list "2")))))
           (outer-node
             (nshell.domain.parsing::make-for-node
              "outer"
              (list (nshell.domain.parsing:make-command-arg "one")
                    (nshell.domain.parsing:make-command-arg "two"))
              (list inner-node
                    (nshell.domain.parsing:make-command-node "echo" (list "outer")))))
           (after-node (nshell.domain.parsing:make-command-node "echo" (list "after"))))
      (multiple-value-bind (output code)
          (nshell.application::%execute-ast-list-in-context
           context (list outer-node after-node))
        (expect (format nil "inner~%after~%") :to-equal output)
        (expect 0 :to-equal code))))

  (it "source-loop-control-outside-a-loop-reports-an-error"
    "break outside a loop leaves the shell running and returns a diagnostic."
    (with-builtins-source (output code _context
                                  '("break"
                                    "echo after"))
      (expect (format nil "break: only meaningful in a loop~%after~%")
              :to-equal output)
      (expect 0 :to-equal code))))

  (it "source-control-helpers-handle-loop-signal-contracts"
    "Loop control consumption owns one level and propagates remaining levels."
    (dolist (case '((nil nil nil)
                    ((:break . 1) :break nil)
                    ((:continue . 1) :continue nil)
                    ((:break . 2) :propagate (:break . 1))))
      (destructuring-bind (signal expected remaining) case
        (let ((nshell.application::*loop-control-signal* signal))
          (expect expected :to-equal
                  (nshell.application::%consume-loop-control-signal))
          (expect remaining :to-equal
                  nshell.application::*loop-control-signal*))))
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application::%execute-condition-in-context context nil)
        (expect nil :to-equal output)
        (expect 1 :to-equal code)
        (expect 1 :to-equal
                (nshell.application:shell-context-last-exit-code context)))))

  (it "ast-dispatcher-reports-unsupported-syntax"
    "The generated AST dispatcher returns a stable diagnostic for unknown nodes."
    (multiple-value-bind (output code)
        (nshell.application::execute-ast-in-context
         (make-test-builtins-context)
         :unknown-ast)
      (expect (stringp output) :to-be-truthy)
      (expect 2 :to-equal code)))

