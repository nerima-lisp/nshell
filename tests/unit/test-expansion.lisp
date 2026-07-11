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

(defmacro %assert-multiple-value-cases ((predicate builder) &body cases)
  "Assert CASES against a BUILDER that returns multiple values."
  (let ((expander (gensym "EXPANDER-")))
    `(let ((,expander ,builder))
       ,@(mapcar (lambda (case)
                   (destructuring-bind (expected &rest args) case
                     `(is (,predicate ',expected
                                      (multiple-value-list
                                       (funcall ,expander ,@args))))))
                 cases))))

(defmacro %assert-quote-style-dispatch-case (style expected branch)
  `(let ((observed-branch nil))
     (is (equal ,expected
                 (nshell.domain.expansion:expand-by-quote-style
                  ,style
                 (progn (setf observed-branch :unquoted) '("unquoted"))
                 (progn (setf observed-branch :single) '("single"))
                  (progn (setf observed-branch :double) '("double")))))
     (is (eq ,branch observed-branch))))

(defmacro %assert-command-name-case (input style expected-command expected-error-count env)
  `(multiple-value-bind (command error)
       (nshell.domain.expansion:expand-command-name-by-quote-style
        ,input ,style ,env)
     (is (equal ,expected-command command))
     (if ,expected-error-count
         (is (string= (format nil "nshell: ~a: command name expansion produced ~d fields~%"
                              ,input ,expected-error-count)
                      error))
         (is (null error)))))

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

(test command-name-unquoted-fields-split-only-variable-originated-fields
  "Unquoted command names split only when raw text contains variable expansion."
  (let ((env (test-expansion-env)))
    (is (equal '("literal word")
               (nshell.domain.expansion::%command-name-unquoted-fields
                "literal word" env)))
    (is (equal '("echo" "bar")
               (nshell.domain.expansion::%command-name-unquoted-fields
                "echo $FOO" env)))))

(test command-name-field-splitting-required-p-documents-origin-rule
  "Command-position splitting is tied to raw variable-reference syntax."
  (is (null (nshell.domain.expansion::%command-name-field-splitting-required-p
             "literal word")))
  (is (nshell.domain.expansion::%command-name-field-splitting-required-p
       "echo $FOO")))

(test command-name-by-quote-style
  "Command-name expansion collapses to one field or returns the ambiguity error."
  (let ((env (test-expansion-env)))
    (setf env (nshell.domain.environment:env-set env "CMD" "echo" nil))
    (setf env (nshell.domain.environment:env-set env "EMPTY" "" nil))
    (%assert-command-name-case "$CMD" nil "echo" nil env)
    (%assert-command-name-case "$EMPTY" nil nil 0 env)
    (%assert-command-name-case "echo $FOO" nil nil 2 env)))

(test single-command-name-or-error-validates-non-empty-cardinality
  "Command-position resolution drops empty fields before validating cardinality."
  (multiple-value-bind (command error)
      (nshell.domain.expansion::%single-command-name-or-error "$EMPTY" '(""))
    (is (null command))
    (is (string= (format nil "nshell: $EMPTY: command name expansion produced 0 fields~%")
                 error)))
  (multiple-value-bind (command error)
      (nshell.domain.expansion::%single-command-name-or-error "$CMD" '("" "echo" ""))
    (is (string= "echo" command))
    (is (null error)))
  (multiple-value-bind (command error)
      (nshell.domain.expansion::%single-command-name-or-error "$CMD" '("echo" "printf"))
      (is (null command))
      (is (string= (format nil "nshell: $CMD: command name expansion produced 2 fields~%")
                   error))))

(test command-name-candidate-resolves-non-empty-cardinality
  "command-name-candidate owns empty-field removal before command resolution."
  (let ((candidate (nshell.domain.expansion::%make-command-name-candidate
                    "$CMD"
                    '("" "echo" ""))))
    (is (equal '("echo")
               (nshell.domain.expansion::command-name-candidate-non-empty-fields
                candidate)))
    (multiple-value-bind (command error)
        (nshell.domain.expansion::%resolve-command-name-candidate candidate)
      (is (string= "echo" command))
      (is (null error)))))

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
      (("alpha" "beta" "gamma") "$argv")
      (("pre-alpha.txt" "pre-beta.txt" "pre-gamma.txt") "pre-$argv.txt")
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
      ("alpha beta gamma" "$LIST")
      ("beta" "$LIST[2]")
      ("alpha beta" "$LIST[1..2]"))
    (%assert-expansion-cases-with-env (equal
                                       #'nshell.domain.expansion:expand-all
                                       env)
      (("alpha" "beta" "gamma") "$LIST")
      (("pre-alpha.txt" "pre-beta.txt" "pre-gamma.txt") "pre-$LIST.txt")
      (("pre-alpha.txt" "pre-beta.txt") "pre-$LIST[1..2].txt")
      (("alpha-beta" "alpha-gamma" "beta-beta" "beta-gamma" "gamma-beta" "gamma-gamma")
       "$LIST-$LIST[2..3]")
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
      (("pre-hello world.txt" "pre-tail.txt") "pre-$FILES.txt")
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


(defun arith-env ()
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "X" "10" nil))
    (setf env (nshell.domain.environment:env-set env "Y" "3" nil))
    env))


(test split-whitespace-fields-handles-edge-cases
  "whitespace splitting produces fields from space/tab/newline separators."
  (flet ((split (s) (nshell.domain.expansion::%split-whitespace-fields s)))
    (is (null (split "")))
    (is (null (split "   ")))
    (is (equal '("abc") (split "abc")))
    (is (equal '("a" "b" "c") (split "a b c")))
    (is (equal '("a" "b") (split "  a  b  ")))
    (is (equal '("a" "b") (split (format nil "a~%b"))))
    (is (equal '("a" "b") (split (format nil "a~Cb" #\Tab))))))

(test whitespace-field-scanner-accumulates-field-boundaries
  "Scanner state exposes field-boundary accumulation for whitespace splitting."
  (is (not (fboundp 'nshell.domain.expansion::make-whitespace-field-scanner)))
  (is (fboundp 'nshell.domain.expansion::%make-whitespace-field-scanner))
  (let* ((text (format nil " alpha~Cbeta~Cgamma " #\Tab #\Newline))
         (scanner (nshell.domain.expansion::%make-whitespace-field-scanner text)))
    (loop for index from 0 below (length text)
          do (nshell.domain.expansion::whitespace-field-scanner-accept
              scanner index (char text index)))
    (let ((boundaries
            (nshell.domain.expansion::whitespace-field-scanner-field-boundaries scanner)))
      (is (every #'nshell.domain.expansion::whitespace-field-boundary-p boundaries))
      (is (equal '((1 . 6) (7 . 11) (12 . 17))
                 (mapcar
                  (lambda (boundary)
                    (cons
                     (nshell.domain.expansion::whitespace-field-boundary-start boundary)
                     (nshell.domain.expansion::whitespace-field-boundary-end boundary)))
                  boundaries)))
      (is (equal '("alpha" "beta" "gamma")
                 (mapcar
                  (lambda (boundary)
                    (nshell.domain.expansion::whitespace-field-boundary-text boundary text))
                  boundaries)))
      (is (equal '("alpha" "beta" "gamma")
                 (nshell.domain.expansion::whitespace-field-scanner-result scanner))))))

(test expand-list-references-falls-through-scalar-path
  "When there is no list reference, result equals expand-variables output."
  (let ((env (test-expansion-env)))
    ;; No $-reference at all: literal pass-through.
    (is (equal '("plain") (nshell.domain.expansion::%expand-list-references "plain" env)))
    ;; Scalar $VAR: falls through to expand-variables, returns one element.
    (is (equal '("bar") (nshell.domain.expansion::%expand-list-references "$FOO" env)))))

(test expand-list-references-produces-multiple-fields
  "List variable references expand into multiple fields."
  (let* ((env (nshell.domain.environment:env-set-values
               (test-expansion-env) "WORDS" '("one" "two" "three") nil)))
    ;; Bare $VAR is a structured list in unquoted expansion.
    (is (equal '("one" "two" "three")
               (nshell.domain.expansion::%expand-list-references "$WORDS" env)))
    ;; Indexed reference $VAR[1..-1] produces separate fields.
    (is (equal '("one" "two" "three")
               (nshell.domain.expansion::%expand-list-references "$WORDS[1..-1]" env)))
    ;; Prefix literal + indexed reference produces cross-product.
    (is (equal '("pre-one" "pre-two" "pre-three")
               (nshell.domain.expansion::%expand-list-references "pre-$WORDS[1..-1]" env)))))

(test list-reference-fragment-at-projects-field-producing-fragments
  "list-reference-fragment-at projects field-producing references into fragments."
  (let ((env (nshell.domain.environment:env-set-values
              (test-expansion-env) "WORDS" '("one" "two" "three") nil)))
    (multiple-value-bind (fragment next)
        (nshell.domain.expansion::%list-reference-fragment-at
         "$WORDS[1..2]" 0 (length "$WORDS[1..2]") env)
      (is (nshell.domain.expansion::unquoted-field-fragment-p fragment))
      (is (eq :list-reference
              (nshell.domain.expansion::unquoted-field-fragment-kind fragment)))
      (is (equal '("one" "two")
                 (nshell.domain.expansion::unquoted-field-fragment-value fragment)))
      (is (= 12 next))
      (is (equal '("pre-one" "pre-two")
                 (nshell.domain.expansion::%apply-unquoted-field-fragment
                  '("pre-") fragment env))))
    (is (null (nshell.domain.expansion::%list-reference-fragment-at
               "literal" 0 (length "literal") env)))))

(test find-matching-brace-locates-balanced-closing-brace
  "find-matching-brace returns the index OF the closing }, not past it."
  (flet ((mbrace (s start) (nshell.domain.expansion::%find-matching-brace s start)))
    (is (= 1 (mbrace "{}" 0)))
    (is (= 4 (mbrace "{a,b}" 0)))
    (is (= 6 (mbrace "{a{b}c}" 0)))
    (is (null (mbrace "{unclosed" 0)))))

(test split-top-level-commas-respects-brace-nesting
  "split-top-level-commas splits on top-level commas only."
  (flet ((split (s) (nshell.domain.expansion::%split-top-level-commas s)))
    (is (equal '("a" "b" "c") (split "a,b,c")))
    (is (equal '("a{b,c}" "d") (split "a{b,c},d")))
    (is (equal '("a") (split "a")))
    (is (equal '("" "") (split ",")))))

(test brace-range-expansion-handles-numeric-and-alpha-ranges
  "brace-range-expansion returns an ascending or descending sequence for N..M and a..z."
  (flet ((range (s) (nshell.domain.expansion::%brace-range-expansion s)))
    (is (equal '("1" "2" "3") (range "1..3")))
    (is (equal '("3" "2" "1") (range "3..1")))
    (is (equal '("a" "b" "c") (range "a..c")))
    (is (equal '("c" "b" "a") (range "c..a")))
    (is (null (range "no-dots")))
    (is (null (range "ab..cd")))))

(test brace-expansion-options-classifies-one-brace-group
  "brace-expansion-options classifies a single brace group's range, comma group, or literal."
  (flet ((options (s) (nshell.domain.expansion::%brace-expansion-options s)))
    (is (equal '("1" "2" "3") (options "1..3")))
    (is (equal '("a" "b") (options "a,b")))
    (is (equal '("a{b,c}" "d") (options "a{b,c},d")))
    (is (null (options "literal")))))

(test glob-pattern-p-detects-wildcard-characters
  "glob-pattern-p returns true for patterns containing * ? or [."
  (flet ((pat (s) (nshell.domain.expansion::glob-pattern-p s)))
    (is (pat "*.txt"))
    (is (pat "file?.c"))
    (is (pat "[abc]"))
    (is (not (pat "plain")))
    (is (not (pat "a.b.c")))))
