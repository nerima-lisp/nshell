(in-package #:nshell/test)

(describe "builtin-tests"
  (it "source-function-body-supports-nested-control-flow"
    "source preserves nested conditional control flow in an S-expression shell function."
    (with-builtins-source-ok (output code context
                                     '("(define-shell-function nested () (if t (echo function-inner) (echo function-else)) (echo function-after))"
                                       "(nested)"
                                       "(echo script-after)"))
        (format nil "function-inner~%function-after~%script-after~%")
      (expect t :to-equal
              (nth-value 1
                         (nshell.application:lookup-shell-function
                          (nshell.application:context-shell-function-registry context)
                          "nested")))))

  (it "source-switch-case-executes-matching-clause"
    "source uses S-expression case to execute the matching clause."
    (with-builtins-source-ok (output code context
                                     '("(case 2 ((1) (echo plain)) ((2 3) (echo sweet)) (otherwise (echo default)))"))
        (format nil "sweet~%")))

  (it "source-switch-case-matches-later-pattern-in-clause"
    "source case matches any listed exact selector in a clause."
    (with-builtins-source-ok (output code context
                                     '("(case 3 ((1 2) (echo plain)) ((2 3) (echo sweet)) (otherwise (echo default)))"))
        (format nil "sweet~%")))

  (it "source-switch-case-supports-default-pattern"
    "source case executes its otherwise clause when no exact selector matches."
    (with-builtins-source-ok (output code context
                                     '("(case 4 ((1) (echo plain)) ((2 3) (echo sweet)) (otherwise (echo default)))"))
        (format nil "default~%")))

  (it "source-reader-string-match-supports-glob-patterns"
    "source string match uses the shell glob matcher through the S-expression reader."
    (with-builtins-source-ok (output code context
                                     '("(if (= 0 (string match -q \"plugin[0-9][0-9].lisp\" \"plugin42.lisp\")) (echo lisp) (echo default))"))
        (format nil "lisp~%")))

  (it "source-if-supports-not-command-modifier"
    "source evaluates not around command tests in S-expression conditionals."
    (with-builtins-source-ok (output code context
                                     '("(progn (if (not (= 0 (test -f \"/etc/hosts\"))) (echo missing) (echo exists)) (if (not (= 0 (test -f \"/definitely/not/a/nshell-file\"))) (echo absent) (echo present)))"))
        (format nil "exists~%absent~%")))

  (it "source-if-supports-else-if-branches"
    "source represents else-if branches as nested S-expression conditionals."
    (with-builtins-source-ok (output code context
                                     '("(progn (if (not t) (echo first) (if (not t) (echo second) (echo fallback))) (if (not t) (echo skip) (if t (echo nested))))"))
        (format nil "fallback~%nested~%")))

  (it "source-command-substitution-expands-sexp-function-output"
    "source expands S-expression function output in command substitutions and splits output on newlines."
    (with-builtins-source-ok
        (output code context
                (list "(define-shell-function produce () (echo alpha) (echo beta))"
                      "echo before (produce) after"))
      (format nil "before alpha beta after~%")))

  (it "source-command-substitution-expands-inside-double-quotes"
    "source supports embedded command substitutions inside double-quoted words."
    (with-builtins-source-ok (output code context
                                     '("echo \"file-$(echo main).lisp\""))
        (format nil "file-main.lisp~%")))

  (it "source-command-substitution-expands-inside-compound-word"
    "source keeps fish-style command substitutions attached to compound words."
    (with-builtins-source-ok (output code context
                                     '("echo prefix=(echo main).lisp suffix=(echo ok)"))
        (format nil "prefix=main.lisp suffix=ok~%")))

  (it "source-command-substitution-expands-external-output"
    "source expands external command substitution output when capture is available."
    (let ((context (make-test-builtins-context)))
      (with-test-external-capture-runner
          (lambda (command args)
            (expect "capture-values" :to-equal command)
            (expect args :to-be-null)
            (values (format nil "red~%blue~%") 0))
        (with-called-source (output code context
                                    '("echo before (capture-values) after"))
          (expect 0 :to-equal code)
          (expect (format nil "before red blue after~%") :to-equal output)))))

  (it "source-command-substitution-keeps-non-substitution-dollar-literal"
    "source keeps a dollar that is neither arithmetic nor command substitution."
    (with-builtins-source-ok (output code context
                                     '("echo price$"))
        (format nil "price$~%")))
  (it "source-command-substitution-reads-later-sexp-lines-after-bare-line"
    "source reads multiline command substitution lines with their own reader context."
    (let ((context (make-test-builtins-context)))
      (expect (format nil "bare-line~%sexp-line")
              :to-equal
              (nshell.application::%execute-command-substitution-output
               context
               (format nil "echo bare-line~%(progn (echo sexp-line))")))))

  (it "source-command-substitution-keeps-single-quoted-words-literal"
    "source does not expand command substitutions in single-quoted words."
    (with-builtins-source-ok (output code context
                                     '("echo '(echo nope)'"))
        (format nil "(echo nope)~%")))

  (it "source-expands-command-position-word"
    "source expands variables in command position before dispatch."
    (with-builtins-context-environment
        (context (make-test-builtins-context)
                 ("CMD" "echo"))
      (with-called-source (output code context '("$CMD command-word"))
        (expect 0 :to-equal code)
        (expect (format nil "command-word~%") :to-equal output))))

  (it "source-expands-double-quoted-command-position-word"
    "source expands double-quoted variables in command position as a single field."
    (with-builtins-context-environment
        (context (make-test-builtins-context)
                 ("CMD" "echo"))
      (with-called-source (output code context '("\"$CMD\" quoted-command-word"))
        (expect 0 :to-equal code)
        (expect (format nil "quoted-command-word~%") :to-equal output))))

  (it "source-reader-keeps-escaped-command-name-literal"
    "Escaped S-expression command heads remain literal and are not variable-expanded."
    (let* ((seen nil)
           (context (make-test-builtins-context)))
      (setf (nshell.application:shell-context-environment context)
            (nshell.domain.environment:env-set
             (nshell.application:shell-context-environment context)
             "CMD" "echo" t))
      (with-stubbed-command-builtin
          (("$CMD"
            (expect (list "command-word") :to-equal *stubbed-command-builtin-arguments*)
            (setf seen t)
            (values "" 0)))
        (multiple-value-bind (output code)
            (nshell.application:source-lines
             context (list "(|$CMD| command-word)"))
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect t :to-equal seen)))))

  (it "source-rejects-computed-command-heads-in-reader-pipelines"
    "source rejects computed S-expression pipeline stage heads."
    (let ((condition
            (handler-case
                (progn
                  (nshell.application:source-lines
                   (make-test-builtins-context)
                   '("(| (cat) ((computed) arg))"))
                  nil)
              (nshell.domain.parsing:sexp-reader-error (condition)
                condition))))
      (expect condition :to-be-truthy)))

  (it "source-if-without-else-returns-zero-on-failure"
    "an S-expression if with a false value test and no alternate returns zero without output."
    (with-builtins-source-ok (output code context
                                     '("(if (not t) (echo should-not-run))"))
        ""))

  (it "source-switch-case-no-match-returns-zero"
    "source case with no matching clause returns zero and emits no output."
    (with-builtins-source-ok (output code context
                                     '("(case 9 ((1) (echo vanilla)) ((2) (echo chocolate)))"))
        ""))

  (it "source-begin-end-executes-body-in-current-context"
    "source progn runs its body in the current shell context."
    (with-builtins-source-ok (output code context
                                     '("(progn (echo first) (echo second))"))
        (format nil "first~%second~%")))

  (it "source-for-with-empty-values-runs-no-iterations"
    "dolist over an empty list runs no body iterations and emits no output."
    (with-builtins-source-ok (output code context
                                     '("(dolist (x (list)) (echo ,x))"))
        ""))

  (it "source-for-loop-updates-current-environment"
    "dolist can update the current shell environment for following commands."
    (with-builtins-source-ok (output code context
                                     '("(progn (dolist (item '(\"first\" \"second\")) (set item ,item)) (echo $item))"))
        (format nil "second~%")
      (expect "second" :to-equal (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "item")))))
(describe "legacy-source-function-reader-tests"
  (it "source-function-definition-supports-inline-body"
    "source registers functions defined on a single line with an inline body."
    (with-builtins-source-ok (output code context
                                     '("function foo; echo hi; end"
                                       "foo"))
        (format nil "hi~%")
      (expect '("echo hi") :to-equal
              (gethash "foo"
                       (nshell.application:shell-context-function-table
                        context)))))
  (it "source-function-definition-preserves-trailing-inline-commands"
    "source keeps commands that follow an inline function definition on the same line."
    (with-builtins-source-ok (output code context
                                     '("function foo; echo hi; end; foo"))
        (format nil "hi~%")
      (expect '("echo hi") :to-equal
              (gethash "foo"
                       (nshell.application:shell-context-function-table
                        context))))))

