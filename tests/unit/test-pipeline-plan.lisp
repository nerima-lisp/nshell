(in-package #:nshell/test)
(def-suite pipeline-plan-tests :description "Pipeline plan tests" :in nshell-tests)
(in-suite pipeline-plan-tests)
(test empty-pipeline-detected
  (let ((pipe (nshell.domain.execution:make-pipeline)))
    (is (nshell.domain.execution:pipeline-empty-p pipe))))
(test single-command-pipeline
  (let* ((cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd)))
    (is (nshell.domain.execution:pipeline-single-command-p pipe))))

(test pipeline-command-list-is-domain-owned
  (let* ((cmd1 (nshell.domain.execution:make-command "printf" '("foo")))
         (cmd2 (nshell.domain.execution:make-command "grep" '("f")))
         (pipe (nshell.domain.execution:make-pipeline cmd1 cmd2))
         (commands (nshell.domain.execution:pipeline-commands pipe)))
    (setf (car commands) :mutated)
    (is (equal (list cmd1 cmd2)
               (nshell.domain.execution:pipeline-commands pipe)))
    (is (= 2 (nshell.domain.execution:pipeline-length pipe)))))

(test pipeline-plan-preserves-stage-order
  (let* ((cmd1 (nshell.domain.execution:make-command "printf" '("foo")))
         (cmd2 (nshell.domain.execution:make-command "grep" '("f")))
         (pipe (nshell.domain.execution:make-pipeline cmd1 cmd2))
         (plan (nshell.domain.execution:make-pipeline-plan pipe)))
    (is (= 2 (nshell.domain.execution:pipeline-plan-stage-count plan)))
    (is (equal (list cmd1 cmd2)
               (nshell.domain.execution:pipeline-plan-commands plan)))
    (is (not (nshell.domain.execution:pipeline-plan-stage-piped-input-p plan 0)))
    (is (nshell.domain.execution:pipeline-plan-stage-piped-output-p plan 0))
    (is (nshell.domain.execution:pipeline-plan-stage-piped-input-p plan 1))
    (is (not (nshell.domain.execution:pipeline-plan-stage-piped-output-p plan 1)))))

(test pipeline-plan-command-list-is-domain-owned
  (let* ((cmd1 (nshell.domain.execution:make-command "printf" '("foo")))
         (cmd2 (nshell.domain.execution:make-command "grep" '("f")))
         (plan (nshell.domain.execution:make-pipeline-plan
                (nshell.domain.execution:make-pipeline cmd1 cmd2)))
         (commands (nshell.domain.execution:pipeline-plan-commands plan)))
    (setf (car commands) :mutated)
    (is (equal (list cmd1 cmd2)
               (nshell.domain.execution:pipeline-plan-commands plan)))))

(test pipeline-plan-rejects-invalid-stage-indexes
  (let* ((cmd (nshell.domain.execution:make-command "printf" '("foo")))
         (plan (nshell.domain.execution:make-pipeline-plan
                (nshell.domain.execution:make-pipeline cmd))))
    (dolist (index '(-1 1 :first))
      (signals error
        (nshell.domain.execution:pipeline-plan-stage-piped-input-p plan index))
      (signals error
        (nshell.domain.execution:pipeline-plan-stage-piped-output-p plan index)))))
