(in-package #:nshell/test)

(in-suite completion-rules-tests)

(defmethod nshell.domain.completion:predicate-true-p
    ((predicate (eql 'test-builtin-true)) args bindings)
  (declare (ignore predicate args bindings))
  t)

(defmethod nshell.domain.completion:predicate-true-p
    ((predicate (eql 'test-builtin-string=)) args bindings)
  (declare (ignore predicate bindings))
  (and (= 2 (length args))
       (string= (first args) (second args))))

(test fact-only-resolution
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'completes :args '("ls" "--help")))
    (is (= 1 (length (nshell.domain.completion:prove-all kb '(completes "ls" "--help")))))))

(test rule-knowledge-base-constructor-is-internal-boundary
  (is (not (fboundp 'nshell.domain.completion::make-rule-knowledge-base)))
  (is (fboundp 'nshell.domain.completion::%make-rule-knowledge-base))
  (is (nshell.domain.completion::rule-knowledge-base-p
       (nshell.domain.completion::make-empty-rule-knowledge-base))))

(test rule-with-one-body-goal-resolves
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'command-is :args '("cd" "cd")))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(suggests-dir ?input)
                                          :body '((command-is ?input "cd"))))
    (is (= 1 (length (nshell.domain.completion:prove-all kb '(suggests-dir "cd")))))))

(test rule-with-conjunction-resolves
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'command-is :args '("git" "git")))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'has-flag :args '("git" "--help")))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(documented-command ?cmd)
                                          :body '((command-is ?cmd "git")
                                                  (has-flag ?cmd "--help"))))
    (is (= 1 (length (nshell.domain.completion:prove-all kb '(documented-command "git")))))))

(test rule-disjunction-via-multiple-rules
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'git-subcommand :args '("add")))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'git-subcommand :args '("commit")))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion:make-rule :head '(completes "git" ?sub)
                                          :body '((git-subcommand ?sub))))
    (let ((solutions (nshell.domain.completion:prove-all kb '(completes "git" ?sub))))
      (is (= 2 (length solutions)))
      (is (member "add" (mapcar (lambda (solution) (solution-binding '?sub solution)) solutions)
                  :test #'string=))
      (is (member "commit" (mapcar (lambda (solution) (solution-binding '?sub solution)) solutions)
                  :test #'string=)))))

(test variable-binding-extraction
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'completes :args '("ls" "--help")))
    (let ((solutions (nshell.domain.completion:prove-all kb '(completes ?command "--help"))))
      (is (= 1 (length solutions)))
      (is (string= "ls" (solution-binding '?command (first solutions)))))))

(test first-solution-value-projects-rule-solution-boundary
  (let ((solutions (list (list (cons '?description "primary"))
                         (list (cons '?description "fallback")))))
    (let ((binding
            (nshell.domain.completion::project-rule-solution-binding
             '?description
             (first solutions)))
          (missing
            (nshell.domain.completion::project-rule-solution-binding
             '?missing
             (first solutions)))
          (solution-set
            (nshell.domain.completion::project-rule-solution-set solutions)))
      (is (string= "primary"
                   (nshell.domain.completion::rule-solution-binding-projection-value
                    binding)))
      (is (nshell.domain.completion::rule-solution-binding-projection-present-p
           binding))
      (is (not (nshell.domain.completion::rule-solution-binding-projection-present-p
                missing)))
      (is (equal (first solutions)
                 (nshell.domain.completion::rule-solution-set-projection-first-solution
                  solution-set)))
      (is (not (fboundp 'nshell.domain.completion::make-rule-solution-binding-projection)))
      (is (not (fboundp 'nshell.domain.completion::make-rule-solution-set-projection))))
    (is (string= "primary"
                 (nshell.domain.completion::first-solution-value
                  '?description solutions)))
    (is (null (nshell.domain.completion::first-solution-value
               '?description nil)))))

(test rule-data-projection-boundaries-name-domain-parts
  (let ((fact (nshell.domain.completion::make-fact-from-spec
               '(completes "git" "status")))
        (rule (nshell.domain.completion::make-rule-from-spec
               '((completes "git" ?completion) (git-subcommand ?completion))))
        (goal '(test-builtin-string= "git" "git")))
    (is (eq 'completes (nshell.domain.completion::fact-predicate fact)))
    (is (equal '("git" "status") (nshell.domain.completion::fact-args fact)))
    (is (equal '(completes "git" ?completion)
               (nshell.domain.completion::rule-head rule)))
    (is (equal '((git-subcommand ?completion))
               (nshell.domain.completion::rule-body rule)))
    (is (eq 'test-builtin-string=
            (nshell.domain.completion::goal-predicate goal)))
    (is (equal '("git" "git")
               (nshell.domain.completion::goal-arguments goal)))
    (is (not (fboundp 'nshell.domain.completion::make-proof-search)))))

(test logic-form-pair-projects-conversion-boundary
  (let* ((env (make-hash-table :test #'eq))
         (converted (nshell.domain.completion::convert-logic-variables
                     '(?value . ?value)
                     env))
         (head (nshell.domain.completion::logic-form-pair-head converted))
         (tail (nshell.domain.completion::logic-form-pair-tail converted)))
    (is (nshell.domain.parsing:var-p head))
    (is (eq head tail))))

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
