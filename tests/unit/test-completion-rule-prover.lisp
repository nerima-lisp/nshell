(in-package #:nshell/test)

(describe "completion-rules-tests"
  (it "rule-prover-helpers-are-internal-boundaries"
    (expect (fboundp 'nshell.domain.completion::%make-rule-from-spec) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::make-proof-search) :to-be-falsy))

  (it "logic-variable-conversion-preserves-shared-bindings-through-prover"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'same :args '("git" "git")))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'same :args '("git" "status")))
      (let ((solutions (nshell.domain.completion:prove-all kb '(same ?value ?value))))
        (expect 1 :to-equal (length solutions))
        (expect "git" :to-equal (solution-binding '?value (first solutions))))))

  (it "no-solution-for-unsatisfiable-goal"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'completes :args '("ls" "--help")))
      (expect (nshell.domain.completion:prove-all kb '(completes "cat" "--help")) :to-be-null)))

  (it "builtin-predicate-succeeds-without-bindings"
    (let ((solutions
            (nshell.domain.completion:prove-all
             (make-empty-rule-kb)
             '(test-builtin-true))))
      (expect 1 :to-equal (length solutions))
      (expect (first solutions) :to-be-null)))

  (it "builtin-predicate-participates-in-rule-body"
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
        (expect 1 :to-equal (length solutions))
        (expect "git" :to-equal (solution-binding '?cmd (first solutions))))))

  (it "builtin-predicate-solutions-are-combined-with-facts"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'test-builtin-true :args '()))
      (expect 2 :to-equal (length (nshell.domain.completion:prove-all kb '(test-builtin-true))))))

  (it "occurs-check-prevents-infinite-loops"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'recursive :args '(?x (wrap ?x))))
      (expect (nshell.domain.completion:prove-all kb '(recursive ?x ?x)) :to-be-null)))

  (it "recursive-rule-search-is-depth-bounded"
    "Recursive completion rules must not hang the interactive proof engine."
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-rule!
       kb
       (nshell.domain.completion:make-rule :head '(loops ?x)
                                            :body '((loops ?x))))
      (expect (nshell.domain.completion:prove-all kb '(loops "git") :max-depth 4) :to-be-null)))

  (it "bounded-recursive-rule-keeps-finite-solutions"
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
        (expect (member "status" (mapcar (lambda (solution)
                                        (solution-binding '?target solution))
                                      shallow)
                    :test #'string=) :to-be-truthy)
        (expect (member "format" (mapcar (lambda (solution)
                                             (solution-binding '?target solution))
                                           shallow)
                         :test #'string=) :to-be-falsy)
        (expect (member "format" (mapcar (lambda (solution)
                                         (solution-binding '?target solution))
                                       deep)
                     :test #'string=) :to-be-truthy))))

  (it "repeated-rule-expansion-uses-fresh-rule-variables"
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
        (expect 1 :to-equal (length solutions))
        (expect "--amend" :to-equal (solution-binding '?target (first solutions)))))))
