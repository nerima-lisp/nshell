(in-package #:nshell/test)

;;;; Mutation tests exercise cl-weave's most advanced facility: instead of asking
;;;; "did a test run this code?" (coverage), they ask "would a test have *caught*
;;;; a bug here?".  `run-mutations' rewrites each arithmetic/comparison/boolean/
;;;; conditional site in a form and re-checks it against an oracle; a mutant that
;;;; still passes the oracle "survived" (the oracle is too weak), one that fails
;;;; is "killed".  These forms mirror real nshell logic -- glob character ranges,
;;;; string-prefix bounds, arithmetic precedence -- and their oracles kill every
;;;; mutation, so `assert-mutation-score' demands a perfect 1.0.

(defmacro assert-oracle-kills-mutations (form (&rest lambda-list) &body oracle-body)
  "Mutate FORM and assert every mutant is killed by ORACLE-BODY, which receives
the mutant compiled as a function bound over LAMBDA-LIST and must return true
only when the mutant is indistinguishable from the original."
  `(assert-mutation-score
    (run-mutations ,form
                   (lambda (mutant-form mutation)
                     (declare (ignore mutation))
                     (let ((,(first lambda-list) (eval mutant-form)))
                       (declare (ignorable ,(first lambda-list)))
                       ,@oracle-body)))
    1.0))

(describe "mutation-tests"
  (it "glob character-range membership kills every mutation"
    "lo <= ch <= hi -- the core of bracket [a-z] matching."
    (assert-oracle-kills-mutations
        '(lambda (lo hi ch) (and (<= lo ch) (<= ch hi)))
        (in-range)
      (and (funcall in-range 97 122 100)       ; 'd' within a-z
           (funcall in-range 97 122 97)        ; boundary lo
           (funcall in-range 97 122 122)       ; boundary hi
           (not (funcall in-range 97 122 96))  ; just below
           (not (funcall in-range 97 122 123))))) ; just above

  (it "string-prefix length bound kills every mutation"
    "A prefix can only match when it is no longer than the string."
    (assert-oracle-kills-mutations
        '(lambda (prefix string) (<= (length prefix) (length string)))
        (fits)
      (and (funcall fits "ab" "abc")
           (funcall fits "abc" "abc")
           (not (funcall fits "abcd" "abc")))))

  (it "arithmetic precedence kills every mutation"
    "a + b * c -- multiplication binds tighter than addition."
    (assert-oracle-kills-mutations
        '(lambda (a b c) (+ a (* b c)))
        (eval-expr)
      (and (= 7 (funcall eval-expr 1 2 3))
           (= 14 (funcall eval-expr 2 3 4))
           (= 25 (funcall eval-expr 5 4 5))))))
