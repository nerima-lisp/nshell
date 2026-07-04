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

(test parameter-operator-parts-classifies-colon-and-word
  "parameter-operator-parts projects a braced operator tail into a value object."
  (flet ((operator (rest)
           (nshell.domain.expansion::%parameter-operator-parts rest)))
    (let ((default (operator ":-fallback"))
          (alternate (operator "+yes"))
          (long-prefix (operator "##pat"))
          (empty (operator "")))
      (is (nshell.domain.expansion::parameter-operator-p default))
      (is (char= #\- (nshell.domain.expansion::parameter-operator-op default)))
      (is (string= "fallback"
                   (nshell.domain.expansion::parameter-operator-word-text default)))
      (is (nshell.domain.expansion::parameter-operator-colon-p default))
      (is (char= #\+ (nshell.domain.expansion::parameter-operator-op alternate)))
      (is (string= "yes"
                   (nshell.domain.expansion::parameter-operator-word-text alternate)))
      (is (not (nshell.domain.expansion::parameter-operator-colon-p alternate)))
      (is (char= #\# (nshell.domain.expansion::parameter-operator-op long-prefix)))
      (is (string= "#pat"
                   (nshell.domain.expansion::parameter-operator-word-text long-prefix)))
      (is (null (nshell.domain.expansion::parameter-operator-op empty)))
      (is (string= "" (nshell.domain.expansion::parameter-operator-word-text empty)))
      (is (not (nshell.domain.expansion::parameter-operator-colon-p empty))))))

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
      (is (nshell.domain.expansion::parameter-binding-p missing))
      (is (not (nshell.domain.expansion::parameter-binding-set-p missing)))
      (is (string= "" (nshell.domain.expansion::parameter-binding-value missing)))
      (is (nshell.domain.expansion::parameter-binding-set-p empty))
      (is (string= "" (nshell.domain.expansion::parameter-binding-value empty)))
      (is (string= "value" (nshell.domain.expansion::parameter-binding-value full)))
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
          (unknown (nshell.domain.expansion::%parameter-operator-parts ":!tail")))
      (flet ((apply-op (binding operator word rest)
               (nshell.domain.expansion::%apply-parameter-operator
                binding operator word rest env)))
        (is (string= "fallback" (apply-op missing default "fallback" ":-fallback")))
        (is (string= "value" (apply-op full default "fallback" ":-fallback")))
        (is (string= "" (apply-op missing alternate "alt" ":+alt")))
        (is (string= "alt" (apply-op full alternate "alt" ":+alt")))
        (is (string= "value:!tail" (apply-op full unknown "tail" ":!tail")))))))

(test parse-argv-index-parses-integer-or-returns-default
  "parse-argv-index returns the parsed integer, default for empty string, nil on failure."
  (flet ((parse (text &optional default)
           (nshell.domain.expansion::%parse-argv-index text default)))
    (is (= 3  (parse "3")))
    (is (= -1 (parse "-1")))
    (is (null (parse "abc")))
    (is (= 0  (parse "" 0)))
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
  (flet ((scan (input name-end)
           (multiple-value-list
            (nshell.domain.expansion::%bracket-spec-after-name
             input name-end (length input)))))
    (is (equal '("2..-1" 12 :indexed) (scan "$argv[2..-1]" 5)))
    (is (equal '(nil 5 :unbalanced) (scan "$argv[2" 5)))
    (is (equal '(nil) (scan "$argv" 5)))))

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
    (flet ((expand (input)
             (multiple-value-list
              (nshell.domain.expansion::%argv-expansion-after-name
               input 5 (length input)))))
      (is (equal '("alpha beta gamma" 5) (expand "$argv")))
      (is (equal '("beta" 8) (expand "$argv[2]"))))))

(test variable-expansion-after-name-resolves-scalar-and-indexed-values
  "variable-expansion-after-name owns scalar fallback vs indexed env expansion semantics."
  (let ((env (nshell.domain.environment:make-environment)))
    (setf env (nshell.domain.environment:env-set env "SCALAR" "plain" nil))
    (setf env (nshell.domain.environment:env-set-values
               env "WORDS" '("one" "two" "three") nil))
    (flet ((expand (input name name-end)
             (multiple-value-list
              (nshell.domain.expansion::%variable-expansion-after-name
               input name env name-end (length input)))))
      (is (equal '("plain" 7) (expand "$SCALAR" "SCALAR" 7)))
      (is (equal '("two" 9) (expand "$WORDS[2]" "WORDS" 6))))))

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
