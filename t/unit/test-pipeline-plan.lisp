(in-package #:nshell/test)
(describe "pipeline-plan-tests"
  (it "empty-pipeline-detected"
    (let ((pipe (nshell.domain.execution:make-pipeline)))
      (expect (nshell.domain.execution:pipeline-empty-p pipe) :to-be-truthy)))
  (it "single-command-pipeline"
    (let* ((cmd (nshell.domain.execution:make-command "ls"))
           (pipe (nshell.domain.execution:make-pipeline cmd)))
      (expect (nshell.domain.execution:pipeline-single-command-p pipe) :to-be-truthy)))

  (it "pipeline-command-list-is-domain-owned"
    (let* ((cmd1 (nshell.domain.execution:make-command "printf" '("foo")))
           (cmd2 (nshell.domain.execution:make-command "grep" '("f")))
           (pipe (nshell.domain.execution:make-pipeline cmd1 cmd2))
           (commands (nshell.domain.execution:pipeline-commands pipe)))
      (setf (car commands) :mutated)
      (expect (list cmd1 cmd2) :to-equal (nshell.domain.execution:pipeline-commands pipe))
      (expect 2 :to-equal (nshell.domain.execution:pipeline-length pipe))))

  (it "pipeline-plan-preserves-stage-order"
    (let* ((cmd1 (nshell.domain.execution:make-command "printf" '("foo")))
           (cmd2 (nshell.domain.execution:make-command "grep" '("f")))
           (pipe (nshell.domain.execution:make-pipeline cmd1 cmd2))
           (plan (nshell.domain.execution:make-pipeline-plan pipe)))
      (expect 2 :to-equal (nshell.domain.execution:pipeline-plan-stage-count plan))
      (expect (list cmd1 cmd2) :to-equal (nshell.domain.execution:pipeline-plan-commands plan))
      (expect (nshell.domain.execution:pipeline-plan-stage-piped-input-p plan 0) :to-be-falsy)
      (expect (nshell.domain.execution:pipeline-plan-stage-piped-output-p plan 0) :to-be-truthy)
      (expect (nshell.domain.execution:pipeline-plan-stage-piped-input-p plan 1) :to-be-truthy)
      (expect (nshell.domain.execution:pipeline-plan-stage-piped-output-p plan 1) :to-be-falsy)))

  (it "pipeline-plan-command-list-is-domain-owned"
    (let* ((cmd1 (nshell.domain.execution:make-command "printf" '("foo")))
           (cmd2 (nshell.domain.execution:make-command "grep" '("f")))
           (plan (nshell.domain.execution:make-pipeline-plan
                  (nshell.domain.execution:make-pipeline cmd1 cmd2)))
           (commands (nshell.domain.execution:pipeline-plan-commands plan)))
      (setf (car commands) :mutated)
      (expect (list cmd1 cmd2) :to-equal (nshell.domain.execution:pipeline-plan-commands plan))))

  (it "pipeline-plan-rejects-invalid-stage-indexes"
    (let* ((cmd (nshell.domain.execution:make-command "printf" '("foo")))
           (plan (nshell.domain.execution:make-pipeline-plan
                  (nshell.domain.execution:make-pipeline cmd))))
      (dolist (index '(-1 1 :first))
        (expect (lambda () (nshell.domain.execution:pipeline-plan-stage-piped-input-p plan index)) :to-throw 'error)
        (expect (lambda () (nshell.domain.execution:pipeline-plan-stage-piped-output-p plan index)) :to-throw 'error)))))
