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

(test fact-and-rule-constructors-validate-domain-values
  (is (fboundp 'nshell.domain.completion:make-fact))
  (is (fboundp 'nshell.domain.completion:make-rule))
  (is (fboundp 'nshell.domain.completion::%allocate-fact))
  (is (fboundp 'nshell.domain.completion::%allocate-rule))
  (is (not (fboundp 'nshell.domain.completion::copy-fact)))
  (is (not (fboundp 'nshell.domain.completion::copy-rule)))
  (signals type-error
    (nshell.domain.completion:make-fact :predicate "completes"
                                        :args '("ls" "--help")))
  (signals type-error
    (nshell.domain.completion:make-fact :predicate 'completes
                                        :args "ls"))
  (signals type-error
    (nshell.domain.completion:make-rule :head "bad"
                                        :body '()))
  (signals type-error
    (nshell.domain.completion:make-rule :head '(suggests-dir ?input)
                                        :body "bad"))
  (let* ((args (list "ls" "--help"))
         (head (list 'suggests-dir '?input))
         (body (list '(command-is ?input "cd")))
         (fact (nshell.domain.completion:make-fact :predicate 'completes
                                                   :args args))
         (rule (nshell.domain.completion:make-rule :head head
                                                   :body body)))
    (setf (first args) "git")
    (setf (first head) 'changed)
    (setf (first body) '(changed ?input))
    (is (equal '("ls" "--help")
               (nshell.domain.completion::fact-args fact)))
    (is (equal '(suggests-dir ?input)
               (nshell.domain.completion::rule-head rule)))
    (is (equal '((command-is ?input "cd"))
               (nshell.domain.completion::rule-body rule)))))

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

(test rule-completion-projects-solution-values-through-candidates
  (let ((kb (make-empty-rule-kb)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::completes
                                         :args '("git" "status")))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::describes
                                         :args '("git" "version control")))
    (let ((candidates (nshell.domain.completion:rule-complete kb "gi")))
      (is (= 1 (length candidates)))
      (is (string= "git" (nshell.domain.completion:candidate-text (first candidates))))
      (is (string= "version control"
                   (nshell.domain.completion:candidate-description (first candidates)))))))

(test rule-solution-projections-are-internal-boundaries
  (is (not (fboundp 'nshell.domain.completion::solution-value)))
  (is (not (fboundp 'nshell.domain.completion::first-solution-value)))
  (is (not (fboundp 'nshell.domain.completion::completion-description)))
  (is (not (fboundp 'nshell.domain.completion::candidates-from-rule-solutions)))
  (is (fboundp 'nshell.domain.completion::%rule-solution-value))
  (is (fboundp 'nshell.domain.completion::%first-rule-solution-value))
  (is (fboundp 'nshell.domain.completion::%completion-description))
  (is (fboundp 'nshell.domain.completion::%candidates-from-rule-solutions))
  (is (not (fboundp 'nshell.domain.completion::make-rule-solution-binding-projection)))
  (is (not (fboundp 'nshell.domain.completion::make-rule-solution-set-projection)))
  (is (not (fboundp 'nshell.domain.completion::project-rule-solution-binding)))
  (is (not (fboundp 'nshell.domain.completion::project-rule-solution-set)))
  (is (not (fboundp 'nshell.domain.completion::rule-solution-binding-projection-value)))
  (is (not (fboundp 'nshell.domain.completion::rule-solution-binding-projection-present-p)))
  (is (not (fboundp 'nshell.domain.completion::rule-solution-set-projection-first-solution)))
  (is (not (fboundp 'nshell.domain.completion::%make-rule-solution-binding-projection)))
  (is (not (fboundp 'nshell.domain.completion::%make-rule-solution-set-projection)))
  (is (not (fboundp 'nshell.domain.completion::%project-rule-solution-binding)))
  (is (not (fboundp 'nshell.domain.completion::%project-rule-solution-set)))
  (is (not (fboundp 'nshell.domain.completion::%rule-solution-binding-projection-value)))
  (is (not (fboundp 'nshell.domain.completion::%rule-solution-binding-projection-present-p)))
  (is (not (fboundp 'nshell.domain.completion::%rule-solution-set-projection-first-solution))))

(test rule-data-spec-projections-feed-proof-search
  (let ((kb (nshell.domain.completion::make-empty-rule-knowledge-base)))
    (nshell.domain.completion:assert-fact!
     kb
     (nshell.domain.completion::%make-fact-from-spec
      '(git-subcommand "status")))
    (nshell.domain.completion:assert-rule!
     kb
     (nshell.domain.completion::%make-rule-from-spec
      '((completes "git" ?completion) (git-subcommand ?completion))))
    (let ((solutions (nshell.domain.completion:prove-all
                      kb
                      '(completes "git" ?completion))))
      (is (= 1 (length solutions)))
      (is (string= "status"
                   (solution-binding '?completion (first solutions)))))))

(test rule-data-projections-name-specs-and-proof-goals
  (let ((fact (nshell.domain.completion::%project-fact-spec
               '(git-subcommand "status")))
        (rule (nshell.domain.completion::%project-rule-spec
               '((completes "git" ?completion)
                 (git-subcommand ?completion))))
        (goals (nshell.domain.completion::%proof-goal-sequence-from-goals
                '((git-subcommand "status") (git-option "--help"))))
        (goal (nshell.domain.completion::%project-proof-goal
               '(git-subcommand "status"))))
    (is (eq 'git-subcommand
            (nshell.domain.completion::%fact-spec-projection-predicate fact)))
    (is (equal '("status")
               (nshell.domain.completion::%fact-spec-projection-args fact)))
    (is (equal '(completes "git" ?completion)
               (nshell.domain.completion::%rule-spec-projection-head rule)))
    (is (equal '((git-subcommand ?completion))
               (nshell.domain.completion::%rule-spec-projection-body rule)))
    (is (equal '(git-subcommand "status")
               (nshell.domain.completion::%proof-goal-sequence-next-goal goals)))
    (is (equal '((git-option "--help"))
               (nshell.domain.completion::%proof-goal-sequence-remaining-goals
                goals)))
    (is (eq 'git-subcommand
            (nshell.domain.completion::%proof-goal-projection-predicate goal)))
    (is (equal '("status")
               (nshell.domain.completion::%proof-goal-projection-arguments
                goal)))))

(test rule-data-spec-builders-are-internal-boundaries
  (is (not (fboundp 'nshell.domain.completion::fact-spec-predicate)))
  (is (not (fboundp 'nshell.domain.completion::fact-spec-args)))
  (is (not (fboundp 'nshell.domain.completion::rule-spec-head)))
  (is (not (fboundp 'nshell.domain.completion::rule-spec-body)))
  (is (not (fboundp 'nshell.domain.completion::next-proof-goal)))
  (is (not (fboundp 'nshell.domain.completion::remaining-proof-goals)))
  (is (not (fboundp 'nshell.domain.completion::goal-predicate)))
  (is (not (fboundp 'nshell.domain.completion::goal-arguments)))
  (is (fboundp 'nshell.domain.completion::%project-fact-spec))
  (is (fboundp 'nshell.domain.completion::%project-rule-spec))
  (is (fboundp 'nshell.domain.completion::%proof-goal-sequence-from-goals))
  (is (fboundp 'nshell.domain.completion::%project-proof-goal))
  (is (not (fboundp 'nshell.domain.completion::make-fact-from-spec)))
  (is (not (fboundp 'nshell.domain.completion::make-rule-from-spec)))
  (is (fboundp 'nshell.domain.completion::%make-fact-from-spec))
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
