(in-package #:nshell/test)


(in-suite expansion-tests)

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

(test arithmetic-substitution-spans-render-through-public-expander
  "$((expr)) detection is observable through complete arithmetic expansion."
  (let ((env (arith-env)))
    (is (string= "a11b6"
                 (nshell.domain.expansion:expand-arithmetic
                  "a$((X + 1))b$((Y * 2))" env)))
    (is (string= "$(echo hi)"
                 (nshell.domain.expansion:expand-arithmetic "$(echo hi)" env)))
    (is (string= "$((1 + 2)"
                 (nshell.domain.expansion:expand-arithmetic "$((1 + 2)" env)))))

(test arithmetic-division-by-zero-signals
  "Division by zero is an error rather than a crash-producing value."
  (signals error (nshell.domain.expansion:evaluate-arithmetic "1 / 0" (arith-env))))

(test arithmetic-lexer-branches-through-public-evaluator
  "Numbers, variables, operators, and whitespace are accepted through evaluate-arithmetic."
  (let ((env (arith-env)))
    (is (= 52 (nshell.domain.expansion:evaluate-arithmetic "X + 42" env)))
    (is (= 13 (nshell.domain.expansion:evaluate-arithmetic " X + Y " env)))
    (signals error (nshell.domain.expansion:evaluate-arithmetic "1 @ 2" env))))

(test arithmetic-evaluator-rejects-trailing-tokens
  "Arithmetic evaluation must consume the entire expression."
  (let ((env (arith-env)))
    (is (= 42 (nshell.domain.expansion:evaluate-arithmetic "42" env)))
    (signals error (nshell.domain.expansion:evaluate-arithmetic "1 + 2 3" env))))

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

(test brace-expansion-composes-prefix-options-and-suffix
  "Brace expansion composes the first group through the public expander."
  (is (equal '("preapost" "prebpost")
             (nshell.domain.expansion:expand-braces "pre{a,b}post")))
  (is (equal '("pre{x}post")
             (nshell.domain.expansion:expand-braces "pre{x}post"))))

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

(test expand-glob-uses-immediate-directory-scope
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
      (is (equal '("/tmp/one.txt")
                 (nshell.domain.expansion:expand-glob "/tmp/*.txt")))
      (is (equal '((:files "/tmp/")) (nreverse calls))))))

(test expand-glob-uses-recursive-directory-scope
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
      (is (equal '("/tmp/sub/one.txt")
                 (nshell.domain.expansion:expand-glob "/tmp/**/*.txt")))
      (is (equal '((:files "/tmp/")
                   (:subdirs "/tmp/")
                   (:files "/tmp/sub/")
                   (:subdirs "/tmp/sub/"))
                 (nreverse calls))))))

(test expand-glob-projects-relative-root-candidates
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
      (is (equal '("alpha.txt")
                 (nshell.domain.expansion:expand-glob "*.txt")))
      (is (equal '("./") (nreverse calls))))))

(test expand-all-reattaches-assignment-like-glob-prefixes
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
      (is (equal '("label=alpha.txt")
                 (nshell.domain.expansion:expand-all "label=*.txt" env)))
      (is (equal '("env:FOO=bar1.lisp")
                 (nshell.domain.expansion:expand-all "env:FOO=bar?.lisp" env)))
      (is (equal '("/tmp/a=b/alpha.txt")
                 (nshell.domain.expansion:expand-all "/tmp/a=b/*.txt" env))))))

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
  (is (nshell.domain.expansion:glob-match-p "file[0-2].lisp" "file1.lisp"))
  (is (not (nshell.domain.expansion:glob-match-p "file[0-2].lisp" "file9.lisp"))))

(test glob-bracket-negation-matches-outside-set
  "Bracket negation matches characters outside the declared set."
  (is (nshell.domain.expansion:glob-match-p "file[!0-2].lisp" "file9.lisp"))
  (is (not (nshell.domain.expansion:glob-match-p "file[!0-2].lisp" "file1.lisp")))
  (is (nshell.domain.expansion:glob-match-p "file[^ab].lisp" "filez.lisp"))
  (is (not (nshell.domain.expansion:glob-match-p "file[^ab].lisp" "filea.lisp"))))

(test glob-unclosed-bracket-matches-literal
  "An unclosed bracket is treated as a literal character."
  (is (nshell.domain.expansion:glob-match-p "file[1" "file[1"))
  (is (not (nshell.domain.expansion:glob-match-p "file[1" "file11"))))

(test pbt-glob-ranges-match-generated-members
  "Generated characters inside a bracket range always match that range."
  (check-property (:trials 50)
      ((start (gen-in-range 97 122) nil)
       (end (gen-in-range 97 122) nil))
    (let* ((lo (code-char (min start end)))
           (hi (code-char (max start end)))
           (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
      (nshell.domain.expansion:glob-match-p (format nil "[~c-~c]" lo hi)
                                            (string mid)))))

(test pbt-glob-negated-ranges-reject-generated-members
  "Generated characters inside a negated bracket range never match that range."
  (check-property (:trials 50)
      ((start (gen-in-range 97 122) nil)
       (end (gen-in-range 97 122) nil))
    (let* ((lo (code-char (min start end)))
           (hi (code-char (max start end)))
           (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
      (not (nshell.domain.expansion:glob-match-p (format nil "[!~c-~c]" lo hi)
                                                 (string mid))))))
