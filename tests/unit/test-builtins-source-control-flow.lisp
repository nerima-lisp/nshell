(in-package #:nshell/test)
(in-suite builtin-tests)

(test source-function-body-supports-nested-control-flow
  "source keeps nested blocks inside function definitions instead of closing at the first end."
  (with-builtins-source-ok (output code context
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
      (format nil "function-inner~%function-after~%script-after~%")
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
  (with-builtins-source-ok (output code context
                                   '("function foo; echo hi; end"
                                     "foo"))
      (format nil "hi~%")
    (is (equal '("echo hi")
               (gethash "foo"
                        (nshell.application:shell-context-function-table
                         context))))))

(test source-function-definition-preserves-trailing-inline-commands
  "source keeps commands that follow an inline function definition on the same line."
  (with-builtins-source-ok (output code context
                                   '("function foo; echo hi; end; foo"))
      (format nil "hi~%")
    (is (equal '("echo hi")
               (gethash "foo"
                        (nshell.application:shell-context-function-table
                         context))))))

(test source-switch-case-executes-matching-clause
  "source executes fish-style switch/case blocks."
  (with-builtins-source-ok (output code context
                                   '("switch chocolate"
                                     "case vanilla"
                                     "echo plain"
                                     "case chocolate strawberry"
                                     "echo sweet"
                                     "case '*'"
                                     "echo default"
                                     "end"))
      (format nil "sweet~%")))

(test source-switch-case-matches-later-pattern-in-clause
  "source matches every fish-style pattern listed on a single case clause."
  (with-builtins-source-ok (output code context
                                   '("switch strawberry"
                                     "case vanilla chocolate"
                                     "echo plain"
                                     "case mint strawberry"
                                     "echo sweet"
                                     "case '*'"
                                     "echo default"
                                     "end"))
      (format nil "sweet~%")))

(test source-switch-case-supports-default-pattern
  "source executes the default switch/case clause when no exact pattern matches."
  (with-builtins-source-ok (output code context
                                   '("switch mint"
                                     "case vanilla"
                                     "echo plain"
                                     "case chocolate strawberry"
                                     "echo sweet"
                                     "case '*'"
                                     "echo default"
                                     "end"))
      (format nil "default~%")))

(test source-switch-case-supports-glob-patterns
  "source switch/case patterns use the same glob semantics as expansion."
  (with-builtins-source-ok (output code context
                                   '("switch plugin42.lisp"
                                     "case '*.md'"
                                     "echo markdown"
                                     "case 'plugin[0-9][0-9].lisp'"
                                     "echo lisp"
                                     "case '*'"
                                     "echo default"
                                     "end"))
      (format nil "lisp~%")))

(test source-if-supports-not-command-modifier
  "source lets fish-style if conditions invert command status with not."
  (with-builtins-source-ok (output code context
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
      (format nil "exists~%absent~%")))

(test source-if-supports-else-if-branches
  "source treats fish-style else if as a nested conditional branch."
  (with-builtins-source-ok (output code context
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
      (format nil "fallback~%nested~%")))

(test source-command-substitution-expands-function-output
  "source expands fish-style command substitutions and splits output on newlines."
  (with-builtins-source-ok (output code context
                                   '("function produce"
                                     "echo alpha"
                                     "echo beta"
                                     "end"
                                     "echo before (produce) after"))
      (format nil "before alpha beta after~%")))

(test source-command-substitution-expands-inside-double-quotes
  "source supports embedded command substitutions inside double-quoted words."
  (with-builtins-source-ok (output code context
                                   '("echo \"file-(echo main).lisp\""))
      (format nil "file-main.lisp~%")))

(test source-command-substitution-expands-inside-compound-word
  "source keeps fish-style command substitutions attached to compound words."
  (with-builtins-source-ok (output code context
                                   '("echo prefix=(echo main).lisp suffix=(echo ok)"))
      (format nil "prefix=main.lisp suffix=ok~%")))

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
  (with-builtins-source-ok (output code context
                                   '("echo price$"))
      (format nil "price$~%")))

(test source-command-substitution-keeps-single-quoted-words-literal
  "source does not expand command substitutions in single-quoted words."
  (with-builtins-source-ok (output code context
                                   '("echo '(echo nope)'"))
      (format nil "(echo nope)~%")))

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

(test source-if-without-else-returns-zero-on-failure
  "if with a failing condition and no else branch exits 0 with no output."
  (with-builtins-source-ok (output code context
                                   '("if false"
                                     "echo should-not-run"
                                     "end"))
      ""))

(test source-switch-case-no-match-returns-zero
  "switch with no matching clause exits 0 with no output."
  (with-builtins-source-ok (output code context
                                   '("switch unmatched"
                                     "case vanilla"
                                     "echo vanilla"
                                     "case chocolate"
                                     "echo chocolate"
                                     "end"))
      ""))

(test source-begin-end-executes-body-in-current-context
  "begin/end runs its body and accumulates output like an inline block."
  (with-builtins-source-ok (output code context
                                   '("begin"
                                     "echo first"
                                     "echo second"
                                     "end"))
      (format nil "first~%second~%")))

(test source-for-with-empty-values-runs-no-iterations
  "for loop with no in-values iterates zero times, producing no output."
  (with-builtins-source-ok (output code context
                                   '("for x in"
                                     "echo $x"
                                     "end"))
      ""))

(test source-for-loop-updates-current-environment
  "for loop assignment updates the current shell environment for following commands."
  (with-builtins-source-ok (output code context
                                   '("for item in first second"
                                     "end"
                                     "echo $item"))
      (format nil "second~%")
    (is (equal "second"
               (nshell.domain.environment:env-get
                (nshell.application:shell-context-environment context)
                "item")))))
