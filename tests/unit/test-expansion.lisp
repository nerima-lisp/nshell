(in-package #:nshell/test)

(def-suite expansion-tests
  :description "Shell expansion tests"
  :in nshell-tests)

(in-suite expansion-tests)

(defun test-expansion-env ()
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "FOO" "bar" nil))
    (setf env (nshell.domain.environment:env-set env "HOME" "/tmp/nshell-home" nil))
    env))

(defmacro %assert-expansion-cases ((predicate builder) &body cases)
  "Assert CASES against BUILDER using PREDICATE.

Each case is (EXPECTED INPUT &rest ARGS)."
  (let ((expander (gensym "EXPANDER-")))
    `(let ((,expander ,builder))
       ,@(mapcar (lambda (case)
                   (destructuring-bind (expected &rest args) case
                     `(is (,predicate ',expected (funcall ,expander ,@args)))))
                 cases))))

(defmacro %assert-expansion-cases-with-env ((predicate expander env-form) &body cases)
  "Assert CASES against an EXPANDER that takes INPUT and ENV."
  (let ((input (gensym "INPUT-"))
        (env (gensym "ENV-"))
        (expander-fn (gensym "EXPANDER-")))
    `(let ((,env ,env-form)
           (,expander-fn ,expander))
       (%assert-expansion-cases (,predicate
                                 (lambda (,input)
                                   (funcall ,expander-fn ,input ,env)))
         ,@cases))))

(defmacro %assert-quote-style-dispatch-case (style expected branch)
  `(let ((observed-branch nil))
     (is (equal ,expected
                (nshell.domain.expansion:expand-by-quote-style
                 ,style
                 (progn (setf observed-branch :unquoted) '("unquoted"))
                 (progn (setf observed-branch :single) '("single"))
                 (progn (setf observed-branch :double) '("double")))))
     (is (eq ,branch observed-branch))))

(test dollar-var-expansion
  "$VAR expands using the shell environment."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-variables
                                     (test-expansion-env))
    ("value=bar" "value=$FOO")))

(test braced-var-expansion
  "${VAR} expands using the shell environment."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-variables
                                     (test-expansion-env))
    ("value=bar" "value=${FOO}")))

(test tilde-expansion
  "A leading tilde expands to HOME."
  (is (string= "/tmp/nshell-home/src"
               (nshell.domain.expansion:expand-tilde "~/src" (test-expansion-env)))))

(test double-quoted-expands-variables
  "Double-quoted contents expand $VAR but stay a single field."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-double-quoted
                                     (test-expansion-env))
    ("value=bar" "value=$FOO")))

(test quote-style-dispatch-selects-forms
  "Quote-style dispatch should evaluate exactly one branch."
  (dolist (case '((nil ("unquoted") :unquoted)
                  (:single ("single") :single)
                  (:double ("double") :double)))
    (destructuring-bind (style expected branch) case
      (%assert-quote-style-dispatch-case style expected branch))))

(test quote-style-dispatch-rejects-invalid-style
  "Quote-style dispatch should reject invalid styles."
  (signals error
    (nshell.domain.expansion:expand-by-quote-style
     :bogus
     '("unquoted")
     '("single")
     '("double"))))

(test command-name-fields-by-quote-style
  "Command-name expansion stays a single field unless unquoted $-expansion needs splitting."
  (let ((env (test-expansion-env)))
    (%assert-expansion-cases (equal
                              (lambda (input quote-style)
                                (nshell.domain.expansion:expand-command-name-fields-by-quote-style
                                 input quote-style env)))
      (("echo" "bar") "echo $FOO" nil)
      (("echo bar") "echo $FOO" :double)
      (("literal") "literal" nil))))

(test argv-and-indexed-argv-expansion
  "$argv joins args with spaces; $argv[N] selects one (fish-style, 1-based)."
  (let ((env (test-expansion-env))
        (nshell.domain.expansion:*positional-args* '("alpha" "beta" "gamma")))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("alpha beta gamma" "$argv")
      ("alpha" "$argv[1]")
      ("gamma" "$argv[3]")
      ("" "$argv[5]")
      ("gamma" "$argv[-1]")
      ("alpha beta" "$argv[1..2]")
      ("beta gamma" "$argv[2..-1]")
      ("gamma beta alpha" "$argv[-1..1]")
      ("x-beta-y" "x-$argv[2]-y")))
  (let ((env (test-expansion-env)))
    ;; With no args bound, $argv expands to empty; $1 stays literal (fish).
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("" "$argv")
      ("$1" "$1"))))

(test argv-list-compound-expansion
  "Unquoted $argv list references expand as compound field fragments."
  (let ((env (test-expansion-env))
        (nshell.domain.expansion:*positional-args* '("alpha" "beta" "gamma")))
    (%assert-expansion-cases-with-env (equal
                                       #'nshell.domain.expansion:expand-all
                                       env)
      (("pre-alpha.txt" "pre-beta.txt") "pre-$argv[1..2].txt")
      (("alpha-beta" "alpha-gamma" "beta-beta" "beta-gamma")
       "$argv[1..2]-$argv[2..3]"))
    (let ((nshell.domain.expansion:*positional-args* '("literal-$FOO")))
      (%assert-expansion-cases-with-env (equal
                                         #'nshell.domain.expansion:expand-all
                                         env)
        (("pre-literal-$FOO") "pre-$argv[1]")))
    (%assert-expansion-cases-with-env (equal
                                       #'nshell.domain.expansion:expand-all
                                       env)
      (("missing-") "missing-$argv[9]"))))

(test variable-list-compound-expansion
  "Unquoted indexed variables expand as compound field fragments."
  (let ((env (nshell.domain.environment:env-set-values
              (test-expansion-env)
              "LIST"
              '("alpha" "beta" "gamma")
              nil)))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("beta" "$LIST[2]")
      ("alpha beta" "$LIST[1..2]"))
    (%assert-expansion-cases-with-env (equal
                                       #'nshell.domain.expansion:expand-all
                                       env)
      (("pre-alpha.txt" "pre-beta.txt") "pre-$LIST[1..2].txt")
      (("alpha-beta" "alpha-gamma" "beta-beta" "beta-gamma")
       "$LIST[1..2]-$LIST[2..3]"))
    (let ((env (nshell.domain.environment:env-set-values
                env
                "LIST"
                '("literal-$FOO" "beta")
                nil)))
      (%assert-expansion-cases-with-env (equal
                                         #'nshell.domain.expansion:expand-all
                                         env)
        (("pre-literal-$FOO") "pre-$LIST[1]")))
    (%assert-expansion-cases-with-env (equal
                                       #'nshell.domain.expansion:expand-all
                                       env)
      (("missing-") "missing-$LIST[9]"))))

(test variable-list-expansion-preserves-spaces-inside-elements
  "Indexed variables use structured list elements instead of splitting scalar text."
  (let ((env (nshell.domain.environment:env-set-values
              (test-expansion-env)
              "FILES"
              '("hello world" "tail")
              nil)))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("hello world" "$FILES[1]"))
    (%assert-expansion-cases-with-env (equal
                                       #'nshell.domain.expansion:expand-all
                                       env)
      (("pre-hello world.txt" "pre-tail.txt") "pre-$FILES[1..2].txt"))))

(test double-quoted-expands-arithmetic
  "Arithmetic $((...)) is evaluated inside double quotes (POSIX)."
  (let ((env (test-expansion-env)))            ; FOO = bar
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-double-quoted
                                       env)
      ("sum=7" "sum=$((3 + 4))")
      ("bar-3" "$FOO-$((1+2))"))))

(test double-quoted-suppresses-globbing
  "Double-quoted contents must not be glob-expanded."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-double-quoted
                                     (test-expansion-env))
    ("*" "*")
    ("a*b?c" "a*b?c")))

(test parameter-default-when-unset
  "${VAR:-word} yields the value when set and the word when unset/empty."
  (let ((env (test-expansion-env)))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("bar" "${FOO:-fallback}")
      ("fallback" "${MISSING:-fallback}")
      ("bar" "${MISSING:-$FOO}"))))

(test parameter-alternative-when-set
  "${VAR:+word} yields the word only when the variable is set and non-empty."
  (let ((env (test-expansion-env)))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("yes" "${FOO:+yes}")
      ("" "${MISSING:+yes}"))))

(test parameter-assign-default-side-effect
  "${VAR:=word} assigns the expanded default only when the operator fires."
  (let ((source-env (test-expansion-env))
        (env (nshell.domain.environment:make-environment)))
    (is (string= "bar"
                 (nshell.domain.expansion:expand-variables
                  "${MISSING:=$FOO}" source-env)))
    (is (string= "bar"
                 (nshell.domain.environment:env-get source-env "MISSING")))
    (is (string= "default"
                 (nshell.domain.expansion:expand-variables
                  "${MISSING:=default}" env)))
    (is (string= "default"
                 (nshell.domain.environment:env-get env "MISSING")))
    (is (string= "default"
                 (nshell.domain.expansion:expand-variables
                  "${MISSING:=other}" env)))
    (is (string= "default"
                 (nshell.domain.environment:env-get env "MISSING")))))

(test parameter-assign-default-preserves-export-state
  "${VAR:=word} keeps an existing variable's exported state when assigning."
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "EMPTY" "" t))
    (is (string= "filled"
                 (nshell.domain.expansion:expand-variables
                  "${EMPTY:=filled}" env)))
    (is (equal '(("EMPTY" . "filled"))
               (nshell.domain.environment:env-list env)))))

(test parameter-length
  "${#VAR} yields the length of the variable's value."
  (let ((env (test-expansion-env)))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("3" "${#FOO}")
      ("0" "${#MISSING}"))))

(test parameter-prefix-and-suffix-strip
  "${VAR#pat} / ## strip a prefix; ${VAR%pat} / %% strip a suffix (glob)."
  (let ((env (test-expansion-env)))            ; FOO = bar
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("ar" "${FOO#b}")
      ("r" "${FOO##*a}")
      ("ba" "${FOO%r}")
      ("b" "${FOO%%a*}")
      ("3" "${#FOO}"))))

(test parameter-substitution-operator
  "${VAR/pat/rep} replaces the first match; // replaces all (literal)."
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "P" "a-a-a" nil))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("X-a-a" "${P/a/X}")
      ("X-X-X" "${P//a/X}")
      ("a-a-a" "${P/z/X}"))))

(test parameter-plain-brace-still-works
  "Plain ${VAR} expansion is unchanged by the operator support."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-variables
                                     (test-expansion-env))
    ("value=bar" "value=${FOO}")))

(defun arith-env ()
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "X" "10" nil))
    (setf env (nshell.domain.environment:env-set env "Y" "3" nil))
    env))

