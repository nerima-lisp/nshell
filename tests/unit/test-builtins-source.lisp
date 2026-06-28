(in-package #:nshell/test)

(in-suite builtin-tests)

(defun %source-sequence-call-order (separator first-code second-code)
  (let ((context (make-test-builtins-context))
        (calls nil))
    (with-temporary-function
        ('nshell.application::execute-ast-in-context
         (lambda (_context ast)
           (declare (ignore _context))
           (let ((command (nshell.domain.parsing:command-node-command ast)))
             (push command calls)
             (values nil (if (string= command "first")
                             first-code
                             second-code)))))
      (let ((ast (nshell.domain.parsing::make-sequence-node
                  (list (nshell.domain.parsing:make-command-node "first" nil)
                        (nshell.domain.parsing:make-command-node "second" nil))
                  (list separator))))
        (multiple-value-bind (output code)
            (nshell.application::%execute-sequence-node-in-context context ast)
          (values output code (nreverse calls)))))))

(test source-sequence-and-short-circuits-on-failure
  "source stops a sequence after a failing && command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :and 1 0)
    (is (string= "" output))
    (is (= 1 code))
    (is (equal '("first") calls))))

(test source-sequence-and-continues-on-success
  "source continues past a successful && command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :and 0 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first" "second") calls))))

(test source-sequence-or-short-circuits-on-success
  "source stops a sequence after a successful || command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :or 0 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first") calls))))

(test source-sequence-or-continues-on-failure
  "source continues past a failing || command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :or 1 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first" "second") calls))))

(test source-sequence-amp-spawns-background-command-and-continues
  "source runs the command before & asynchronously and continues with the next command."
  (let ((context (make-test-builtins-context))
        (foreground-calls nil)
        (spawned nil))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-async
         (lambda (command args &key redirects)
           (setf spawned (list command args redirects))
           t))
      (with-temporary-function
          ('nshell.application::execute-ast-in-context
           (lambda (_context ast)
             (declare (ignore _context))
             (let ((command (nshell.domain.parsing:command-node-command ast)))
               (push command foreground-calls)
               (values (format nil "~a~%" command) 0))))
           (let ((ast (nshell.domain.parsing::make-sequence-node
                       (list (nshell.domain.parsing:make-command-node
                              "first" nil)
                             (nshell.domain.parsing:make-command-node "second" nil))
                       (list :amp))))
          (multiple-value-bind (output code)
              (nshell.application::%execute-sequence-node-in-context context ast)
            (is (= 0 code))
            (is (string= (format nil "second~%") output))
            (is (equal '("second") (nreverse foreground-calls)))
            (is (equal '("first" nil nil) spawned))))))))

(test source-sequence-amp-spawns-background-pipeline-and-continues
  "source runs the pipeline before & asynchronously and continues with the next command."
  (let ((context (make-test-builtins-context))
        (foreground-calls nil)
        (spawned nil))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-pipeline-async
         (lambda (commands &key redirects)
           (setf spawned (list (mapcar #'nshell.domain.parsing:command-node-command
                                       commands)
                               redirects))
           commands))
      (with-temporary-function
          ('nshell.application::execute-ast-in-context
           (lambda (_context ast)
             (declare (ignore _context))
             (let ((command (nshell.domain.parsing:command-node-command ast)))
               (push command foreground-calls)
               (values (format nil "~a~%" command) 0))))
        (let* ((pipeline (nshell.domain.parsing:make-pipeline-node
                          (list (nshell.domain.parsing:make-command-node "first" nil)
                                (nshell.domain.parsing:make-command-node "second" nil))))
               (ast (nshell.domain.parsing::make-sequence-node
                     (list pipeline
                           (nshell.domain.parsing:make-command-node "third" nil))
                     (list :amp))))
          (multiple-value-bind (output code)
              (nshell.application::%execute-sequence-node-in-context context ast)
            (is (= 0 code))
            (is (string= (format nil "third~%") output))
            (is (equal '("third") (nreverse foreground-calls)))
              (is (equal '(("first" "second") (nil nil)) spawned))))))))

(test source-sequence-amp-registers-background-command-job
  "source registers background commands so jobs can report them."
  (let ((context (make-test-builtins-context))
        (process :background-process))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-async
         (lambda (command args &key redirects)
           (declare (ignore command args redirects))
           process))
      (with-temporary-function
          ('nshell.application::%background-process-pid
           (lambda (proc)
             (when (eq proc process)
               4321)))
        (with-temporary-function
            ('nshell.application::execute-ast-in-context
             (lambda (_context ast)
               (declare (ignore _context))
               (values (format nil "~a~%"
                               (nshell.domain.parsing:command-node-command ast))
                       0)))
          (let ((ast (nshell.domain.parsing::make-sequence-node
                      (list (nshell.domain.parsing:make-command-node
                             "first" (list "arg"))
                            (nshell.domain.parsing:make-command-node "second" nil))
                      (list :amp))))
            (multiple-value-bind (output code)
                (nshell.application::%execute-sequence-node-in-context context ast)
              (is (= 0 code))
              (is (string= (format nil "second~%") output))
              (let* ((entries (nshell.domain.job-control:monitor-entries
                               (nshell.application:shell-context-job-monitor
                                context)))
                     (entry (first entries))
                     (job-id (car entry))
                     (job (cdr entry)))
                (is (= 1 (length entries)))
                (is (equal '(4321) (nshell.domain.execution:job-pids job)))
                (is (= 4321 (nshell.domain.execution:job-pgid job)))
                (is (nshell.domain.execution:job-background-p job))
                (is (eq :running (nshell.domain.execution:job-state job)))
                (is (string= "first arg"
                             (nshell.domain.execution:job-command-line job)))
                (is (eq process
                        (gethash job-id
                                 (nshell.application:shell-context-process-registry
                                  context))))))))))))

(test source-sequence-amp-registers-background-pipeline-job
  "source registers background pipelines with every spawned process."
  (let ((context (make-test-builtins-context))
        (processes '(:left-process :right-process)))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-pipeline-async
         (lambda (commands &key redirects)
           (declare (ignore commands redirects))
           processes))
      (with-temporary-function
          ('nshell.application::%background-process-pid
           (lambda (proc)
             (case proc
               (:left-process 4321)
               (:right-process 4322))))
        (with-temporary-function
            ('nshell.application::execute-ast-in-context
             (lambda (_context ast)
               (declare (ignore _context))
               (values (format nil "~a~%"
                               (nshell.domain.parsing:command-node-command ast))
                       0)))
           (let* ((pipeline (nshell.domain.parsing:make-pipeline-node
                            (list (nshell.domain.parsing:make-command-node
                                   "first" (list "left"))
                                  (nshell.domain.parsing:make-command-node
                                   "second" (list "right")))))
                 (ast (nshell.domain.parsing::make-sequence-node
                       (list pipeline
                             (nshell.domain.parsing:make-command-node
                              "third" nil))
                       (list :amp))))
            (multiple-value-bind (output code)
                (nshell.application::%execute-sequence-node-in-context context ast)
              (is (= 0 code))
              (is (string= (format nil "third~%") output))
              (let* ((entries (nshell.domain.job-control:monitor-entries
                               (nshell.application:shell-context-job-monitor
                                context)))
                     (entry (first entries))
                     (job-id (car entry))
                     (job (cdr entry)))
                (is (= 1 (length entries)))
                (is (equal '(4321 4322)
                           (nshell.domain.execution:job-pids job)))
                (is (= 4321 (nshell.domain.execution:job-pgid job)))
                (is (nshell.domain.execution:job-background-p job))
                (is (eq :running (nshell.domain.execution:job-state job)))
                (is (string= "first left | second right"
                             (nshell.domain.execution:job-command-line job)))
                (is (eq processes
                        (gethash job-id
                                 (nshell.application:shell-context-process-registry
                                  context))))))))))))

(test source-function-body-supports-nested-control-flow
  "source keeps nested blocks inside function definitions instead of closing at the first end."
  (with-builtins-source (output code context
                                 '("function nested"
                                   "if true"
                                   "echo function-inner"
                                   "else"
                                   "echo function-else"
                                   "end"
                                   "echo function-after"
                                   "end"
                                   "nested"
                                   "echo script-after"))
    (is (= 0 code))
    (is (string= (format nil "function-inner~%function-after~%script-after~%")
                 output))
    (is (equal '("if true"
                 "echo function-inner"
                 "else"
                 "echo function-else"
                 "end"
                 "echo function-after")
               (gethash "nested"
                        (nshell.application:shell-context-function-table
                         context))))))

(test source-function-definition-supports-inline-body
  "source registers functions defined on a single line with an inline body."
  (with-builtins-source (output code context
                                 '("function foo; echo hi; end"
                                   "foo"))
    (is (= 0 code))
    (is (string= (format nil "hi~%") output))
    (is (equal '("echo hi")
               (gethash "foo"
                        (nshell.application:shell-context-function-table
                         context))))))

(test source-function-definition-preserves-trailing-inline-commands
  "source keeps commands that follow an inline function definition on the same line."
  (with-builtins-source (output code context
                                 '("function foo; echo hi; end; foo"))
    (is (= 0 code))
    (is (string= (format nil "hi~%") output))
    (is (equal '("echo hi")
               (gethash "foo"
                        (nshell.application:shell-context-function-table
                         context))))))

(test source-switch-case-executes-matching-clause
  "source executes fish-style switch/case blocks."
  (with-builtins-source (output code context
                                 '("switch chocolate"
                                   "case vanilla"
                                   "echo plain"
                                   "case chocolate strawberry"
                                   "echo sweet"
                                   "case '*'"
                                   "echo default"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "sweet~%") output))))

(test source-switch-case-matches-later-pattern-in-clause
  "source matches every fish-style pattern listed on a single case clause."
  (with-builtins-source (output code context
                                 '("switch strawberry"
                                   "case vanilla chocolate"
                                   "echo plain"
                                   "case mint strawberry"
                                   "echo sweet"
                                   "case '*'"
                                   "echo default"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "sweet~%") output))))

(test source-switch-case-supports-default-pattern
  "source executes the default switch/case clause when no exact pattern matches."
  (with-builtins-source (output code context
                                 '("switch mint"
                                   "case vanilla"
                                   "echo plain"
                                   "case chocolate strawberry"
                                   "echo sweet"
                                   "case '*'"
                                   "echo default"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "default~%") output))))

(test source-switch-case-supports-glob-patterns
  "source switch/case patterns use the same glob semantics as expansion."
  (with-builtins-source (output code context
                                 '("switch plugin42.lisp"
                                   "case '*.md'"
                                   "echo markdown"
                                   "case 'plugin[0-9][0-9].lisp'"
                                   "echo lisp"
                                   "case '*'"
                                   "echo default"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "lisp~%") output))))

(test source-if-supports-not-command-modifier
  "source lets fish-style if conditions invert command status with not."
  (with-builtins-source (output code context
                                 '("if not test -f /tmp/file.txt"
                                   "echo missing"
                                   "else"
                                   "echo exists"
                                   "end"
                                   "if not test -f /tmp/missing"
                                   "echo absent"
                                   "else"
                                   "echo present"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "exists~%absent~%") output))))

(test source-if-supports-else-if-branches
  "source treats fish-style else if as a nested conditional branch."
  (with-builtins-source (output code context
                                 '("if false"
                                   "echo first"
                                   "else if false"
                                   "echo second"
                                   "else"
                                   "echo fallback"
                                   "end"
                                   "if false"
                                   "echo skip"
                                   "else if true"
                                   "echo nested"
                                   "end"))
    (is (= 0 code))
    (is (string= (format nil "fallback~%nested~%") output))))

(test source-command-substitution-expands-function-output
  "source expands fish-style command substitutions and splits output on newlines."
  (with-builtins-source (output code context
                                 '("function produce"
                                   "echo alpha"
                                   "echo beta"
                                   "end"
                                   "echo before (produce) after"))
    (is (= 0 code))
    (is (string= (format nil "before alpha beta after~%") output))))

(test source-command-substitution-expands-inside-double-quotes
  "source supports embedded command substitutions inside double-quoted words."
  (with-builtins-source (output code context
                                 '("echo \"file-(echo main).lisp\""))
    (is (= 0 code))
    (is (string= (format nil "file-main.lisp~%") output))))

(test source-command-substitution-expands-inside-compound-word
  "source keeps fish-style command substitutions attached to compound words."
  (with-builtins-source (output code context
                                 '("echo prefix=(echo main).lisp suffix=(echo ok)"))
    (is (= 0 code))
    (is (string= (format nil "prefix=main.lisp suffix=ok~%") output))))

(test source-command-substitution-expands-external-output
  "source expands external command substitution output when capture is available."
  (let ((context (make-test-builtins-context
                  :external-capture-runner
                  (lambda (command args)
                    (is (string= "capture-values" command))
                    (is (null args))
                    (values (format nil "red~%blue~%") 0)))))
    (with-called-source (output code context
                                '("echo before (capture-values) after"))
      (is (= 0 code))
      (is (string= (format nil "before red blue after~%") output)))))

(test source-command-substitution-keeps-non-substitution-dollar-literal
  "source keeps a dollar that is neither arithmetic nor command substitution."
  (with-builtins-source (output code context
                                 '("echo price$"))
    (is (= 0 code))
    (is (string= (format nil "price$~%") output))))

(test source-command-substitution-keeps-single-quoted-words-literal
  "source does not expand command substitutions in single-quoted words."
  (with-builtins-source (output code context
                                 '("echo '(echo nope)'"))
    (is (= 0 code))
    (is (string= (format nil "(echo nope)~%") output))))

(test source-expands-command-position-word
  "source expands variables in command position before dispatch."
  (with-builtins-context-environment
      (context (make-test-builtins-context)
               ("CMD" "echo"))
    (with-called-source (output code context '("$CMD command-word"))
      (is (= 0 code))
      (is (string= (format nil "command-word~%") output)))))

(test source-expands-double-quoted-command-position-word
  "source expands double-quoted variables in command position as a single field."
  (with-builtins-context-environment
      (context (make-test-builtins-context)
               ("CMD" "echo"))
    (with-called-source (output code context '("\"$CMD\" quoted-command-word"))
      (is (= 0 code))
      (is (string= (format nil "quoted-command-word~%") output)))))

(test source-keeps-single-quoted-command-position-word-literal
  "Single-quoted command words remain literal and are not variable-expanded."
  (let ((seen nil))
    (with-builtins-context-environment
        (context (make-test-builtins-context
                  :external-runner
                  (lambda (command args)
                    (setf seen (cons command args))
                    127))
                 ("CMD" "echo"))
      (with-called-source (output code context '("'$CMD' command-word"))
        (is (= 127 code))
        (is (string= "" output))
        (is (equal '("$CMD" "command-word") seen))))))

(test source-rejects-multi-field-command-position-expansion
  "source should not dispatch an ambiguous expanded command name."
  (with-builtins-context-environment
      (context (make-test-builtins-context)
               ("CMD" "echo split"))
    (with-called-source (output code context '("$CMD command-word"))
      (is (= 127 code))
      (is (string= (format nil "nshell: $CMD: command name expansion produced 2 fields~%")
                   output)))))

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

(test source-pipeline-feeds-builtin-output-to-read
  "source executes builtin pipeline stages in the current shell context."
  (with-builtins-source (output code context
                                 '("echo piped-value | read captured"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "piped-value"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-feeds-function-output-to-read
  "source lets fish-style functions participate in pipelines."
  (with-builtins-source (output code context
                                 '("function produce"
                                   "echo function-value"
                                   "end"
                                   "produce | read captured"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "function-value"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-redirects-builtin-output
  "source supports redirection on builtin pipeline stages."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-redirect")
    (let ((target (merge-pathnames "out.txt" root)))
      (write-test-lines source
                        (list (format nil "echo redirected > ~a"
                                      (namestring target))))
      (multiple-value-bind (output code)
          (call-source-file context source)
        (is (string= "" output))
        (is (= 0 code))
        (is (string= "redirected" (read-test-file-line target)))))))

(test source-pipeline-redirects-function-output
  "source redirects fish-style function output from pipeline stages."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-function-redirect")
    (let ((target (merge-pathnames "function.txt" root)))
      (write-test-lines source
                        (list "function produce"
                              "echo function-redirected"
                              "end"
                              (format nil "produce > ~a" (namestring target))))
      (multiple-value-bind (output code)
          (call-source-file context source)
        (is (string= "" output))
        (is (= 0 code))
        (is (string= "function-redirected"
                     (read-test-file-line target)))))))

(test source-pipeline-redirects-internal-stderr-to-file
  "source applies 2> to stderr written by internal commands."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-stderr-redirect")
    (let ((target (merge-pathnames "stderr.txt" root)))
      (write-test-lines source
                        (list (format nil "errcmd 2> ~a" (namestring target))))
      (with-temporary-function
          ('nshell.application::%execute-command-by-name-in-context
           (lambda (_context command args)
             (declare (ignore _context args))
             (when (string= command "errcmd")
               (write-line "stderr-line" *error-output*)
               (values (format nil "stdout-line~%") 7))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (is (= 7 code))
          (is (string= (format nil "stdout-line~%") output))
          (is (string= "stderr-line" (read-test-file-line target))))))))

(test source-pipeline-ampersand-redirects-internal-stdout-and-stderr
  "source applies &> to both stdout and stderr from internal commands."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-amp-redirect")
    (let ((target (merge-pathnames "combined.txt" root)))
      (write-test-lines source
                        (list (format nil "errcmd &> ~a" (namestring target))))
      (with-temporary-function
          ('nshell.application::%execute-command-by-name-in-context
           (lambda (_context command args)
             (declare (ignore _context args))
             (when (string= command "errcmd")
               (write-line "stderr-line" *error-output*)
               (values (format nil "stdout-line~%") 7))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (let ((contents (uiop:read-file-string target)))
            (is (= 7 code))
            (is (string= "" output))
            (is (search "stdout-line" contents))
            (is (search "stderr-line" contents))))))))

(test source-pipeline-redirects-internal-stderr-to-stdout
  "source applies 2>&1 after stdout has been redirected."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-stderr-to-stdout")
    (let ((target (merge-pathnames "combined.txt" root)))
      (write-test-lines source
                        (list (format nil "errcmd > ~a 2>&1" (namestring target))))
      (with-temporary-function
          ('nshell.application::%execute-command-by-name-in-context
           (lambda (_context command args)
             (declare (ignore _context args))
             (when (string= command "errcmd")
               (write-line "stderr-line" *error-output*)
               (values (format nil "stdout-line~%") 7))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (let ((contents (uiop:read-file-string target)))
            (is (= 7 code))
            (is (string= "" output))
            (is (search "stdout-line" contents))
            (is (search "stderr-line" contents))))))))

(test source-pipeline-here-string-feeds-builtin-stdin
  "source applies here-strings to builtin pipeline stages."
  (with-builtins-source (output code context
                                 '("read captured <<< inline-value"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "inline-value"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-here-document-feeds-builtin-stdin
  "source accumulates here-document bodies before executing the command."
  (with-builtins-source (output code context
                                 '("read captured << EOF"
                                   "inline-doc"
                                   "EOF"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "inline-doc"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-here-document-continues-after-delimiter
  "source leaves commands after a here-document delimiter for normal execution."
  (with-builtins-source (output code context
                                 '("read captured << EOF"
                                   "inline-doc"
                                   "EOF"
                                   "echo after"))
    (is (string= (format nil "after~%") output))
    (is (= 0 code))
    (is (string= "inline-doc"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-input-redirect-overrides-pipe-input
  "source applies input redirects on builtin pipeline stages."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-input-redirect")
    (let ((input (merge-pathnames "input.txt" root)))
      (write-test-lines input '("from-file"))
      (write-test-lines source
                        (list (format nil "echo from-pipe | read captured < ~a"
                                      (namestring input))))
      (multiple-value-bind (output code)
          (call-source-file context source)
        (is (string= "" output))
        (is (= 0 code))
        (is (string= "from-file"
                     (nshell.domain.environment:env-get
                      (nshell.application:shell-context-environment context)
                      "captured")))))))

(test source-pipeline-uses-source-strategy-for-external-pipelines
  "source keeps external pipelines on the source execution path when strategy is :cps."
  (skip-in-sandbox "executes /bin/echo and /bin/cat"
  (let ((context (make-test-builtins-context)))
    (setf (nshell.application:shell-context-execution-strategy context) :cps)
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-pipeline
         (lambda (&rest _args)
           (declare (ignore _args))
           (error "spawn-pipeline should not run for :cps")))
      (with-called-source (output code context
                                  '("/bin/echo cps-strategy | /bin/cat"))
        (is (= 0 code))
        (is (string= (format nil "cps-strategy~%") output)))))))

(test source-pipeline-uses-os-pipes-strategy-for-external-pipelines
  "source dispatches external pipelines to spawn-pipeline when strategy is :os-pipes."
  (let ((context (make-test-builtins-context))
        (called nil)
        (command-count nil)
        (captured-redirects nil))
    (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-pipeline
         (lambda (commands &key redirects)
           (setf called t
                 command-count (length commands)
                 captured-redirects redirects)
           (format t "spawned-path~%")
           37))
      (with-called-source (output code context
                                  '("/bin/echo os-pipes-strategy | /bin/cat"))
        (is (not (null called)))
        (is (= 2 command-count))
        (is (listp captured-redirects))
        (is (= 37 code))
        (is (string= (format nil "spawned-path~%") output))))))

(test source-pipeline-keeps-internal-commands-on-source-path-under-os-pipes
  "source still executes pipelines with internal commands through the source path even when strategy is :os-pipes."
  (let ((context (make-test-builtins-context)))
    (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-pipeline
         (lambda (&rest _args)
           (declare (ignore _args))
           (error "spawn-pipeline should not run for internal commands")))
      (with-called-source (output code context
                                  '("echo internal-value | read captured"))
        (is (= 0 code))
        (is (string= "" output))
        (is (string= "internal-value"
                     (nshell.domain.environment:env-get
                      (nshell.application:shell-context-environment context)
                      "captured")))))))

(test pbt-source-pipeline-keeps-external-only-pipelines-on-source-path-under-cps
  "Generated external-only pipelines stay on the source path when strategy is :cps."
  (skip-in-sandbox "executes /bin/echo and /bin/cat"
  (check-property (:trials 50)
      ((payload (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text))
    (let ((context (make-test-builtins-context))
          (spawned nil))
      (setf (nshell.application:shell-context-execution-strategy context) :cps)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (&rest _args)
             (declare (ignore _args))
             (setf spawned t)
             (error "spawn-pipeline should not run for :cps")))
        (with-called-source (output code context
                                (list (format nil "/bin/echo ~a | /bin/cat" payload)))
          (is (not spawned))
          (is (= 0 code))
          (is (string= (format nil "~a~%" payload) output))))))))

(test pbt-source-pipeline-routes-external-only-pipelines-to-spawn-pipeline-under-os-pipes
  "Generated external-only pipelines route through spawn-pipeline when strategy is :os-pipes."
  (check-property (:trials 50)
      ((payload (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text))
    (let ((context (make-test-builtins-context))
          (called nil))
      (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (commands &key redirects)
             (setf called t)
             (is (= 2 (length commands)))
             (is (listp redirects))
             (format t "spawned-path~%")
             37))
        (with-called-source (output code context
                                (list (format nil "/bin/echo ~a | /bin/cat" payload)))
          (is (not (null called)))
          (is (= 37 code))
          (is (search "spawned-path" output)))))))
