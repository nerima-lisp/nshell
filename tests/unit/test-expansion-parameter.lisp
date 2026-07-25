(in-package #:nshell/test)

(defmacro %assert-parameter-operator-fields (form op word colon-p)
  `(let ((operator ,form))
     (expect ,op :to-equal (nshell.domain.expansion::parameter-operator-op operator))
     (expect ,word :to-equal (nshell.domain.expansion::parameter-operator-word-text operator))
     (expect ,colon-p :to-be (nshell.domain.expansion::parameter-operator-colon-p operator))))

(defmacro %assert-parameter-binding-fields (form set-p value)
  `(let ((binding ,form))
     (expect ,set-p :to-be (nshell.domain.expansion::parameter-binding-set-p binding))
     (expect ,value :to-equal (nshell.domain.expansion::parameter-binding-value binding))))

(describe "expansion-tests"
  (it "parameter-default-when-unset"
    "${VAR:-word} yields the value when set and the word when unset/empty."
    (let ((env (test-expansion-env)))
      (%assert-expansion-cases-with-env (string=
                                         #'nshell.domain.expansion:expand-variables
                                         env)
        ("bar" "${FOO:-fallback}")
        ("fallback" "${MISSING:-fallback}")
        ("bar" "${MISSING:-$FOO}"))))

  (it "parameter-alternative-when-set"
    "${VAR:+word} yields the word only when the variable is set and non-empty."
    (let ((env (test-expansion-env)))
      (%assert-expansion-cases-with-env (string=
                                         #'nshell.domain.expansion:expand-variables
                                         env)
        ("yes" "${FOO:+yes}")
        ("" "${MISSING:+yes}"))))

  (it "parameter-required-operator-signals-for-unset-or-null-values"
    "${VAR?word} and ${VAR:?word} signal only when their unset/null predicate matches."
    (let ((env (nshell.domain.environment:make-environment)))
      (setf env (nshell.domain.environment:env-set env "FULL" "value" nil))
      (setf env (nshell.domain.environment:env-set env "EMPTY" "" nil))
      (expect "value" :to-equal (nshell.domain.expansion:expand-variables "${FULL:?required}" env))
      (expect "" :to-equal (nshell.domain.expansion:expand-variables "${EMPTY?required}" env))
      (expect (lambda () (nshell.domain.expansion:expand-variables "${MISSING?required}" env)) :to-throw 'nshell.domain.expansion:parameter-expansion-error)
      (expect (lambda () (nshell.domain.expansion:expand-variables "${EMPTY:?required}" env)) :to-throw 'nshell.domain.expansion:parameter-expansion-error)
      (handler-case
          (nshell.domain.expansion:expand-variables "${MISSING:?required value}" env)
        (nshell.domain.expansion:parameter-expansion-error (condition)
          (expect "MISSING" :to-equal (nshell.domain.expansion:parameter-expansion-error-name condition))
          (expect "required value" :to-equal (nshell.domain.expansion:parameter-expansion-error-message condition))))))

  (it "parameter-required-operator-uses-default-diagnostics"
    "${VAR?} and ${VAR:?} provide useful diagnostics when no word is supplied."
    (let ((env (nshell.domain.environment:make-environment)))
      (handler-case
          (nshell.domain.expansion:expand-variables "${MISSING?}" env)
        (nshell.domain.expansion:parameter-expansion-error (condition)
          (expect "parameter not set" :to-equal (nshell.domain.expansion:parameter-expansion-error-message condition))))
      (handler-case
          (nshell.domain.expansion:expand-variables "${MISSING:?}" env)
        (nshell.domain.expansion:parameter-expansion-error (condition)
          (expect "parameter null or not set" :to-equal (nshell.domain.expansion:parameter-expansion-error-message condition))))))

  (it "parameter-assign-default-side-effect"
    "${VAR:=word} assigns the expanded default only when the operator fires."
    (let ((source-env (test-expansion-env))
          (env (nshell.domain.environment:make-environment)))
      (expect "bar" :to-equal (nshell.domain.expansion:expand-variables
                    "${MISSING:=$FOO}" source-env))
      (expect "bar" :to-equal (nshell.domain.environment:env-get source-env "MISSING"))
      (expect "default" :to-equal (nshell.domain.expansion:expand-variables
                    "${MISSING:=default}" env))
      (expect "default" :to-equal (nshell.domain.environment:env-get env "MISSING"))
      (expect "default" :to-equal (nshell.domain.expansion:expand-variables
                    "${MISSING:=other}" env))
      (expect "default" :to-equal (nshell.domain.environment:env-get env "MISSING"))))

  (it "parameter-assign-default-preserves-export-state"
    "${VAR:=word} keeps an existing variable's exported state when assigning."
    (let ((env (nshell.domain.environment:make-environment)))
      (setf env (nshell.domain.environment:env-set env "EMPTY" "" t))
      (expect "filled" :to-equal (nshell.domain.expansion:expand-variables
                    "${EMPTY:=filled}" env))
      (let ((entries (nshell.domain.environment:env-list env)))
        (expect 1 :to-equal (length entries))
        (expect "EMPTY" :to-equal (nshell.domain.environment:env-entry-name (first entries)))
        (expect "filled" :to-equal (nshell.domain.environment:env-entry-value (first entries))))))

  (it "parameter-length"
    "${#VAR} yields the length of the variable's value."
    (let ((env (test-expansion-env)))
      (%assert-expansion-cases-with-env (string=
                                         #'nshell.domain.expansion:expand-variables
                                         env)
        ("3" "${#FOO}")
        ("0" "${#MISSING}"))))

  (it "parameter-substring"
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

  (it "parameter-prefix-and-suffix-strip"
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

  (it "parameter-substitution-operator"
    "${VAR/pat/rep} replaces the first match; // replaces all (literal)."
    (let ((env (nshell.domain.environment:make-environment)))
      (setf env (nshell.domain.environment:env-set env "P" "a-a-a" nil))
      (%assert-expansion-cases-with-env (string=
                                         #'nshell.domain.expansion:expand-variables
                                         env)
        ("X-a-a" "${P/a/X}")
        ("X-X-X" "${P//a/X}")
        ("a-a-a" "${P/z/X}"))))

  (it "parameter-plain-brace-still-works"
    "Plain ${VAR} expansion is unchanged by the operator support."
    (%assert-expansion-cases-with-env (string=
                                       #'nshell.domain.expansion:expand-variables
                                       (test-expansion-env))
      ("value=bar" "value=${FOO}")))

    (it "parameter-operator-parts-classifies-colon-and-word"
      "parameter-operator-parts projects a braced operator tail into a value object."
      (flet ((operator (rest)
               (nshell.domain.expansion::%parameter-operator-parts rest)))
        (%assert-parameter-operator-fields (operator ":-fallback") #\- "fallback" t)
        (%assert-parameter-operator-fields (operator "+yes") #\+ "yes" nil)
        (%assert-parameter-operator-fields (operator "##pat") #\# "#pat" nil)
        (%assert-parameter-operator-fields (operator "") nil "" nil)))

    (it "parameter-binding-tracks-set-empty-and-default-applicability"
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
          (expect (nshell.domain.expansion::parameter-binding-p missing) :to-be-truthy)
          (expect (nshell.domain.expansion::%parameter-default-applicable-p missing unset-default) :to-be-truthy)
          (expect (nshell.domain.expansion::%parameter-default-applicable-p empty unset-default) :to-be-falsy)
          (expect (nshell.domain.expansion::%parameter-default-applicable-p empty colon-default) :to-be-truthy)
          (expect (nshell.domain.expansion::%parameter-default-applicable-p full colon-default) :to-be-falsy))))

  (it "apply-parameter-operator-owns-braced-operator-semantics"
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
          (expect "fallback" :to-equal (apply-op missing default "fallback" ":-fallback"))
          (expect "value" :to-equal (apply-op full default "fallback" ":-fallback"))
          (expect "" :to-equal (apply-op missing alternate "alt" ":+alt"))
          (expect "alt" :to-equal (apply-op full alternate "alt" ":+alt"))
          (expect "value" :to-equal (apply-op full required "required" ":?required"))
          (expect (lambda () (apply-op missing required "required" ":?required")) :to-throw 'nshell.domain.expansion:parameter-expansion-error)
          (expect "value:!tail" :to-equal (apply-op full unknown "tail" ":!tail"))))))

  (it "parse-argv-index-parses-integer-or-returns-default"
    "parse-argv-index returns the parsed integer, default for empty string, nil on failure."
    (flet ((parse (text &optional default)
             (nshell.domain.expansion::%parse-argv-index text default)))
      (expect 3 :to-equal (parse "3"))
      (expect -1 :to-equal (parse "-1"))
      (expect (parse "abc") :to-be-null)
      (expect 0 :to-equal (parse "" 0))
      (expect (parse "") :to-be-null)))

  (it "list-selection-spec-classifies-index-and-range"
    "list-selection-spec separates raw bracket syntax from list field selection."
    (let ((index (nshell.domain.expansion::%list-selection-spec "2"))
          (range (nshell.domain.expansion::%list-selection-spec "2..-1"))
          (open-range (nshell.domain.expansion::%list-selection-spec "..")))
      (expect (nshell.domain.expansion::list-selection-spec-p index) :to-be-truthy)
      (expect :index :to-be (nshell.domain.expansion::list-selection-spec-kind index))
      (expect 2 :to-equal (nshell.domain.expansion::list-selection-spec-start-index index))
      (expect (nshell.domain.expansion::list-selection-spec-end-index index) :to-be-null)
      (expect :range :to-be (nshell.domain.expansion::list-selection-spec-kind range))
      (expect 2 :to-equal (nshell.domain.expansion::list-selection-spec-start-index range))
      (expect -1 :to-equal (nshell.domain.expansion::list-selection-spec-end-index range))
      (expect 1 :to-equal (nshell.domain.expansion::list-selection-spec-start-index open-range))
      (expect -1 :to-equal (nshell.domain.expansion::list-selection-spec-end-index open-range))
      (expect '("b" "c") :to-equal (nshell.domain.expansion::%list-selection-spec-fields
                  '("a" "b" "c")
                  range))))

  (it "bracket-spec-after-name-classifies-index-syntax"
    "Bracket syntax is classified before argv/env lookup applies index semantics."
    (%assert-multiple-value-cases (equal
                                   (lambda (input name-end)
                                     (nshell.domain.expansion::%bracket-spec-after-name
                                      input name-end (length input))))
      (("2..-1" 12 :indexed) "$argv[2..-1]" 5)
      ((nil 5 :unbalanced) "$argv[2" 5)
      ((nil) "$argv" 5)))

  (it "variable-reference-syntax-at-projects-name-and-bracket"
    "variable-reference-syntax-at owns $NAME scanning and bracket classification."
    (flet ((syntax (input)
             (nshell.domain.expansion::%variable-reference-syntax-at
              input 0 (length input))))
      (let ((indexed (syntax "$WORDS[2..-1]"))
            (bare (syntax "$FOO"))
            (unbalanced (syntax "$WORDS[2")))
        (expect (nshell.domain.expansion::variable-reference-syntax-p indexed) :to-be-truthy)
        (expect "WORDS" :to-equal (nshell.domain.expansion::variable-reference-syntax-name indexed))
        (expect 6 :to-equal (nshell.domain.expansion::variable-reference-syntax-name-end indexed))
        (expect :indexed :to-be (nshell.domain.expansion::variable-reference-syntax-bracket-status indexed))
        (expect "2..-1" :to-equal (nshell.domain.expansion::variable-reference-syntax-bracket-spec indexed))
        (expect 13 :to-equal (nshell.domain.expansion::%variable-reference-next-index indexed))
        (expect (nshell.domain.expansion::variable-reference-syntax-bracket-status bare) :to-be-null)
        (expect 4 :to-equal (nshell.domain.expansion::%variable-reference-next-index bare))
        (expect :unbalanced :to-be (nshell.domain.expansion::variable-reference-syntax-bracket-status unbalanced))
        (expect 6 :to-equal (nshell.domain.expansion::%variable-reference-next-index unbalanced))
        (expect (syntax "$1") :to-be-null))))

  (it "argv-expansion-after-name-resolves-bare-and-indexed-argv"
    "argv-expansion-after-name owns bare join vs indexed argv expansion semantics."
    (let ((nshell.domain.expansion:*positional-args* '("alpha" "beta" "gamma")))
      (%assert-after-name-expansion-cases
          ((lambda (input)
             (nshell.domain.expansion::%argv-expansion-after-name
              input 5 (length input))))
        (("alpha beta gamma" 5) "$argv")
        (("beta" 8) "$argv[2]"))))

  (it "variable-expansion-after-name-resolves-scalar-and-indexed-values"
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

  (it "argv-normalized-index-converts-fish-style-indices-to-zero-based"
    "argv-normalized-index converts 1-based and negative indices to 0-based offsets."
    (flet ((norm (index count)
             (nshell.domain.expansion::%argv-normalized-index index count)))
      (expect 0 :to-equal (norm 1 5))
      (expect 4 :to-equal (norm 5 5))
      (expect 4 :to-equal (norm -1 5))
      (expect 0 :to-equal (norm -5 5))
      (expect (norm 0 5) :to-be-null)
      (expect (norm nil 5) :to-be-null)))

  (it "list-index-field-selects-one-element-by-fish-index"
    "list-index-field returns the element at a 1-based fish-style index."
    (flet ((idx (fields index)
             (nshell.domain.expansion::%list-index-field fields index)))
      (expect '("b") :to-equal (idx '("a" "b" "c") 2))
      (expect '("c") :to-equal (idx '("a" "b" "c") -1))
      (expect (idx '("a" "b" "c") 5) :to-be-null)
      (expect (idx '("a" "b" "c") 0) :to-be-null)))

  (it "list-range-fields-selects-ordered-sublist"
    "list-range-fields selects ascending or descending sub-lists by fish-style indices."
    (flet ((range (fields start end)
             (nshell.domain.expansion::%list-range-fields fields start end)))
      (expect '("a" "b") :to-equal (range '("a" "b" "c") 1 2))
      (expect '("c" "b") :to-equal (range '("a" "b" "c") -1 2))
      (expect (range '("a" "b") 0 2) :to-be-null)))

  (property "pbt-argv-normalized-index-maps-one-based-and-negative"
      "For i in [1,count], a 1-based index normalizes to i-1 and -i to count-i."
      ((count (gen-in-range 1 12) #'shrink-integer)
       (raw (gen-in-range 1 12) #'shrink-integer))
      (let ((i (min raw count)))
        (and (= (1- i)
                (nshell.domain.expansion::%argv-normalized-index i count))
             (= (- count i)
                (nshell.domain.expansion::%argv-normalized-index (- i) count)))))

  (property "pbt-list-range-fields-reverses-under-swapped-bounds"
      "Swapping an ascending in-range range's bounds yields the reversed sub-list."
      ((count (gen-in-range 1 8) #'shrink-integer)
       (a (gen-in-range 1 8) #'shrink-integer)
       (b (gen-in-range 1 8) #'shrink-integer))
      (let* ((fields (loop for k from 1 to count collect (format nil "f~d" k)))
             (lo (min a b count))
             (hi (min (max a b) count)))
        (equal (nshell.domain.expansion::%list-range-fields fields hi lo)
               (reverse (nshell.domain.expansion::%list-range-fields fields lo hi)))))

  (it "join-fields-concatenates-with-spaces"
    "join-fields joins a list of strings with single spaces."
    (flet ((join (fields)
             (nshell.domain.expansion::%join-fields fields)))
      (expect "" :to-equal (join nil))
      (expect "a" :to-equal (join '("a")))
      (expect "a b c" :to-equal (join '("a" "b" "c")))))

  (it "append-list-reference-fields-cross-products-prefixes-and-fields"
    "append-list-reference-fields produces every prefix+field combination."
    (flet ((cross (prefixes fields)
             (nshell.domain.expansion::%append-list-reference-fields prefixes fields)))
      ;; single prefix, multiple fields
      (expect '("a-x" "a-y") :to-equal (cross '("a-") '("x" "y")))
      ;; multiple prefixes, single field
      (expect '("a-z" "b-z") :to-equal (cross '("a-" "b-") '("z")))
      ;; nil fields treated as ("") — empty field appended
      (expect '("a-" "b-") :to-equal (cross '("a-" "b-") nil))
      ;; multiple prefixes and fields: cartesian product in order
      (expect '("p-x" "p-y" "q-x" "q-y") :to-equal (cross '("p-" "q-") '("x" "y"))))))
