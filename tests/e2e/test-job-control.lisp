(in-package #:nshell/test)
(describe "e2e-job-tests"
  (it "e2e-job-monitor-lifecycle"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (cmd (nshell.domain.execution:make-command "sleep" '("1")))
           (pipe (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 1 pipe)))
      (declare (ignore monitor job))
      (expect (nshell.domain.execution:job-state-valid-p :running) :to-be-truthy)
      (expect (nshell.domain.execution:job-state-valid-p :stopped) :to-be-truthy))))
