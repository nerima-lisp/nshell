(in-package #:nshell/test)

(describe "expansion-tests"
  ;; Pure "expression -> value" cases read as one table each, asserted through
  ;; the :TO-EVALUATE-TO domain matcher (standard ARITH-ENV: X=10, Y=3).
  (it-each (("1 + 2 * 3" 7)
            ("(1 + 2) * 3" 9)
            ("10 % 3" 1)
            ("10 / 3" 3)
            ("-2 - 3" -5))
      "arithmetic-precedence: ~S evaluates to ~A"
      (expr value)
    (expect expr :to-evaluate-to value))

  (it-each (("X + Y" 13)
            ("X * Y" 30)
            ("UNSET" 0))
      "arithmetic-variables: ~S evaluates to ~A (unset names are 0)"
      (expr value)
    (expect expr :to-evaluate-to value))

  (it-each (("X > Y" 1)
            ("X < Y" 0)
            ("X == 10" 1)
            ("X > 0 && Y > 0" 1)
            ("!1" 0))
      "arithmetic-comparison/logic: ~S yields ~A"
      (expr value)
    (expect expr :to-evaluate-to value))

  ;; >=, <=, and != are distinct Pratt operators from >, <, ==.
  (it-each (("X >= 10" 1)
            ("X >= 11" 0)
            ("X <= 10" 1)
            ("X <= 9" 0)
            ("X != Y" 1)
            ("X != 10" 0))
      "arithmetic-comparison-le/ge/ne: ~S yields ~A"
      (expr value)
    (expect expr :to-evaluate-to value))

  ;; Unary + (the :pos prefix) is distinct from unary - / ! / ~.
  (it-each (("+5" 5)
            ("+X" 10)
            ("-(2 + 3)" -5)
            ("!0" 1)
            ("!!5" 1))
      "arithmetic-unary: ~S yields ~A"
      (expr value)
    (expect expr :to-evaluate-to value))

  (it "arithmetic-exponentiation-is-right-associative"
    "** binds tighter than unary minus and associates to the right (bash parity)."
    (let ((env (arith-env)))
      (expect 512 :to-equal (nshell.domain.expansion:evaluate-arithmetic "2 ** 3 ** 2" env))
      (expect -4 :to-equal (nshell.domain.expansion:evaluate-arithmetic "-2 ** 2" env))
      (expect 8 :to-equal (nshell.domain.expansion:evaluate-arithmetic "2 ** 3" env))
      (expect (lambda () (nshell.domain.expansion:evaluate-arithmetic "2 ** -1" env))
              :to-throw 'error)))

  ;; Bitwise/shift operators over integers; the final row pins precedence
  ;; (& tighter than ^ tighter than |).
  (it-each (("1 << 4" 16)
            ("256 >> 2" 64)
            ("6 & 3" 2)
            ("6 | 1" 7)
            ("5 ^ 1" 4)
            ("~0" -1)
            ("1 | 2 & 3 ^ 4" 7))
      "arithmetic-bitwise/shift: ~S yields ~A"
      (expr value)
    (expect expr :to-evaluate-to value))

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

  (it "arithmetic-logical-operators-short-circuit-errors"
    "Skipped branches must not evaluate division by zero."
    (let ((env (arith-env)))
      (expect 0 :to-equal
              (nshell.domain.expansion:evaluate-arithmetic "0 && (1 / 0)" env))
      (expect 1 :to-equal
              (nshell.domain.expansion:evaluate-arithmetic "1 || (1 / 0)" env))))

  (it "arithmetic-variable-coercion"
    "Unset and non-numeric variables evaluate to zero."
    (let ((env (arith-env)))
      (setf env (nshell.domain.environment:env-set env "NOT-A-NUMBER" "oops" nil))
      (expect 0 :to-equal
              (nshell.domain.expansion:evaluate-arithmetic "NOT-A-NUMBER" env))
      (expect 10 :to-equal
              (nshell.domain.expansion:evaluate-arithmetic "X + NOT-A-NUMBER" env))))

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

  (it "arithmetic-modulo-by-zero-signals"
    "Modulo by zero is an error rather than a crash-producing value."
    (expect (lambda () (nshell.domain.expansion:evaluate-arithmetic "1 % 0" (arith-env))) :to-throw 'error))

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

  (it "glob-star-does-not-cross-path-separators"
    "A single star matches within one path segment."
    (expect "*" :not-to-glob-match "a/b"))

  (it "glob-expansion-finds-files"
    "A star glob expands to matching files."
    (let* ((root (merge-pathnames (format nil "nshell-glob-~a/" (gensym))
                                  (host-kit:temporary-directory)))
           (pattern (namestring (merge-pathnames "*.txt" root)))
           (expected (namestring (merge-pathnames "alpha.txt" root)))
           (filesystem
             (make-test-filesystem
              :directory-files #'host-kit:directory-files
              :subdirectories #'host-kit:subdirectories)))
      (unwind-protect
           (progn
             (ensure-directories-exist root)
             (with-open-file (stream expected :direction :output :if-exists :supersede)
               (write-line "alpha" stream))
             (with-open-file (stream (merge-pathnames "beta.log" root)
                                     :direction :output :if-exists :supersede)
               (write-line "beta" stream))
             (expect (member expected
                             (nshell.domain.expansion:expand-glob pattern filesystem)
                             :test #'string=)
                     :to-be-truthy))
        (ignore-errors
          (when (probe-file root)
            (host-kit:delete-directory-tree root :validate t))))))

  (it "expand-glob-uses-immediate-directory-scope"
    "A non-recursive glob uses immediate directory candidates through expand-glob."
    (let* ((calls nil)
           (filesystem
             (make-test-filesystem
              :directory-files
              (lambda (dir)
                (push (list :files (namestring dir)) calls)
                (list (merge-pathnames "one.txt" dir)
                      (merge-pathnames "two.log" dir)))
              :subdirectories
              (lambda (dir)
                (push (list :subdirs (namestring dir)) calls)
                nil))))
      (expect (nshell.domain.expansion:expand-glob "/tmp/*.txt" filesystem)
              :to-equal '("/tmp/one.txt"))
      (expect '((:files "/tmp/")) :to-equal (nreverse calls))))

  (it "expand-glob-uses-recursive-directory-scope"
    "A ** pattern recursively enumerates candidates through expand-glob."
    (let* ((calls nil)
           (filesystem
             (make-test-filesystem
              :directory-files
              (lambda (dir)
                (push (list :files (namestring dir)) calls)
                (if (string= "/tmp/sub/" (namestring dir))
                    (list (merge-pathnames "one.txt" dir))
                    nil))
              :subdirectories
              (lambda (dir)
                (push (list :subdirs (namestring dir)) calls)
                (if (string= "/tmp/" (namestring dir))
                    (list #p"/tmp/sub/")
                    nil)))))
      (expect (nshell.domain.expansion:expand-glob "/tmp/**/*.txt" filesystem)
              :to-equal '("/tmp/sub/one.txt"))
      (expect '((:files "/tmp/")
                (:subdirs "/tmp/")
                (:files "/tmp/sub/")
                (:subdirs "/tmp/sub/"))
              :to-equal
              (nreverse calls))))

  (it "glob-filesystem-without-capability-is-empty"
    "Filesystem traversal stays inert without an explicit filesystem capability."
    (expect (nshell.domain.expansion::immediate-directory-files "/tmp")
            :to-be-null)
    (expect (nshell.domain.expansion::recursive-directory-files "/tmp")
            :to-be-null))

  (it "expand-glob-preserves-unmatched-pattern"
    "A glob with no filesystem matches remains a literal argument."
    (let ((filesystem (make-test-filesystem)))
      (expect '("/tmp/*.txt")
              :to-equal
              (nshell.domain.expansion:expand-glob "/tmp/*.txt" filesystem))))

  (it "expand-all-preserves-unmatched-assignment-glob"
    "An unmatched assignment-like glob keeps its prefix and literal suffix."
    (let ((env (test-expansion-env))
          (filesystem (make-test-filesystem)))
      (expect '("label=*.txt")
              :to-equal
              (nshell.domain.expansion:expand-all "label=*.txt" env filesystem))))

  (it "expand-glob-projects-relative-root-candidates"
    "A ./ glob root projects candidates without leaking the implicit directory prefix.
The fake mirrors host-kit's real merge-pathnames behavior for a \"./\" root, which
namestrings each entry as \"./alpha.txt\" rather than bare \"alpha.txt\" -- before the
fix, expand-glob pushed that raw namestring, so this would have failed on
'(\"./alpha.txt\") instead of '(\"alpha.txt\")."
    (let* ((calls nil)
           (filesystem
             (make-test-filesystem
              :directory-files
              (lambda (dir)
                (push (namestring dir) calls)
                (list #p"./alpha.txt" #p"./beta.log"))
              :subdirectories (constantly nil))))
      (expect (nshell.domain.expansion:expand-glob "*.txt" filesystem)
              :to-equal '("alpha.txt"))
      (expect '("./") :to-equal (nreverse calls))))

  (it "expand-glob-strips-dot-slash-prefix-from-results"
    "A bare-name pattern under an implicit \"./\" root returns bare matches, matching
fish/bash, instead of leaking the \"./\" root prefix into the result. Before the fix
(pushing (namestring file) instead of the normalized match candidate), this would
have failed on '(\"./g1.txt\") instead of '(\"g1.txt\")."
    (let ((filesystem
            (make-test-filesystem
             :directory-files
             (lambda (dir)
               (declare (ignore dir))
               (list #p"./g1.txt"))
             :subdirectories (constantly nil))))
      (expect (nshell.domain.expansion:expand-glob "g*.txt" filesystem)
              :to-equal '("g1.txt"))))

  (it "expand-glob-keeps-prefix-for-relative-directory-root"
    "A pattern rooted in a named relative directory (src/*.lisp) keeps the src/
prefix on its results -- only the implicit \"./\" root is stripped, not an
explicit one. Before the fix, the pushed result and the matched candidate could
diverge; here they coincide already, so this pins that a correct \"src/\" prefix
survives the fix and is not accidentally stripped too."
    (let ((filesystem
            (make-test-filesystem
             :directory-files
             (lambda (dir)
               (declare (ignore dir))
               (list #p"src/foo.lisp" #p"src/bar.txt"))
             :subdirectories (constantly nil))))
      (expect (nshell.domain.expansion:expand-glob "src/*.lisp" filesystem)
              :to-equal '("src/foo.lisp"))))

  (it "expand-all-reattaches-assignment-like-glob-prefixes"
    "expand-all separates label-like prefixes from glob suffixes without treating paths as labels."
    (let ((env (test-expansion-env))
          (filesystem
            (make-test-filesystem
             :directory-files
             ;; The "./" branch mirrors host-kit's real behavior for an
             ;; implicit root -- entries namestring as "./alpha.txt", not
             ;; bare "alpha.txt" -- same as the corrected fakes above; a
             ;; bare-name fake here would mask a "./" -stripping regression.
             (lambda (dir)
               (if (string= "./" (namestring dir))
                   (list #p"./alpha.txt" #p"./beta.log" #p"./bar1.lisp")
                   (list (merge-pathnames "alpha.txt" dir)
                         (merge-pathnames "beta.log" dir)
                         (merge-pathnames "bar1.lisp" dir))))
             :subdirectories (constantly nil))))
      (expect '("label=alpha.txt") :to-equal
               (nshell.domain.expansion:expand-all "label=*.txt" env filesystem))
      (expect '("env:FOO=bar1.lisp") :to-equal
               (nshell.domain.expansion:expand-all "env:FOO=bar?.lisp" env filesystem))
      (expect '("/tmp/a=b/alpha.txt") :to-equal
               (nshell.domain.expansion:expand-all "/tmp/a=b/*.txt" env filesystem))))

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
    (expect "file[0-2].lisp" :to-glob-match "file1.lisp")
    (expect "file[0-2].lisp" :not-to-glob-match "file9.lisp"))

  (it "glob-bracket-negation-matches-outside-set"
    "Bracket negation matches characters outside the declared set."
    (expect "file[!0-2].lisp" :to-glob-match "file9.lisp")
    (expect "file[!0-2].lisp" :not-to-glob-match "file1.lisp")
    (expect "file[^ab].lisp" :to-glob-match "filez.lisp")
    (expect "file[^ab].lisp" :not-to-glob-match "filea.lisp"))

  (it "glob-unclosed-bracket-matches-literal"
    "An unclosed bracket is treated as a literal character."
    (expect "file[1" :to-glob-match "file[1")
    (expect "file[1" :not-to-glob-match "file11"))

  (it "pbt-glob-ranges-match-generated-members"
    "Generated characters inside a bracket range always match that range."
    (check-property (:trials 50)
        ((start (gen-in-range 97 122) #'shrink-integer)
         (end (gen-in-range 97 122) #'shrink-integer))
      (let* ((lo (code-char (min start end)))
             (hi (code-char (max start end)))
             (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
        (nshell.domain.expansion:glob-match-p (format nil "[~c-~c]" lo hi)
                                              (string mid)))))

  (it "pbt-glob-negated-ranges-reject-generated-members"
    "Generated characters inside a negated bracket range never match that range."
    (check-property (:trials 50)
        ((start (gen-in-range 97 122) #'shrink-integer)
         (end (gen-in-range 97 122) #'shrink-integer))
      (let* ((lo (code-char (min start end)))
             (hi (code-char (max start end)))
             (mid (code-char (floor (+ (char-code lo) (char-code hi)) 2))))
        (not (nshell.domain.expansion:glob-match-p (format nil "[!~c-~c]" lo hi)
                                                   (string mid))))))

  (it "pbt-glob-literal-matches-only-itself"
    "A metacharacter-free pattern matches its own text and nothing longer."
    (check-property (:trials 50)
        ((word (gen-shell-variable-name :min-length 1 :max-length 10)
               #'shrink-prompt-text))
      (and (nshell.domain.expansion:glob-match-p word word)
           (not (nshell.domain.expansion:glob-match-p
                 word (concatenate 'string word "x"))))))

  (it "pbt-glob-star-matches-any-single-segment"
    "* matches any string that contains no path separator."
    (check-property (:trials 50)
        ((word (gen-shell-variable-name :min-length 1 :max-length 10)
               #'shrink-prompt-text))
      (nshell.domain.expansion:glob-match-p "*" word)))

  (it "pbt-brace-numeric-range-size-matches-span"
    "A numeric range {lo..hi} (lo<=hi) expands to exactly hi-lo+1 items."
    (check-property (:trials 50)
        ((lo (gen-in-range 0 20) #'shrink-integer)
         (span (gen-in-range 0 15) #'shrink-integer))
      (let ((result (nshell.domain.expansion:expand-braces
                     (format nil "{~d..~d}" lo (+ lo span)))))
        (= (length result) (1+ span)))))

  (it "pbt-brace-comma-group-size-matches-option-count"
    "A single comma group of N distinct options expands to exactly N items."
    (check-property (:trials 40)
        ((n (gen-in-range 2 6) #'shrink-integer))
      (let* ((options (loop for i from 1 to n collect (format nil "o~d" i)))
             (result (nshell.domain.expansion:expand-braces
                      (format nil "{~{~a~^,~}}" options))))
        (= (length result) n))))

  (it "pbt-arithmetic-integer-literal-is-identity"
    "Evaluating a bare integer literal yields that integer."
    (check-property (:trials 50)
        ((n (gen-in-range -1000 1000) #'shrink-integer))
      (= n (nshell.domain.expansion:evaluate-arithmetic
            (format nil "~d" n) (arith-env)))))

  (it "pbt-arithmetic-addition-is-commutative"
    "a + b and b + a evaluate equal for any generated integers."
    (check-property (:trials 50)
        ((a (gen-in-range -500 500) #'shrink-integer)
         (b (gen-in-range -500 500) #'shrink-integer))
      (= (nshell.domain.expansion:evaluate-arithmetic
          (format nil "~d + ~d" a b) (arith-env))
         (nshell.domain.expansion:evaluate-arithmetic
          (format nil "~d + ~d" b a) (arith-env)))))

  (it "pbt-arithmetic-add-then-subtract-recovers-operand"
    "(a + b) - b evaluates to a."
    (check-property (:trials 50)
        ((a (gen-in-range -500 500) #'shrink-integer)
         (b (gen-in-range -500 500) #'shrink-integer))
      (= a (nshell.domain.expansion:evaluate-arithmetic
            (format nil "(~d + ~d) - ~d" a b b) (arith-env)))))

  (it "pbt-arithmetic-multiply-by-zero-is-zero"
    "a * 0 evaluates to 0 for any generated a."
    (check-property (:trials 50)
        ((a (gen-in-range -1000 1000) #'shrink-integer))
      (zerop (nshell.domain.expansion:evaluate-arithmetic
              (format nil "~d * 0" a) (arith-env)))))

  (it "pbt-glob-double-star-crosses-separators-single-star-does-not"
    "** spans a path separator that a single * cannot."
    (check-property (:trials 50)
        ((a (gen-shell-variable-name :min-length 1 :max-length 6) #'shrink-shell-word)
         (b (gen-shell-variable-name :min-length 1 :max-length 6) #'shrink-shell-word))
      (let ((path (concatenate 'string a "/" b)))
        (and (nshell.domain.expansion:glob-match-p "**" path)
             (not (nshell.domain.expansion:glob-match-p "*" path))))))

  (it "pbt-brace-without-braces-is-identity"
    "A string with no brace group expands to exactly itself."
    (check-property (:trials 50)
        ((word (gen-shell-variable-name :min-length 1 :max-length 12) #'shrink-shell-word))
      (equal (list word)
             (nshell.domain.expansion:expand-braces word)))))
