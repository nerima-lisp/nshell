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

(test arithmetic-basic-operators
  "Integer + - * / % with precedence and parentheses."
  (let ((env (arith-env)))
    (is (= 7 (nshell.domain.expansion:evaluate-arithmetic "1 + 2 * 3" env)))
    (is (= 9 (nshell.domain.expansion:evaluate-arithmetic "(1 + 2) * 3" env)))
    (is (= 1 (nshell.domain.expansion:evaluate-arithmetic "10 % 3" env)))
    (is (= 3 (nshell.domain.expansion:evaluate-arithmetic "10 / 3" env)))
    (is (= -5 (nshell.domain.expansion:evaluate-arithmetic "-2 - 3" env)))))

(test arithmetic-uses-variables
  "Bare names resolve from the environment; unset names are 0."
  (let ((env (arith-env)))
    (is (= 13 (nshell.domain.expansion:evaluate-arithmetic "X + Y" env)))
    (is (= 30 (nshell.domain.expansion:evaluate-arithmetic "X * Y" env)))
    (is (= 0 (nshell.domain.expansion:evaluate-arithmetic "UNSET" env)))))

(test arithmetic-comparisons-and-logic
  "Comparison and logical operators yield 1/0."
  (let ((env (arith-env)))
    (is (= 1 (nshell.domain.expansion:evaluate-arithmetic "X > Y" env)))
    (is (= 0 (nshell.domain.expansion:evaluate-arithmetic "X < Y" env)))
    (is (= 1 (nshell.domain.expansion:evaluate-arithmetic "X == 10" env)))
    (is (= 1 (nshell.domain.expansion:evaluate-arithmetic "X > 0 && Y > 0" env)))
    (is (= 0 (nshell.domain.expansion:evaluate-arithmetic "!1" env)))))

(test arithmetic-substitution-in-text
  "$((expr)) is substituted within surrounding text, with variable expansion."
  (let ((env (arith-env)))
    (is (string= "result=13"
                 (nshell.domain.expansion:expand-arithmetic "result=$((X + Y))" env)))
    (is (string= "a4b"
                 (nshell.domain.expansion:expand-arithmetic "a$(( (1+1) * 2 ))b" env)))
    ;; Non-arithmetic dollar-parens are left untouched.
    (is (string= "$(echo hi)"
                 (nshell.domain.expansion:expand-arithmetic "$(echo hi)" env)))))

(test arithmetic-division-by-zero-signals
  "Division by zero is an error rather than a crash-producing value."
  (signals error (nshell.domain.expansion:evaluate-arithmetic "1 / 0" (arith-env))))

(test brace-comma-expansion
  "{a,b,c} expands to each option with surrounding prefix/suffix."
  (is (equal '("abd" "acd")
             (nshell.domain.expansion:expand-braces "a{b,c}d")))
  (is (equal '("pre1.txt" "pre2.txt" "pre3.txt")
             (nshell.domain.expansion:expand-braces "pre{1,2,3}.txt"))))

(test brace-numeric-range
  "{1..4} expands to an ascending integer sequence (and {3..1} descends)."
  (is (equal '("1" "2" "3" "4") (nshell.domain.expansion:expand-braces "{1..4}")))
  (is (equal '("3" "2" "1") (nshell.domain.expansion:expand-braces "{3..1}"))))

(test brace-char-range
  "{a..c} expands over characters."
  (is (equal '("a" "b" "c") (nshell.domain.expansion:expand-braces "{a..c}"))))

(test brace-nested-and-cartesian
  "Nested and adjacent groups expand as a cartesian product."
  (is (equal '("ax" "ay" "bx" "by")
             (nshell.domain.expansion:expand-braces "{a,b}{x,y}"))))

(test brace-literal-when-no-comma-or-range
  "A single-element group is left literal, matching shell behavior."
  (is (equal '("{a}") (nshell.domain.expansion:expand-braces "{a}")))
  (is (equal '("nobrace") (nshell.domain.expansion:expand-braces "nobrace"))))

(test glob-expansion-finds-files
  "A star glob expands to matching files."
  ;; Inject filesystem adapters for DDD purity
  (setf nshell.domain.expansion:*glob-directory-files-fn*
        (lambda (dir) (uiop:directory-files dir)))
  (setf nshell.domain.expansion:*glob-subdirectories-fn*
        (lambda (dir) (uiop:subdirectories dir)))
  (unwind-protect
       (let* ((root (merge-pathnames (format nil "nshell-glob-~a/" (gensym))
                                     (uiop:temporary-directory)))
              (pattern (namestring (merge-pathnames "*.txt" root)))
              (expected (namestring (merge-pathnames "alpha.txt" root))))
         (ensure-directories-exist root)
         (with-open-file (stream expected :direction :output :if-exists :supersede)
           (write-line "alpha" stream))
         (with-open-file (stream (merge-pathnames "beta.log" root)
                                        :direction :output :if-exists :supersede)
           (write-line "beta" stream))
         (is (member expected (nshell.domain.expansion:expand-glob pattern) :test #'string=)))
    ;; Cleanup: restore dynamic variables and delete temp dir
    (setf nshell.domain.expansion:*glob-directory-files-fn* nil)
    (setf nshell.domain.expansion:*glob-subdirectories-fn* nil)
    (handler-case
        (let ((root (probe-file (merge-pathnames "nshell-glob-*/" (uiop:temporary-directory)))))
          (when root (uiop:delete-directory-tree root :validate t)))
      (error ()))))

(test nonexistent-var-expands-empty
  "Undefined variables expand to the empty string."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-variables
                                     (test-expansion-env))
    ("prefix--suffix" "prefix-$NONEXISTENT-suffix")))

(test numeric-var-reference-stays-literal
  "$1 is not treated as a named variable."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-variables
                                     (test-expansion-env))
    ("value=$1" "value=$1")))

(test numeric-var-reference-with-suffix-stays-literal
  "$1foo is kept literal instead of being split into a variable reference."
  (%assert-expansion-cases-with-env (string=
                                     #'nshell.domain.expansion:expand-variables
                                     (test-expansion-env))
    ("value=$1foo" "value=$1foo")))

(test pbt-valid-variable-names-expand
  "Generated shell variable names expand consistently in both $NAME and ${NAME} forms."
  (check-property (:trials 50)
      ((name (gen-shell-variable-name :min-length 1 :max-length 10)
             #'shrink-prompt-text))
    (let* ((value (concatenate 'string "value-" name))
           (env (nshell.domain.environment:env-set
                 (test-expansion-env) name value nil)))
      (and (string= (nshell.domain.expansion:expand-variables
                     (concatenate 'string "$" name)
                     env)
                    value)
           (string= (nshell.domain.expansion:expand-variables
                     (concatenate 'string "${" name "}")
                     env)
                    value)))))

(test glob-bracket-range-matches-characters
  "Bracket ranges match characters inside the declared span."
  (is (nshell.domain.expansion::glob-match-p "file[0-2].lisp" "file1.lisp"))
  (is (not (nshell.domain.expansion::glob-match-p "file[0-2].lisp" "file9.lisp"))))

(test glob-bracket-negation-matches-outside-set
  "Bracket negation matches characters outside the declared set."
  (is (nshell.domain.expansion::glob-match-p "file[!0-2].lisp" "file9.lisp"))
  (is (not (nshell.domain.expansion::glob-match-p "file[!0-2].lisp" "file1.lisp")))
  (is (nshell.domain.expansion::glob-match-p "file[^ab].lisp" "filez.lisp"))
  (is (not (nshell.domain.expansion::glob-match-p "file[^ab].lisp" "filea.lisp"))))

(test glob-unclosed-bracket-matches-literal
  "An unclosed bracket is treated as a literal character."
  (is (nshell.domain.expansion::glob-match-p "file[1" "file[1"))
  (is (not (nshell.domain.expansion::glob-match-p "file[1" "file11"))))

(test pbt-glob-ranges-match-generated-members
  "Generated characters inside a bracket range always match that range."
  (check-property (:trials 50)
      ((start (gen-in-range 97 122) nil)
       (end (gen-in-range 97 122) nil))
    (let* ((lo (code-char (min start end)))
           (hi (code-char (max start end)))
           (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
      (nshell.domain.expansion::glob-match-p (format nil "[~c-~c]" lo hi)
                                             (string mid)))))

(test pbt-glob-negated-ranges-reject-generated-members
  "Generated characters inside a negated bracket range never match that range."
  (check-property (:trials 50)
      ((start (gen-in-range 97 122) nil)
       (end (gen-in-range 97 122) nil))
    (let* ((lo (code-char (min start end)))
           (hi (code-char (max start end)))
           (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
      (not (nshell.domain.expansion::glob-match-p (format nil "[!~c-~c]" lo hi)
                                                  (string mid))))))

(test abbreviation-domain-finds-token-before-cursor
  (multiple-value-bind (token start end found-p)
      (nshell.domain.abbreviation:abbreviation-target-before-cursor
       "echo|gco" 8)
    (is (not (null found-p)))
    (is (string= "gco" token))
    (is (= 5 start))
    (is (= 8 end))))

(test abbreviation-domain-expands-token-before-cursor
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "echo gco tail"
       8
       (lambda (token)
         (when (string= token "gco")
           "git checkout")))
    (is (not (null expanded-p)))
    (is (string= "echo git checkout tail" buffer))
    (is (= 17 cursor))))

(test abbreviation-domain-command-position-detects-command-starts
  (is (nshell.domain.abbreviation:abbreviation-command-position-p "gco" 0))
  (is (nshell.domain.abbreviation:abbreviation-command-position-p "echo hi; gco" 9))
  (is (nshell.domain.abbreviation:abbreviation-command-position-p "echo hi | gco" 10))
  (is (not (nshell.domain.abbreviation:abbreviation-command-position-p
            "echo gco" 5)))
  (is (not (nshell.domain.abbreviation:abbreviation-command-position-p
            "cat < gco" 6))))

(test abbreviation-domain-respects-command-position-expansions
  (let ((abbr (nshell.domain.abbreviation:make-abbreviation
               :expansion "git checkout"
               :position :command)))
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "gco"
         3
         (lambda (token)
           (when (string= token "gco")
             abbr)))
      (is (not (null expanded-p)))
      (is (string= "git checkout" buffer))
      (is (= 12 cursor)))
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "echo gco"
         8
         (lambda (token)
           (when (string= token "gco")
             abbr)))
      (is (not expanded-p))
      (is (string= "echo gco" buffer))
      (is (= 8 cursor)))))

(test abbreviation-domain-expands-after-leading-space-command-position
  (let ((abbr (nshell.domain.abbreviation:make-abbreviation
               :expansion "git checkout"
               :position :command)))
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "  gco"
         5
         (lambda (token)
           (when (string= token "gco")
             abbr)))
      (is (not (null expanded-p)))
      (is (string= "  git checkout" buffer))
      (is (= 14 cursor)))))

(test abbreviation-domain-respects-escaped-space
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "echo foo\\ gco"
       13
       (lambda (token)
         (when (string= token "gco")
           "git checkout")))
    (is (not expanded-p))
    (is (string= "echo foo\\ gco" buffer))
    (is (= 13 cursor))))

(test abbreviation-domain-does-not-expand-quoted-token
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "echo \"gco\""
       10
       (lambda (token)
         (when (string= token "\"gco\"")
           "git checkout")))
    (is (not expanded-p))
    (is (string= "echo \"gco\"" buffer))
    (is (= 10 cursor))))

(test abbreviation-domain-allows-escaped-quote-content
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "foo\\\"bar"
       8
       (lambda (token)
         (when (string= token "foo\\\"bar")
           "git checkout")))
      (is (not (null expanded-p)))
    (is (string= "git checkout" buffer))
    (is (= 12 cursor))))

(test pbt-abbreviation-domain-expands-token-exactly-at-cursor
  (check-property (:trials 50)
      ((prefix (gen-shell-command :min-words 1 :max-words 3 :max-word-length 6)
               #'shrink-prompt-text)
       (token (gen-shell-word :min-length 1 :max-length 8)
              #'shrink-prompt-text)
       (suffix (gen-shell-command :min-words 1 :max-words 3 :max-word-length 6)
               #'shrink-prompt-text))
    (let* ((expansion (concatenate 'string "expanded-" token))
           (buffer (concatenate 'string prefix " " token " " suffix))
           (cursor (+ (length prefix) 1 (length token))))
      (multiple-value-bind (new-buffer new-cursor expanded-p)
          (nshell.domain.abbreviation:expand-abbreviation
           buffer cursor
           (lambda (candidate)
             (when (string= candidate token)
               expansion)))
        (and expanded-p
             (string= (concatenate 'string prefix " " expansion " " suffix)
                      new-buffer)
             (= (+ (length prefix) 1 (length expansion))
                new-cursor))))))
