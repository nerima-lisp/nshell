(in-package #:nshell/test)

(in-suite completion-rules-tests)

(test rule-prover-helpers-are-internal-boundaries
  (is (fboundp 'nshell.domain.completion::%make-rule-from-spec))
  (is (not (fboundp 'nshell.domain.completion::make-proof-search))))

(test logic-variable-conversion-preserves-shared-bindings-through-prover
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'same :args '("git" "git")))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'same :args '("git" "status")))
    (let ((solutions (nshell.domain.completion:prove-all kb '(same ?value ?value))))
      (is (= 1 (length solutions)))
      (is (string= "git" (solution-binding '?value (first solutions)))))))

(test logic-variable-conversion-helpers-are-internal-boundaries
  (is (not (fboundp 'nshell.domain.completion::logic-variable-symbol-p)))
  (is (not (fboundp 'nshell.domain.completion::variable-name)))
  (is (not (fboundp 'nshell.domain.completion::logic-form-pair-head)))
  (is (not (fboundp 'nshell.domain.completion::logic-form-pair-tail)))
  (is (not (fboundp 'nshell.domain.completion::make-logic-form-pair)))
  (is (not (fboundp 'nshell.domain.completion::convert-logic-form-pair)))
  (is (not (fboundp 'nshell.domain.completion::convert-logic-variables)))
  (is (not (fboundp 'nshell.domain.completion::fact-head)))
  (is (not (fboundp 'nshell.domain.completion::rule-head-term)))
  (is (not (fboundp 'nshell.domain.completion::rule-body-terms)))
  (is (fboundp 'nshell.domain.completion::%logic-variable-symbol-p))
  (is (fboundp 'nshell.domain.completion::%logic-variable-name))
  (is (fboundp 'nshell.domain.completion::%logic-form-pair-head))
  (is (fboundp 'nshell.domain.completion::%logic-form-pair-tail))
  (is (fboundp 'nshell.domain.completion::%make-logic-form-pair))
  (is (fboundp 'nshell.domain.completion::%convert-logic-form-pair))
  (is (fboundp 'nshell.domain.completion::%convert-logic-variables))
  (is (fboundp 'nshell.domain.completion::%fact-head))
  (is (fboundp 'nshell.domain.completion::%rule-head-term))
  (is (fboundp 'nshell.domain.completion::%rule-body-terms)))

(test no-solution-for-unsatisfiable-goal
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'completes :args '("ls" "--help")))
    (is (null (nshell.domain.completion:prove-all kb '(completes "cat" "--help"))))))

(test builtin-predicate-succeeds-without-bindings
  (let ((solutions
          (nshell.domain.completion:prove-all
           (make-empty-rule-kb)
           '(test-builtin-true))))
    (is (= 1 (length solutions)))
    (is (null (first solutions)))))

(test builtin-predicate-participates-in-rule-body
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'command-is :args '("git" "git")))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(verified-command ?cmd)
                                          :body '((command-is ?cmd "git")
                                                  (test-builtin-string= ?cmd "git"))))
    (let ((solutions
            (nshell.domain.completion:prove-all kb '(verified-command ?cmd))))
      (is (= 1 (length solutions)))
      (is (string= "git" (solution-binding '?cmd (first solutions)))))))

(test builtin-predicate-solutions-are-combined-with-facts
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'test-builtin-true :args '()))
    (is (= 2 (length (nshell.domain.completion:prove-all kb '(test-builtin-true)))))))

(test occurs-check-prevents-infinite-loops
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'recursive :args '(?x (wrap ?x))))
    (is (null (nshell.domain.completion:prove-all kb '(recursive ?x ?x))))))

(test recursive-rule-search-is-depth-bounded
  "Recursive completion rules must not hang the interactive proof engine."
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(loops ?x)
                                          :body '((loops ?x))))
    (is (null (nshell.domain.completion:prove-all kb '(loops "git") :max-depth 4)))))

(test bounded-recursive-rule-keeps-finite-solutions
  "Depth limiting still allows useful transitive completion facts within the bound."
  (let ((kb (make-empty-rule-kb)))
    (dolist (edge '(("git" "status")
                    ("status" "--short")
                    ("--short" "format")))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'edge :args edge)))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(reachable ?from ?to)
                                          :body '((edge ?from ?to))))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(reachable ?from ?to)
                                          :body '((edge ?from ?mid)
                                                  (reachable ?mid ?to))))
    (let ((shallow (nshell.domain.completion:prove-all
                    kb '(reachable "git" ?target) :max-depth 1))
          (deep (nshell.domain.completion:prove-all
                 kb '(reachable "git" ?target) :max-depth 4)))
      (is (member "status" (mapcar (lambda (solution)
                                      (solution-binding '?target solution))
                                    shallow)
                  :test #'string=))
      (is (not (member "format" (mapcar (lambda (solution)
                                           (solution-binding '?target solution))
                                         shallow)
                       :test #'string=)))
      (is (member "format" (mapcar (lambda (solution)
                                       (solution-binding '?target solution))
                                     deep)
                   :test #'string=)))))

(test repeated-rule-expansion-uses-fresh-rule-variables
  "Each rule application gets its own logic-variable environment."
  (let ((kb (make-empty-rule-kb)))
    (dolist (edge '(("git" "commit")
                    ("commit" "--amend")))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'edge :args edge)))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(step ?from ?to)
                                          :body '((edge ?from ?to))))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(two-step ?from ?to)
                                          :body '((step ?from ?mid)
                                                  (step ?mid ?to))))
    (let ((solutions
            (nshell.domain.completion:prove-all kb '(two-step "git" ?target)
                                                :max-depth 4)))
      (is (= 1 (length solutions)))
      (is (string= "--amend" (solution-binding '?target (first solutions)))))))
