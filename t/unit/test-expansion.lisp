(in-package #:nshell/test)

(defun test-expansion-env ()
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "FOO" "bar" nil))
    (setf env (nshell.domain.environment:env-set env "HOME" "/tmp/nshell-home" nil))
    (setf env (nshell.domain.environment:env-set env "USER" "nshell-user" nil))
    env))

(defmacro %assert-expansion-cases ((predicate builder) &body cases)
  "Assert CASES against BUILDER using PREDICATE.

Each case is (EXPECTED INPUT &rest ARGS)."
  (let ((expander (gensym "EXPANDER-")))
    `(let ((,expander ,builder))
       ,@(mapcar (lambda (case)
                   (destructuring-bind (expected &rest args) case
                     `(expect (,predicate ',expected (funcall ,expander ,@args)) :to-be-truthy)))
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
                     `(expect (,predicate ',expected
                                      (multiple-value-list
                                       (funcall ,expander ,@args))) :to-be-truthy)))
                 cases))))

(defmacro %assert-quote-style-dispatch-case (style expected branch)
  `(let ((observed-branch nil))
     (expect ,expected :to-equal (nshell.domain.expansion:expand-by-quote-style
                  ,style
                 (progn (setf observed-branch :unquoted) '("unquoted"))
                 (progn (setf observed-branch :single) '("single"))
                  (progn (setf observed-branch :double) '("double"))))
     (expect ,branch :to-be observed-branch)))

(defmacro %assert-command-name-case (input style expected-command expected-error-count env)
  `(multiple-value-bind (command error)
       (nshell.domain.expansion:expand-command-name-by-quote-style
        ,input ,style ,env)
     (expect ,expected-command :to-equal command)
     (if ,expected-error-count
         (expect (format nil "nshell: ~a: command name expansion produced ~d fields~%"
                              ,input ,expected-error-count) :to-equal error)
         (expect error :to-be-null))))

(describe "expansion-tests"
  (it "dollar-var-expansion"
    "$VAR expands using the shell environment."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       (test-expansion-env))
      ("value=bar" "value=$FOO")))

  (it "braced-var-expansion"
    "${VAR} expands using the shell environment."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       (test-expansion-env))
      ("value=bar" "value=${FOO}")))

  (it "tilde-expansion"
    "A leading tilde expands to HOME."
    (expect "/tmp/nshell-home/src"
            :to-equal
            (nshell.domain.expansion:expand-tilde "~/src" (test-expansion-env))))
  (it "tilde-expands-current-user-from-environment"
    "A named tilde expands only for the current USER using HOME."
    (let ((env (test-expansion-env)))
      (expect "/tmp/nshell-home/src"
              :to-equal
              (nshell.domain.expansion:expand-tilde "~nshell-user/src" env))
      (expect "~other-user/src"
              :to-equal
              (nshell.domain.expansion:expand-tilde "~other-user/src" env))))

  (it "tilde-expansion-covers-home-and-user-boundaries"
    "Bare and named current-user tildes use HOME, with a literal fallback when HOME is absent."
    (let ((env (test-expansion-env))
          (empty-env (nshell.domain.environment:make-environment)))
      (expect "/tmp/nshell-home"
              :to-equal
              (nshell.domain.expansion:expand-tilde "~" env))
      (expect "/tmp/nshell-home"
              :to-equal
              (nshell.domain.expansion:expand-tilde "~nshell-user" env))
      (expect "~"
              :to-equal
              (nshell.domain.expansion:expand-tilde "~" empty-env))))

  (it "pathname-directory-string-handles-path-kinds"
    "Directory extraction preserves absolute, relative, and file-only paths."
    (expect "/tmp/"
            :to-equal
            (nshell.domain.expansion::pathname-directory-string "/tmp/a.txt"))
    (expect "tmp/"
            :to-equal
            (nshell.domain.expansion::pathname-directory-string "tmp/a.txt"))
    (expect ""
            :to-equal
            (nshell.domain.expansion::pathname-directory-string "a.txt"))
    (expect "/tmp/"
            :to-equal
            (nshell.domain.expansion::glob-root "/tmp/a.txt")))

  (it "double-quoted-expands-variables"
    "Double-quoted contents expand $VAR but stay a single field."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-double-quoted
                                       (test-expansion-env))
      ("value=bar" "value=$FOO")))

  (it "quote-style-dispatch-selects-forms"
    "Quote-style dispatch should evaluate exactly one branch."
    (dolist (case '((nil ("unquoted") :unquoted)
                    (:single ("single") :single)
                    (:double ("double") :double)))
      (destructuring-bind (style expected branch) case
        (%assert-quote-style-dispatch-case style expected branch))))

  (it "quote-style-dispatch-rejects-invalid-style"
    "Quote-style dispatch should reject invalid styles."
    (expect (lambda () (nshell.domain.expansion:expand-by-quote-style
       :bogus
       '("unquoted")
       '("single")
       '("double"))) :to-throw 'error))

  (it "command-name-fields-by-quote-style"
    "Command-name expansion stays a single field unless unquoted $-expansion needs splitting."
    (let ((env (test-expansion-env)))
      (%assert-expansion-cases (equal
                                (lambda (input quote-style)
                                  (nshell.domain.expansion:expand-command-name-fields-by-quote-style
                                   input quote-style env)))
        (("echo" "bar") "echo $FOO" nil)
        (("echo bar") "echo $FOO" :double)
        (("literal") "literal" nil))))

  (it "command-name-unquoted-fields-split-only-variable-originated-fields"
    "Unquoted command names split only when raw text contains variable expansion."
    (let ((env (test-expansion-env)))
      (expect '("literal word") :to-equal (nshell.domain.expansion::%command-name-unquoted-fields
                  "literal word" env nil))
      (expect '("echo" "bar") :to-equal (nshell.domain.expansion::%command-name-unquoted-fields
                  "echo $FOO" env nil))))

  (it "command-name-field-splitting-required-p-documents-origin-rule"
    "Command-position splitting is tied to raw variable-reference syntax."
    (expect (nshell.domain.expansion::%command-name-field-splitting-required-p
               "literal word") :to-be-null)
    (expect (nshell.domain.expansion::%command-name-field-splitting-required-p
         "echo $FOO") :to-be-truthy))

  (it "command-name-by-quote-style"
    "Command-name expansion collapses to one field or returns the ambiguity error."
    (let ((env (test-expansion-env)))
      (setf env (nshell.domain.environment:env-set env "CMD" "echo" nil))
      (setf env (nshell.domain.environment:env-set env "EMPTY" "" nil))
      (%assert-command-name-case "$CMD" nil "echo" nil env)
      (%assert-command-name-case "$EMPTY" nil nil 0 env)
      (%assert-command-name-case "echo $FOO" nil nil 2 env)))

  (it "single-command-name-or-error-validates-non-empty-cardinality"
    "Command-position resolution drops empty fields before validating cardinality."
    (multiple-value-bind (command error)
        (nshell.domain.expansion::%single-command-name-or-error "$EMPTY" '(""))
      (expect command :to-be-null)
      (expect (format nil "nshell: $EMPTY: command name expansion produced 0 fields~%") :to-equal error))
    (multiple-value-bind (command error)
        (nshell.domain.expansion::%single-command-name-or-error "$CMD" '("" "echo" ""))
      (expect "echo" :to-equal command)
      (expect error :to-be-null))
    (multiple-value-bind (command error)
        (nshell.domain.expansion::%single-command-name-or-error "$CMD" '("echo" "printf"))
        (expect command :to-be-null)
        (expect (format nil "nshell: $CMD: command name expansion produced 2 fields~%") :to-equal error)))

  (it "command-name-candidate-resolves-non-empty-cardinality"
    "command-name-candidate owns empty-field removal before command resolution."
    (let ((candidate (nshell.domain.expansion::%make-command-name-candidate
                      "$CMD"
                      '("" "echo" ""))))
      (expect '("echo") :to-equal (nshell.domain.expansion::command-name-candidate-non-empty-fields
                  candidate))
      (multiple-value-bind (command error)
          (nshell.domain.expansion::%resolve-command-name-candidate candidate)
        (expect "echo" :to-equal command)
        (expect error :to-be-null))))

  (it "argv-and-indexed-argv-expansion"
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

  (it "argv-list-compound-expansion"
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

  (it "variable-list-compound-expansion"
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

  (it "variable-list-expansion-preserves-spaces-inside-elements"
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

  (it "double-quoted-expands-arithmetic"
    "Arithmetic $((...)) is evaluated inside double quotes (POSIX)."
    (let ((env (test-expansion-env)))            ; FOO = bar
      (%assert-expansion-cases-with-env (string=
                                         #'nshell.domain.expansion:expand-double-quoted
                                         env)
        ("sum=7" "sum=$((3 + 4))")
        ("bar-3" "$FOO-$((1+2))"))))

  (it "double-quoted-suppresses-globbing"
    "Double-quoted contents must not be glob-expanded."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-double-quoted
                                       (test-expansion-env))
      ("*" "*")
      ("a*b?c" "a*b?c"))))


(defun arith-env ()
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "X" "10" nil))
    (setf env (nshell.domain.environment:env-set env "Y" "3" nil))
    env))


(describe "expansion-tests"
  (it "split-whitespace-fields-handles-edge-cases"
    "whitespace splitting produces fields from space/tab/newline separators."
    (flet ((split (s) (nshell.domain.expansion::%split-whitespace-fields s)))
      (expect (split "") :to-be-null)
      (expect (split "   ") :to-be-null)
      (expect '("abc") :to-equal (split "abc"))
      (expect '("a" "b" "c") :to-equal (split "a b c"))
      (expect '("a" "b") :to-equal (split "  a  b  "))
      (expect '("a" "b") :to-equal (split (format nil "a~%b")))
      (expect '("a" "b") :to-equal (split (format nil "a~Cb" #\Tab)))))

  (it "whitespace-field-scanner-accumulates-field-boundaries"
    "Scanner state exposes field-boundary accumulation for whitespace splitting."
    (expect (fboundp 'nshell.domain.expansion::make-whitespace-field-scanner) :to-be-falsy)
    (expect (fboundp 'nshell.domain.expansion::%make-whitespace-field-scanner) :to-be-truthy)
    (let* ((text (format nil " alpha~Cbeta~Cgamma " #\Tab #\Newline))
           (scanner (nshell.domain.expansion::%make-whitespace-field-scanner text)))
      (loop for index from 0 below (length text)
            do (setf scanner
                     (nshell.domain.expansion::whitespace-field-scanner-accept
                      scanner index (char text index))))
      (let ((boundaries
              (nshell.domain.expansion::whitespace-field-scanner-field-boundaries scanner)))
        (expect (every #'nshell.domain.expansion::whitespace-field-boundary-p boundaries) :to-be-truthy)
        (expect '((1 . 6) (7 . 11) (12 . 17)) :to-equal (mapcar
                    (lambda (boundary)
                      (cons
                       (nshell.domain.expansion::whitespace-field-boundary-start boundary)
                       (nshell.domain.expansion::whitespace-field-boundary-end boundary)))
                    boundaries))
        (expect '("alpha" "beta" "gamma") :to-equal (mapcar
                    (lambda (boundary)
                      (nshell.domain.expansion::whitespace-field-boundary-text boundary text))
                    boundaries))
        (expect '("alpha" "beta" "gamma") :to-equal (nshell.domain.expansion::whitespace-field-scanner-result scanner)))))

  (it "expand-list-references-falls-through-scalar-path"
    "When there is no list reference, result equals expand-variables output."
    (let ((env (test-expansion-env)))
      ;; No $-reference at all: literal pass-through.
      (expect '("plain") :to-equal (nshell.domain.expansion::%expand-list-references "plain" env))
      ;; Scalar $VAR: falls through to expand-variables, returns one element.
      (expect '("bar") :to-equal (nshell.domain.expansion::%expand-list-references "$FOO" env))))

  (it "expand-list-references-produces-multiple-fields"
    "List variable references expand into multiple fields."
    (let* ((env (nshell.domain.environment:env-set-values
                 (test-expansion-env) "WORDS" '("one" "two" "three") nil)))
      ;; Bare $VAR is a structured list in unquoted expansion.
      (expect '("one" "two" "three") :to-equal (nshell.domain.expansion::%expand-list-references "$WORDS" env))
      ;; Indexed reference $VAR[1..-1] produces separate fields.
      (expect '("one" "two" "three") :to-equal (nshell.domain.expansion::%expand-list-references "$WORDS[1..-1]" env))
      ;; Prefix literal + indexed reference produces cross-product.
      (expect '("pre-one" "pre-two" "pre-three") :to-equal (nshell.domain.expansion::%expand-list-references "pre-$WORDS[1..-1]" env))))

  (it "list-reference-fragment-at-projects-field-producing-fragments"
    "list-reference-fragment-at projects field-producing references into fragments."
    (let ((env (nshell.domain.environment:env-set-values
                (test-expansion-env) "WORDS" '("one" "two" "three") nil)))
      (multiple-value-bind (fragment next)
          (nshell.domain.expansion::%list-reference-fragment-at
           "$WORDS[1..2]" 0 (length "$WORDS[1..2]") env)
        (expect (nshell.domain.expansion::unquoted-field-fragment-p fragment) :to-be-truthy)
        (expect :list-reference :to-be (nshell.domain.expansion::unquoted-field-fragment-kind fragment))
        (expect '("one" "two") :to-equal (nshell.domain.expansion::unquoted-field-fragment-value fragment))
        (expect 12 :to-equal next)
        (expect '("pre-one" "pre-two") :to-equal (nshell.domain.expansion::%apply-unquoted-field-fragment
                    '("pre-") fragment env)))
      (expect (nshell.domain.expansion::%list-reference-fragment-at
                 "literal" 0 (length "literal") env) :to-be-null)))

  (it "find-matching-brace-locates-balanced-closing-brace"
    "find-matching-brace returns the index OF the closing }, not past it."
    (flet ((mbrace (s start) (nshell.domain.expansion::%find-matching-brace s start)))
      (expect 1 :to-equal (mbrace "{}" 0))
      (expect 4 :to-equal (mbrace "{a,b}" 0))
      (expect 6 :to-equal (mbrace "{a{b}c}" 0))
      (expect (mbrace "{unclosed" 0) :to-be-null)))

  (it "split-top-level-commas-respects-brace-nesting"
    "split-top-level-commas splits on top-level commas only."
    (flet ((split (s) (nshell.domain.expansion::%split-top-level-commas s)))
      (expect '("a" "b" "c") :to-equal (split "a,b,c"))
      (expect '("a{b,c}" "d") :to-equal (split "a{b,c},d"))
      (expect '("a") :to-equal (split "a"))
      (expect '("" "") :to-equal (split ","))))

  (it "brace-range-expansion-handles-numeric-and-alpha-ranges"
    "brace-range-expansion returns an ascending or descending sequence for N..M and a..z."
    (flet ((range (s) (nshell.domain.expansion::%brace-range-expansion s)))
      (expect '("1" "2" "3") :to-equal (range "1..3"))
      (expect '("3" "2" "1") :to-equal (range "3..1"))
      (expect '("a" "b" "c") :to-equal (range "a..c"))
      (expect '("c" "b" "a") :to-equal (range "c..a"))
      (expect (range "no-dots") :to-be-null)
      (expect (range "ab..cd") :to-be-null)))

  (it "brace-expansion-options-classifies-one-brace-group"
    "brace-expansion-options classifies a single brace group's range, comma group, or literal."
    (flet ((options (s) (nshell.domain.expansion::%brace-expansion-options s)))
      (expect '("1" "2" "3") :to-equal (options "1..3"))
      (expect '("a" "b") :to-equal (options "a,b"))
      (expect '("a{b,c}" "d") :to-equal (options "a{b,c},d"))
      (expect (options "literal") :to-be-null)))

  (it "glob-pattern-p-detects-wildcard-characters"
    "glob-pattern-p returns true for patterns containing * ? or [."
    (flet ((pat (s) (nshell.domain.expansion::glob-pattern-p s)))
      (expect (pat "*.txt") :to-be-truthy)
      (expect (pat "file?.c") :to-be-truthy)
      (expect (pat "[abc]") :to-be-truthy)
      (expect (pat "plain") :to-be-falsy)
      (expect (pat "a.b.c") :to-be-falsy)))

  (it "glob-match-subject-normalizes-files-outside-root"
    "A candidate outside the computed root remains usable for matching."
    (let* ((subject (nshell.domain.expansion::%glob-file-match-subject
                     "*.txt" "/tmp/" #p"other.txt"))
           (candidate (nshell.domain.expansion::%glob-match-subject-candidate
                       subject)))
      (expect "/tmp/other.txt" :to-equal candidate))))
