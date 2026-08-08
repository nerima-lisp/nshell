(in-package #:nshell/test)

(cl-prolog:define-foreign-predicate (test-builtin-true)
    (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (funcall emit environment))

(cl-prolog:define-foreign-predicate (test-builtin-string= a b)
    (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (when (and (stringp a) (stringp b) (string= a b))
    (funcall emit environment)))

(describe "completion-rules-tests"
  (it "foreign-predicate-resolves-as-top-level-goal"
    (let ((kb (make-empty-rule-kb)))
      (expect 1 :to-equal (length (nshell.domain.completion:prove-all kb '(test-builtin-true))))
      (expect 1 :to-equal (length (nshell.domain.completion:prove-all kb '(test-builtin-string= "a" "a"))))
      (expect 0 :to-equal (length (nshell.domain.completion:prove-all kb '(test-builtin-string= "a" "b"))))))

  (it "foreign-predicate-resolves-as-rule-body-subgoal"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'command-is :args '("cd" "cd")))
      (nshell.domain.completion:assert-rule!
       kb
       (nshell.domain.completion:make-rule :head '(suggests-dir ?input)
                                            :body '((command-is ?input "cd") (test-builtin-true))))
      (expect 1 :to-equal (length (nshell.domain.completion:prove-all kb '(suggests-dir "cd"))))))

  (it "fact-only-resolution"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate
          'completes
          :args
          '("ls" "--help")))
      (expect
        1
        :to-equal
        (length (nshell.domain.completion:prove-all kb '(completes "ls" "--help"))))))
  (it
    "rule-knowledge-base-constructor-is-internal-boundary"
    (assert-package-function-boundaries
      :package
      "NSHELL.DOMAIN.COMPLETION"
      :present
      (nshell.domain.completion::%make-rule-knowledge-base)
      :absent
      (nshell.domain.completion::make-rule-knowledge-base
        nshell.domain.completion::knowledge-base-commands))
    (expect
      (nshell.domain.completion::rule-knowledge-base-p
        (nshell.domain.completion::make-empty-rule-knowledge-base))
      :to-be-truthy))
  (it
    "fact-and-rule-constructors-validate-domain-values"
    (assert-package-function-boundaries
      :package
      "NSHELL.DOMAIN.COMPLETION"
      :present
      (nshell.domain.completion:make-fact
        nshell.domain.completion:make-rule
        nshell.domain.completion::%allocate-fact
        nshell.domain.completion::%allocate-rule)
      :absent
      (nshell.domain.completion::copy-fact nshell.domain.completion::copy-rule))
    (expect
      (lambda ()
        (nshell.domain.completion:make-fact
          :predicate
          "completes"
          :args
          '("ls" "--help")))
      :to-throw
      'type-error)
    (expect
      (lambda ()
        (nshell.domain.completion:make-fact :predicate 'completes :args "ls"))
      :to-throw
      'type-error)
    (expect
      (lambda ()
        (nshell.domain.completion:make-rule :head "bad" :body '()))
      :to-throw
      'type-error)
    (expect
      (lambda ()
        (nshell.domain.completion:make-rule :head '(suggests-dir ?input) :body "bad"))
      :to-throw
      'type-error)
    (let* ((args (list "ls" "--help"))
           (head (list 'suggests-dir '?input))
           (body (list '(command-is ?input "cd")))
           (fact (nshell.domain.completion:make-fact :predicate 'completes :args args))
           (rule (nshell.domain.completion:make-rule :head head :body body)))
      (setf (first args) "git")
      (setf (first head) 'changed)
      (setf (first body) '(changed ?input))
      (expect '("ls" "--help") :to-equal (nshell.domain.completion::fact-args fact))
      (expect
        '(suggests-dir ?input)
        :to-equal
        (nshell.domain.completion::rule-head rule))
      (expect
        '((command-is ?input "cd"))
        :to-equal
        (nshell.domain.completion::rule-body rule))))
  (it
    "rule-with-one-body-goal-resolves"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact :predicate 'command-is :args '("cd" "cd")))
      (nshell.domain.completion:assert-rule!
        kb
        (nshell.domain.completion:make-rule
          :head
          '(suggests-dir ?input)
          :body
          '((command-is ?input "cd"))))
      (expect
        1
        :to-equal
        (length (nshell.domain.completion:prove-all kb '(suggests-dir "cd"))))))
  (it
    "rule-with-conjunction-resolves"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact :predicate 'command-is :args '("git" "git")))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate
          'has-flag
          :args
          '("git" "--help")))
      (nshell.domain.completion:assert-rule!
        kb
        (nshell.domain.completion:make-rule
          :head
          '(documented-command ?cmd)
          :body
          '((command-is ?cmd "git") (has-flag ?cmd "--help"))))
      (expect
        1
        :to-equal
        (length (nshell.domain.completion:prove-all kb '(documented-command "git"))))))
  (it
    "rule-disjunction-via-multiple-rules"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact :predicate 'git-subcommand :args '("add")))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate
          'git-subcommand
          :args
          '("commit")))
      (nshell.domain.completion:assert-rule!
        kb
        (nshell.domain.completion:make-rule
          :head
          '(completes "git" ?sub)
          :body
          '((git-subcommand ?sub))))
      (let ((solutions (nshell.domain.completion:prove-all kb '(completes "git" ?sub))))
        (expect 2 :to-equal (length solutions))
        (expect
          (member
            "add"
            (mapcar
              (lambda (solution)
                (solution-binding '?sub solution))
              solutions)
            :test
            #'string=)
          :to-be-truthy)
        (expect
          (member
            "commit"
            (mapcar
              (lambda (solution)
                (solution-binding '?sub solution))
              solutions)
            :test
            #'string=)
          :to-be-truthy))))
  (it
    "variable-binding-extraction"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate
          'completes
          :args
          '("ls" "--help")))
      (let ((solutions
            (nshell.domain.completion:prove-all kb '(completes ?command "--help"))))
        (expect 1 :to-equal (length solutions))
        (expect "ls" :to-equal (solution-binding '?command (first solutions))))))
  (it
    "rule-solution-projections-are-internal-boundaries"
    (assert-package-function-boundaries
      :package
      "NSHELL.DOMAIN.COMPLETION"
      :present
      (nshell.domain.completion::%rule-solution-value
        nshell.domain.completion::%completion-descriptions
        nshell.domain.completion::%candidates-from-rule-solutions)
      :absent
      (nshell.domain.completion::solution-value
        nshell.domain.completion::first-solution-value
        nshell.domain.completion::completion-description
        nshell.domain.completion::%first-rule-solution-value
        nshell.domain.completion::%completion-description
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
  (it
    "compiled rulebase is reused until the knowledge base changes"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate
          'completes
          :args
          '("git" "status")))
      (let ((initial (nshell.domain.completion:completion-rulebase kb)))
        (expect
          (eq initial (nshell.domain.completion:completion-rulebase kb))
          :to-be-truthy)
        (expect
          1
          :to-equal
          (length
            (nshell.domain.completion::%prove-rulebase
              initial
              '(completes ?command "status"))))
        (nshell.domain.completion:assert-fact!
          kb
          (nshell.domain.completion:make-fact
            :predicate
            'completes
            :args
            '("git" "branch")))
        (let ((after-fact (nshell.domain.completion:completion-rulebase kb)))
          (expect (not (eq initial after-fact)) :to-be-truthy)
          (expect
            (eq after-fact (nshell.domain.completion:completion-rulebase kb))
            :to-be-truthy)
          (expect
            2
            :to-equal
            (length
              (nshell.domain.completion::%prove-rulebase
                after-fact
                '(completes "git" ?completion))))
          (nshell.domain.completion:assert-rule!
            kb
            (nshell.domain.completion:make-rule
              :head
              '(documented ?command ?completion)
              :body
              '((completes ?command ?completion))))
          (let ((after-rule (nshell.domain.completion:completion-rulebase kb)))
            (expect (not (eq after-fact after-rule)) :to-be-truthy)
            (expect
              (eq after-rule (nshell.domain.completion:completion-rulebase kb))
              :to-be-truthy)
            (expect
              2
              :to-equal
              (length
                (nshell.domain.completion::%prove-rulebase
                  after-rule
                  '(documented "git" ?completion)))))))))
  (it
    "rule-data-spec-builders-are-internal-boundaries"
    (assert-package-function-boundaries
      :package
      "NSHELL.DOMAIN.COMPLETION"
      :present
      (nshell.domain.completion::%make-fact-from-spec
        nshell.domain.completion::%make-rule-from-spec)
      :absent
      (nshell.domain.completion::project-fact-spec
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
        nshell.domain.completion::make-proof-search))))
