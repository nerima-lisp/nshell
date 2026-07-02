(in-package #:nshell/test)
(in-suite expansion-tests)

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

(test parse-argv-index-parses-integer-or-returns-default
  "parse-argv-index returns the parsed integer, default for empty string, nil on failure."
  (flet ((parse (text &optional default)
           (nshell.domain.expansion::%parse-argv-index text default)))
    (is (= 3  (parse "3")))
    (is (= -1 (parse "-1")))
    (is (null (parse "abc")))
    (is (= 0  (parse "" 0)))
    (is (null (parse "")))))

(test argv-normalized-index-converts-fish-style-indices-to-zero-based
  "argv-normalized-index converts 1-based and negative indices to 0-based offsets."
  (flet ((norm (index count)
           (nshell.domain.expansion::%argv-normalized-index index count)))
    (is (= 0  (norm 1 5)))
    (is (= 4  (norm 5 5)))
    (is (= 4  (norm -1 5)))
    (is (= 0  (norm -5 5)))
    (is (null (norm 0 5)))
    (is (null (norm nil 5)))))

(test list-index-field-selects-one-element-by-fish-index
  "list-index-field returns the element at a 1-based fish-style index."
  (flet ((idx (fields index)
           (nshell.domain.expansion::%list-index-field fields index)))
    (is (equal '("b") (idx '("a" "b" "c") 2)))
    (is (equal '("c") (idx '("a" "b" "c") -1)))
    (is (null          (idx '("a" "b" "c") 5)))
    (is (null          (idx '("a" "b" "c") 0)))))

(test list-range-fields-selects-ordered-sublist
  "list-range-fields selects ascending or descending sub-lists by fish-style indices."
  (flet ((range (fields start end)
           (nshell.domain.expansion::%list-range-fields fields start end)))
    (is (equal '("a" "b") (range '("a" "b" "c") 1 2)))
    (is (equal '("c" "b") (range '("a" "b" "c") -1 2)))
    (is (null              (range '("a" "b") 0 2)))))

(test join-fields-concatenates-with-spaces
  "join-fields joins a list of strings with single spaces."
  (flet ((join (fields)
           (nshell.domain.expansion::%join-fields fields)))
    (is (string= ""        (join nil)))
    (is (string= "a"       (join '("a"))))
    (is (string= "a b c"   (join '("a" "b" "c"))))))

(test append-list-reference-fields-cross-products-prefixes-and-fields
  "append-list-reference-fields produces every prefix+field combination."
  (flet ((cross (prefixes fields)
           (nshell.domain.expansion::%append-list-reference-fields prefixes fields)))
    ;; single prefix, multiple fields
    (is (equal '("a-x" "a-y") (cross '("a-") '("x" "y"))))
    ;; multiple prefixes, single field
    (is (equal '("a-z" "b-z") (cross '("a-" "b-") '("z"))))
    ;; nil fields treated as ("") — empty field appended
    (is (equal '("a-" "b-") (cross '("a-" "b-") nil)))
    ;; multiple prefixes and fields: cartesian product in order
    (is (equal '("p-x" "p-y" "q-x" "q-y")
               (cross '("p-" "q-") '("x" "y"))))))
