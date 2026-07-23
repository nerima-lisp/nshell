(in-package #:nshell/test)

(describe "expansion-tests"
  (it "arithmetic-basic-operators"
    "Integer + - * / % with precedence and parentheses."
    (let ((env (arith-env)))
      (expect 7 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 + 2 * 3" env))
      (expect 9 :to-equal (nshell.domain.expansion:evaluate-arithmetic "(1 + 2) * 3" env))
      (expect 1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "10 % 3" env))
      (expect 3 :to-equal (nshell.domain.expansion:evaluate-arithmetic "10 / 3" env))
      (expect -5 :to-equal (nshell.domain.expansion:evaluate-arithmetic "-2 - 3" env))))

  (it "arithmetic-uses-variables"
    "Bare names resolve from the environment; unset names are 0."
    (let ((env (arith-env)))
      (expect 13 :to-equal (nshell.domain.expansion:evaluate-arithmetic "X + Y" env))
      (expect 30 :to-equal (nshell.domain.expansion:evaluate-arithmetic "X * Y" env))
      (expect 0 :to-equal (nshell.domain.expansion:evaluate-arithmetic "UNSET" env))))

  (it "arithmetic-comparisons-and-logic"
    "Comparison and logical operators yield 1/0."
    (let ((env (arith-env)))
      (expect 1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "X > Y" env))
      (expect 0 :to-equal (nshell.domain.expansion:evaluate-arithmetic "X < Y" env))
      (expect 1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "X == 10" env))
      (expect 1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "X > 0 && Y > 0" env))
      (expect 0 :to-equal (nshell.domain.expansion:evaluate-arithmetic "!1" env))))

  (it "arithmetic-exponentiation-is-right-associative"
    "** binds tighter than unary minus and associates to the right (bash parity)."
    (let ((env (arith-env)))
      (expect 512 :to-equal (nshell.domain.expansion:evaluate-arithmetic "2 ** 3 ** 2" env))
      (expect -4 :to-equal (nshell.domain.expansion:evaluate-arithmetic "-2 ** 2" env))
      (expect 8 :to-equal (nshell.domain.expansion:evaluate-arithmetic "2 ** 3" env))
      (expect (lambda () (nshell.domain.expansion:evaluate-arithmetic "2 ** -1" env))
              :to-throw 'error)))

  (it "arithmetic-bitwise-and-shift-operators"
    "Bitwise &, |, ^, ~ and the << >> shifts evaluate over integers."
    (let ((env (arith-env)))
      (expect 16 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 << 4" env))
      (expect 64 :to-equal (nshell.domain.expansion:evaluate-arithmetic "256 >> 2" env))
      (expect 2 :to-equal (nshell.domain.expansion:evaluate-arithmetic "6 & 3" env))
      (expect 7 :to-equal (nshell.domain.expansion:evaluate-arithmetic "6 | 1" env))
      (expect 4 :to-equal (nshell.domain.expansion:evaluate-arithmetic "5 ^ 1" env))
      (expect -1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "~0" env))
      ;; Bitwise precedence: & binds tighter than ^ binds tighter than |.
      (expect 7 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 | 2 & 3 ^ 4" env))))

  (it "arithmetic-ternary-conditional"
    "?: selects a branch, associates right, and sits below the other operators."
    (let ((env (arith-env)))
      (expect 2 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 ? 2 : 3" env))
      (expect 3 :to-equal (nshell.domain.expansion:evaluate-arithmetic "0 ? 2 : 3" env))
      ;; Right associative: 1 ? 2 : (3 ? 4 : 5) -> condition true -> then branch 2.
      (expect 2 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 ? 2 : 3 ? 4 : 5" env))
      ;; 0 ? 2 : (3 ? 4 : 5) -> condition false -> else branch (3 ? 4 : 5) -> 4.
      (expect 4 :to-equal (nshell.domain.expansion:evaluate-arithmetic "0 ? 2 : 3 ? 4 : 5" env))
      ;; The condition is a full expression to the left of `?`.
      (expect 10 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 + 2 ? 10 : 20" env))
      (expect (lambda () (nshell.domain.expansion:evaluate-arithmetic "1 ? 2" env))
              :to-throw 'error)))

  (it "arithmetic-logical-operators-short-circuit-without-trailing-error"
    "&& and || evaluate to 1/0 for every operand combination (no leftover-token error)."
    (let ((env (arith-env)))
      (expect 1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 || 5" env))
      (expect 1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "0 || 5" env))
      (expect 0 :to-equal (nshell.domain.expansion:evaluate-arithmetic "0 && 5" env))
      (expect 1 :to-equal (nshell.domain.expansion:evaluate-arithmetic "1 && 5" env))))

  (it "arithmetic-substitution-in-text"
    "$((expr)) is substituted within surrounding text, with variable expansion."
    (let ((env (arith-env)))
      (expect "result=13" :to-equal (nshell.domain.expansion:expand-arithmetic "result=$((X + Y))" env))
      (expect "a4b" :to-equal (nshell.domain.expansion:expand-arithmetic "a$(( (1+1) * 2 ))b" env))
      ;; Non-arithmetic dollar-parens are left untouched.
      (expect "$(echo hi)" :to-equal (nshell.domain.expansion:expand-arithmetic "$(echo hi)" env))))

  (it "arithmetic-substitution-spans-render-through-public-expander"
    "$((expr)) detection is observable through complete arithmetic expansion."
    (let ((env (arith-env)))
      (expect "a11b6" :to-equal (nshell.domain.expansion:expand-arithmetic
                    "a$((X + 1))b$((Y * 2))" env))
      (expect "$(echo hi)" :to-equal (nshell.domain.expansion:expand-arithmetic "$(echo hi)" env))
      (expect "$((1 + 2)" :to-equal (nshell.domain.expansion:expand-arithmetic "$((1 + 2)" env))))

  (it "arithmetic-division-by-zero-signals"
    "Division by zero is an error rather than a crash-producing value."
    (expect (lambda () (nshell.domain.expansion:evaluate-arithmetic "1 / 0" (arith-env))) :to-throw 'error))

  (it "arithmetic-lexer-branches-through-public-evaluator"
    "Numbers, variables, operators, and whitespace are accepted through evaluate-arithmetic."
    (let ((env (arith-env)))
      (expect 52 :to-equal (nshell.domain.expansion:evaluate-arithmetic "X + 42" env))
      (expect 13 :to-equal (nshell.domain.expansion:evaluate-arithmetic " X + Y " env))
      (expect (lambda () (nshell.domain.expansion:evaluate-arithmetic "1 @ 2" env)) :to-throw 'error)))

  (it "arithmetic-evaluator-rejects-trailing-tokens"
    "Arithmetic evaluation must consume the entire expression."
    (let ((env (arith-env)))
      (expect 42 :to-equal (nshell.domain.expansion:evaluate-arithmetic "42" env))
      (expect (lambda () (nshell.domain.expansion:evaluate-arithmetic "1 + 2 3" env)) :to-throw 'error)))

  (it "brace-comma-expansion"
    "{a,b,c} expands to each option with surrounding prefix/suffix."
    (expect '("abd" "acd") :to-equal (nshell.domain.expansion:expand-braces "a{b,c}d"))
    (expect '("pre1.txt" "pre2.txt" "pre3.txt") :to-equal (nshell.domain.expansion:expand-braces "pre{1,2,3}.txt")))

  (it "brace-numeric-range"
    "{1..4} expands to an ascending integer sequence (and {3..1} descends)."
    (expect '("1" "2" "3" "4") :to-equal (nshell.domain.expansion:expand-braces "{1..4}"))
    (expect '("3" "2" "1") :to-equal (nshell.domain.expansion:expand-braces "{3..1}")))

  (it "brace-char-range"
    "{a..c} expands over characters."
    (expect '("a" "b" "c") :to-equal (nshell.domain.expansion:expand-braces "{a..c}")))

  (it "brace-nested-and-cartesian"
    "Nested and adjacent groups expand as a cartesian product."
    (expect '("ax" "ay" "bx" "by") :to-equal (nshell.domain.expansion:expand-braces "{a,b}{x,y}")))

  (it "brace-literal-when-no-comma-or-range"
    "A single-element group is left literal, matching shell behavior."
    (expect '("{a}") :to-equal (nshell.domain.expansion:expand-braces "{a}"))
    (expect '("nobrace") :to-equal (nshell.domain.expansion:expand-braces "nobrace")))

  (it "brace-expansion-composes-prefix-options-and-suffix"
    "Brace expansion composes the first group through the public expander."
    (expect '("preapost" "prebpost") :to-equal (nshell.domain.expansion:expand-braces "pre{a,b}post"))
    (expect '("pre{x}post") :to-equal (nshell.domain.expansion:expand-braces "pre{x}post")))

  (it "glob-expansion-finds-files"
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
           (expect (member expected (nshell.domain.expansion:expand-glob pattern) :test #'string=) :to-be-truthy))
      ;; Cleanup: restore dynamic variables and delete temp dir
      (setf nshell.domain.expansion:*glob-directory-files-fn* nil)
      (setf nshell.domain.expansion:*glob-subdirectories-fn* nil)
      (handler-case
          (let ((root (probe-file (merge-pathnames "nshell-glob-*/" (uiop:temporary-directory)))))
            (when root (uiop:delete-directory-tree root :validate t)))
        (error ()))))

  (it "expand-glob-uses-immediate-directory-scope"
    "A non-recursive glob uses immediate directory candidates through expand-glob."
    (let ((calls nil))
      (let ((nshell.domain.expansion:*glob-directory-files-fn*
              (lambda (dir)
                (push (list :files (namestring dir)) calls)
                (list (merge-pathnames "one.txt" dir)
                      (merge-pathnames "two.log" dir))))
            (nshell.domain.expansion:*glob-subdirectories-fn*
              (lambda (dir)
                (push (list :subdirs (namestring dir)) calls)
                nil)))
        (expect '("/tmp/one.txt") :to-equal (nshell.domain.expansion:expand-glob "/tmp/*.txt"))
        (expect '((:files "/tmp/")) :to-equal (nreverse calls)))))

  (it "expand-glob-uses-recursive-directory-scope"
    "A ** pattern recursively enumerates candidates through expand-glob."
    (let ((calls nil))
      (let ((nshell.domain.expansion:*glob-directory-files-fn*
              (lambda (dir)
                (push (list :files (namestring dir)) calls)
                (if (string= "/tmp/sub/" (namestring dir))
                    (list (merge-pathnames "one.txt" dir))
                    nil)))
            (nshell.domain.expansion:*glob-subdirectories-fn*
              (lambda (dir)
                (push (list :subdirs (namestring dir)) calls)
                (if (string= "/tmp/" (namestring dir))
                    (list #p"/tmp/sub/")
                    nil))))
        (expect '("/tmp/sub/one.txt") :to-equal (nshell.domain.expansion:expand-glob "/tmp/**/*.txt"))
        (expect '((:files "/tmp/")
                     (:subdirs "/tmp/")
                     (:files "/tmp/sub/")
                     (:subdirs "/tmp/sub/")) :to-equal (nreverse calls)))))

  (it "expand-glob-projects-relative-root-candidates"
    "A ./ glob root projects candidates without leaking the implicit directory prefix."
    (let ((calls nil))
      (let ((nshell.domain.expansion:*glob-directory-files-fn*
              (lambda (dir)
                (push (namestring dir) calls)
                (list #p"alpha.txt" #p"beta.log")))
            (nshell.domain.expansion:*glob-subdirectories-fn*
              (lambda (dir)
                (declare (ignore dir))
                nil)))
        (expect '("alpha.txt") :to-equal (nshell.domain.expansion:expand-glob "*.txt"))
        (expect '("./") :to-equal (nreverse calls)))))

  (it "expand-all-reattaches-assignment-like-glob-prefixes"
    "expand-all separates label-like prefixes from glob suffixes without treating paths as labels."
    (let ((env (test-expansion-env)))
      (let ((nshell.domain.expansion:*glob-directory-files-fn*
              (lambda (dir)
                (if (string= "./" (namestring dir))
                    (list #p"alpha.txt" #p"beta.log" #p"bar1.lisp")
                    (list (merge-pathnames "alpha.txt" dir)
                          (merge-pathnames "beta.log" dir)
                          (merge-pathnames "bar1.lisp" dir)))))
            (nshell.domain.expansion:*glob-subdirectories-fn*
              (lambda (dir)
                (declare (ignore dir))
                nil)))
        (expect '("label=alpha.txt") :to-equal (nshell.domain.expansion:expand-all "label=*.txt" env))
        (expect '("env:FOO=bar1.lisp") :to-equal (nshell.domain.expansion:expand-all "env:FOO=bar?.lisp" env))
        (expect '("/tmp/a=b/alpha.txt") :to-equal (nshell.domain.expansion:expand-all "/tmp/a=b/*.txt" env)))))

  (it "nonexistent-var-expands-empty"
    "Undefined variables expand to the empty string."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       (test-expansion-env))
      ("prefix--suffix" "prefix-$NONEXISTENT-suffix")))

  (it "numeric-var-reference-stays-literal"
    "$1 is not treated as a named variable."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       (test-expansion-env))
      ("value=$1" "value=$1")))

  (it "numeric-var-reference-with-suffix-stays-literal"
    "$1foo is kept literal instead of being split into a variable reference."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       (test-expansion-env))
      ("value=$1foo" "value=$1foo")))

  (it "pbt-valid-variable-names-expand"
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

  (it "glob-bracket-range-matches-characters"
    "Bracket ranges match characters inside the declared span."
    (expect (nshell.domain.expansion:glob-match-p "file[0-2].lisp" "file1.lisp") :to-be-truthy)
    (expect (nshell.domain.expansion:glob-match-p "file[0-2].lisp" "file9.lisp") :to-be-falsy))

  (it "glob-bracket-negation-matches-outside-set"
    "Bracket negation matches characters outside the declared set."
    (expect (nshell.domain.expansion:glob-match-p "file[!0-2].lisp" "file9.lisp") :to-be-truthy)
    (expect (nshell.domain.expansion:glob-match-p "file[!0-2].lisp" "file1.lisp") :to-be-falsy)
    (expect (nshell.domain.expansion:glob-match-p "file[^ab].lisp" "filez.lisp") :to-be-truthy)
    (expect (nshell.domain.expansion:glob-match-p "file[^ab].lisp" "filea.lisp") :to-be-falsy))

  (it "glob-unclosed-bracket-matches-literal"
    "An unclosed bracket is treated as a literal character."
    (expect (nshell.domain.expansion:glob-match-p "file[1" "file[1") :to-be-truthy)
    (expect (nshell.domain.expansion:glob-match-p "file[1" "file11") :to-be-falsy))

  (it "pbt-glob-ranges-match-generated-members"
    "Generated characters inside a bracket range always match that range."
    (check-property (:trials 50)
        ((start (gen-in-range 97 122) nil)
         (end (gen-in-range 97 122) nil))
      (let* ((lo (code-char (min start end)))
             (hi (code-char (max start end)))
             (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
        (nshell.domain.expansion:glob-match-p (format nil "[~c-~c]" lo hi)
                                              (string mid)))))

  (it "pbt-glob-negated-ranges-reject-generated-members"
    "Generated characters inside a negated bracket range never match that range."
    (check-property (:trials 50)
        ((start (gen-in-range 97 122) nil)
         (end (gen-in-range 97 122) nil))
      (let* ((lo (code-char (min start end)))
             (hi (code-char (max start end)))
             (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
        (not (nshell.domain.expansion:glob-match-p (format nil "[!~c-~c]" lo hi)
                                                   (string mid)))))))
