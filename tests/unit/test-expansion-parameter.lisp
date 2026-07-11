(in-package #:nshell/test)


(in-suite expansion-tests)

(defmacro %assert-parameter-operator-fields (form op word colon-p)
  `(let ((operator ,form))
     (is (equal ,op (nshell.domain.expansion::parameter-operator-op operator)))
     (is (string= ,word
                  (nshell.domain.expansion::parameter-operator-word-text operator)))
     (is (eq ,colon-p
             (nshell.domain.expansion::parameter-operator-colon-p operator)))))

(defmacro %assert-parameter-binding-fields (form set-p value)
  `(let ((binding ,form))
     (is (eq ,set-p (nshell.domain.expansion::parameter-binding-set-p binding)))
     (is (string= ,value
                  (nshell.domain.expansion::parameter-binding-value binding)))))

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

(test parameter-required-operator-signals-for-unset-or-null-values
  "${VAR?word} and ${VAR:?word} signal only when their unset/null predicate matches."
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "FULL" "value" nil))
    (setf env (nshell.domain.environment:env-set env "EMPTY" "" nil))
    (is (string= "value"
                 (nshell.domain.expansion:expand-variables "${FULL:?required}" env)))
    (is (string= ""
                 (nshell.domain.expansion:expand-variables "${EMPTY?required}" env)))
    (signals nshell.domain.expansion:parameter-expansion-error
      (nshell.domain.expansion:expand-variables "${MISSING?required}" env))
    (signals nshell.domain.expansion:parameter-expansion-error
      (nshell.domain.expansion:expand-variables "${EMPTY:?required}" env))
    (handler-case
        (nshell.domain.expansion:expand-variables "${MISSING:?required value}" env)
      (nshell.domain.expansion:parameter-expansion-error (condition)
        (is (string= "MISSING"
                     (nshell.domain.expansion:parameter-expansion-error-name condition)))
        (is (string= "required value"
                     (nshell.domain.expansion:parameter-expansion-error-message condition)))))))

(test parameter-required-operator-uses-default-diagnostics
  "${VAR?} and ${VAR:?} provide useful diagnostics when no word is supplied."
  (let ((env (nshell.domain.environment:make-environment)))
    (handler-case
        (nshell.domain.expansion:expand-variables "${MISSING?}" env)
      (nshell.domain.expansion:parameter-expansion-error (condition)
        (is (string= "parameter not set"
                     (nshell.domain.expansion:parameter-expansion-error-message condition)))))
    (handler-case
        (nshell.domain.expansion:expand-variables "${MISSING:?}" env)
      (nshell.domain.expansion:parameter-expansion-error (condition)
        (is (string= "parameter null or not set"
                     (nshell.domain.expansion:parameter-expansion-error-message condition)))))))

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
    (let ((entries (nshell.domain.environment:env-list env)))
      (is (= 1 (length entries)))
      (is (string= "EMPTY"
                   (nshell.domain.environment:env-entry-name (first entries))))
      (is (string= "filled"
                   (nshell.domain.environment:env-entry-value (first entries)))))))

(test parameter-length
  "${#VAR} yields the length of the variable's value."
  (let ((env (test-expansion-env)))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("3" "${#FOO}")
      ("0" "${#MISSING}"))))

(test parameter-substring
  "${VAR:offset[:length]} extracts substrings without stealing :- operators."
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "LONG" "abcdef" nil))
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       env)
      ("bcdef" "${LONG:1}")
      ("bcd" "${LONG:1:3}")
      ("" "${LONG:0:0}")
      ("ef" "${LONG: -2}")
      ("cd" "${LONG:2:-2}")
      ("abcdef" "${LONG:-1}")
      ("1" "${MISSING:-1}")
      ("" "${LONG:99}")
      ("fallback" "${MISSING:-fallback}")
      ("abcdef:abc" "${LONG:abc}"))))

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

  (test parameter-operator-parts-classifies-colon-and-word
    "parameter-operator-parts projects a braced operator tail into a value object."
    (flet ((operator (rest)
             (nshell.domain.expansion::%parameter-operator-parts rest)))
      (%assert-parameter-operator-fields (operator ":-fallback") #\- "fallback" t)
      (%assert-parameter-operator-fields (operator "+yes") #\+ "yes" nil)
      (%assert-parameter-operator-fields (operator "##pat") #\# "#pat" nil)
      (%assert-parameter-operator-fields (operator "") nil "" nil)))

  (test parameter-binding-tracks-set-empty-and-default-applicability
    "parameter-binding keeps env lookup state separate from braced operator parsing."
    (let ((env (nshell.domain.environment:make-environment)))
      (setf env (nshell.domain.environment:env-set env "EMPTY" "" nil))
      (setf env (nshell.domain.environment:env-set env "FULL" "value" nil))
      (let ((missing (nshell.domain.expansion::%parameter-binding "MISSING" env))
            (empty (nshell.domain.expansion::%parameter-binding "EMPTY" env))
            (full (nshell.domain.expansion::%parameter-binding "FULL" env))
            (colon-default (nshell.domain.expansion::%parameter-operator-parts ":-fallback"))
            (unset-default (nshell.domain.expansion::%parameter-operator-parts "-fallback")))
        (%assert-parameter-binding-fields missing nil "")
        (%assert-parameter-binding-fields empty t "")
        (%assert-parameter-binding-fields full t "value")
        (is (nshell.domain.expansion::parameter-binding-p missing))
        (is (nshell.domain.expansion::%parameter-default-applicable-p missing unset-default))
        (is (not (nshell.domain.expansion::%parameter-default-applicable-p empty unset-default)))
        (is (nshell.domain.expansion::%parameter-default-applicable-p empty colon-default))
        (is (not (nshell.domain.expansion::%parameter-default-applicable-p full colon-default))))))

(test apply-parameter-operator-owns-braced-operator-semantics
  "apply-parameter-operator maps parsed operators and bindings to expansion results."
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "FULL" "value" nil))
    (let ((missing (nshell.domain.expansion::%parameter-binding "MISSING" env))
          (full (nshell.domain.expansion::%parameter-binding "FULL" env))
          (default (nshell.domain.expansion::%parameter-operator-parts ":-fallback"))
          (alternate (nshell.domain.expansion::%parameter-operator-parts ":+alt"))
          (required (nshell.domain.expansion::%parameter-operator-parts ":?required"))
          (unknown (nshell.domain.expansion::%parameter-operator-parts ":!tail")))
      (flet ((apply-op (binding operator word rest)
               (nshell.domain.expansion::%apply-parameter-operator
                binding operator word rest env)))
        (is (string= "fallback" (apply-op missing default "fallback" ":-fallback")))
        (is (string= "value" (apply-op full default "fallback" ":-fallback")))
        (is (string= "" (apply-op missing alternate "alt" ":+alt")))
        (is (string= "alt" (apply-op full alternate "alt" ":+alt")))
        (is (string= "value" (apply-op full required "required" ":?required")))
        (signals nshell.domain.expansion:parameter-expansion-error
          (apply-op missing required "required" ":?required"))
        (is (string= "value:!tail" (apply-op full unknown "tail" ":!tail")))))))

(test parse-argv-index-parses-integer-or-returns-default
  "parse-argv-index returns the parsed integer, default for empty string, nil on failure."
  (flet ((parse (text &optional default)
           (nshell.domain.expansion::%parse-argv-index text default)))
    (is (= 3 (parse "3")))
    (is (= -1 (parse "-1")))
    (is (null (parse "abc")))
    (is (= 0 (parse "" 0)))
    (is (null (parse "")))))

(test list-selection-spec-classifies-index-and-range
  "list-selection-spec separates raw bracket syntax from list field selection."
  (let ((index (nshell.domain.expansion::%list-selection-spec "2"))
        (range (nshell.domain.expansion::%list-selection-spec "2..-1"))
        (open-range (nshell.domain.expansion::%list-selection-spec "..")))
    (is (nshell.domain.expansion::list-selection-spec-p index))
    (is (eq :index (nshell.domain.expansion::list-selection-spec-kind index)))
    (is (= 2 (nshell.domain.expansion::list-selection-spec-start-index index)))
    (is (null (nshell.domain.expansion::list-selection-spec-end-index index)))
    (is (eq :range (nshell.domain.expansion::list-selection-spec-kind range)))
    (is (= 2 (nshell.domain.expansion::list-selection-spec-start-index range)))
    (is (= -1 (nshell.domain.expansion::list-selection-spec-end-index range)))
    (is (= 1 (nshell.domain.expansion::list-selection-spec-start-index open-range)))
    (is (= -1 (nshell.domain.expansion::list-selection-spec-end-index open-range)))
    (is (equal '("b" "c")
               (nshell.domain.expansion::%list-selection-spec-fields
                '("a" "b" "c")
                range)))))

(test bracket-spec-after-name-classifies-index-syntax
  "Bracket syntax is classified before argv/env lookup applies index semantics."
  (%assert-multiple-value-cases (equal
                                 (lambda (input name-end)
                                   (nshell.domain.expansion::%bracket-spec-after-name
                                    input name-end (length input))))
    (("2..-1" 12 :indexed) "$argv[2..-1]" 5)
    ((nil 5 :unbalanced) "$argv[2" 5)
    ((nil) "$argv" 5)))

(test variable-reference-syntax-at-projects-name-and-bracket
  "variable-reference-syntax-at owns $NAME scanning and bracket classification."
  (flet ((syntax (input)
           (nshell.domain.expansion::%variable-reference-syntax-at
            input 0 (length input))))
    (let ((indexed (syntax "$WORDS[2..-1]"))
          (bare (syntax "$FOO"))
          (unbalanced (syntax "$WORDS[2")))
      (is (nshell.domain.expansion::variable-reference-syntax-p indexed))
      (is (string= "WORDS"
                   (nshell.domain.expansion::variable-reference-syntax-name indexed)))
      (is (= 6
             (nshell.domain.expansion::variable-reference-syntax-name-end indexed)))
      (is (eq :indexed
              (nshell.domain.expansion::variable-reference-syntax-bracket-status indexed)))
      (is (string= "2..-1"
                   (nshell.domain.expansion::variable-reference-syntax-bracket-spec indexed)))
      (is (= 13
             (nshell.domain.expansion::%variable-reference-next-index indexed)))
      (is (null (nshell.domain.expansion::variable-reference-syntax-bracket-status bare)))
      (is (= 4
             (nshell.domain.expansion::%variable-reference-next-index bare)))
      (is (eq :unbalanced
              (nshell.domain.expansion::variable-reference-syntax-bracket-status unbalanced)))
      (is (= 6
             (nshell.domain.expansion::%variable-reference-next-index unbalanced)))
      (is (null (syntax "$1"))))))

(test argv-expansion-after-name-resolves-bare-and-indexed-argv
  "argv-expansion-after-name owns bare join vs indexed argv expansion semantics."
  (let ((nshell.domain.expansion:*positional-args* '("alpha" "beta" "gamma")))
    (%assert-after-name-expansion-cases
        ((lambda (input)
           (nshell.domain.expansion::%argv-expansion-after-name
            input 5 (length input))))
      (("alpha beta gamma" 5) "$argv")
      (("beta" 8) "$argv[2]"))))

(test variable-expansion-after-name-resolves-scalar-and-indexed-values
  "variable-expansion-after-name owns scalar fallback vs indexed env expansion semantics."
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "SCALAR" "plain" nil))
    (setf env (nshell.domain.environment:env-set-values
               env "WORDS" '("one" "two" "three") nil))
    (%assert-after-name-expansion-cases
        ((lambda (input name name-end)
           (nshell.domain.expansion::%variable-expansion-after-name
            input name env name-end (length input))))
      (("plain" 7) "$SCALAR" "SCALAR" 7)
      (("two" 9) "$WORDS[2]" "WORDS" 6))))

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
