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

(test pipeline-plan-preserves-stage-order
  (let* ((cmd1 (nshell.domain.execution:make-command "printf" '("foo")))
         (cmd2 (nshell.domain.execution:make-command "grep" '("f")))
         (pipe (nshell.domain.execution:make-pipeline cmd1 cmd2))
         (plan (nshell.domain.execution:make-pipeline-plan pipe))
         (stages (nshell.domain.execution:pipeline-plan-stages plan)))
    (is (not (fboundp 'nshell.domain.execution::make-pipe-config)))
    (is (not (fboundp 'nshell.domain.execution::make-pipeline-stage)))
    (is (fboundp 'nshell.domain.execution::%make-pipe-config))
    (is (fboundp 'nshell.domain.execution::%make-pipeline-stage))
    (is (= 2 (nshell.domain.execution:pipeline-stage-count plan)))
    (is (eq cmd1 (nshell.domain.execution:pipeline-stage-command (first stages))))
    (is (eq cmd2 (nshell.domain.execution:pipeline-stage-command (second stages))))
    (is (eq :pipe (nshell.domain.execution:pipe-config-stdout
                   (nshell.domain.execution:pipeline-stage-pipe-config (first stages)))))
    (is (eq :pipe (nshell.domain.execution:pipe-config-stdin
                   (nshell.domain.execution:pipeline-stage-pipe-config (second stages)))))))
