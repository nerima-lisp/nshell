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
  (assert-package-function-boundaries
      :package "NSHELL.DOMAIN.COMPLETION"
      :present (nshell.domain.completion::%make-rule-knowledge-base)
      :absent (nshell.domain.completion::make-rule-knowledge-base
               nshell.domain.completion::knowledge-base-commands))
  (is (nshell.domain.completion::rule-knowledge-base-p
       (nshell.domain.completion::make-empty-rule-knowledge-base))))

(test fact-and-rule-constructors-validate-domain-values
  (assert-package-function-boundaries
      :package "NSHELL.DOMAIN.COMPLETION"
      :present (nshell.domain.completion:make-fact
                nshell.domain.completion:make-rule
                nshell.domain.completion::%allocate-fact
                nshell.domain.completion::%allocate-rule)
      :absent (nshell.domain.completion::copy-fact
               nshell.domain.completion::copy-rule))
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
  (assert-package-function-boundaries
      :package "NSHELL.DOMAIN.COMPLETION"
      :present (nshell.domain.completion::%rule-solution-value
                nshell.domain.completion::%first-rule-solution-value
                nshell.domain.completion::%completion-description
                nshell.domain.completion::%candidates-from-rule-solutions)
      :absent (nshell.domain.completion::solution-value
               nshell.domain.completion::first-solution-value
               nshell.domain.completion::completion-description
               nshell.domain.completion::candidates-from-rule-solutions
               nshell.domain.completion::make-rule-solution-binding-projection
               nshell.domain.completion::make-rule-solution-set-projection
               nshell.domain.completion::project-rule-solution-binding
               nshell.domain.completion::project-rule-solution-set
               nshell.domain.completion::rule-solution-binding-projection-value
               nshell.domain.completion::rule-solution-binding-projection-present-p
               nshell.domain.completion::rule-solution-set-projection-first-solution
               nshell.domain.completion::%make-rule-solution-binding-projection
               nshell.domain.completion::%make-rule-solution-set-projection
               nshell.domain.completion::%project-rule-solution-binding
               nshell.domain.completion::%project-rule-solution-set
               nshell.domain.completion::%rule-solution-binding-projection-value
               nshell.domain.completion::%rule-solution-binding-projection-present-p
                nshell.domain.completion::%rule-solution-set-projection-first-solution)))

(test rule-data-spec-builders-feed-proof-search
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

(test rule-data-spec-builders-are-internal-boundaries
  (assert-package-function-boundaries
      :package "NSHELL.DOMAIN.COMPLETION"
      :present (nshell.domain.completion::%make-fact-from-spec
                nshell.domain.completion::%make-rule-from-spec)
      :absent (nshell.domain.completion::project-fact-spec
               nshell.domain.completion::project-rule-spec
               nshell.domain.completion::proof-goal-sequence-from-goals
               nshell.domain.completion::project-proof-goal
               nshell.domain.completion::fact-spec-predicate
               nshell.domain.completion::fact-spec-args
               nshell.domain.completion::rule-spec-head
               nshell.domain.completion::rule-spec-body
               nshell.domain.completion::next-proof-goal
               nshell.domain.completion::remaining-proof-goals
               nshell.domain.completion::goal-predicate
               nshell.domain.completion::goal-arguments
               nshell.domain.completion::make-fact-from-spec
               nshell.domain.completion::make-rule-from-spec
               nshell.domain.completion::make-proof-search)))

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
