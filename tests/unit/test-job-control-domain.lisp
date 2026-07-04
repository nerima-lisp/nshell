(in-package #:nshell/test)
(def-suite job-control-domain-tests :description "Job control domain tests" :in nshell-tests)
(in-suite job-control-domain-tests)

(test job-monitor-raw-constructor-is-internal-boundary
  (let ((monitor (nshell.domain.job-control:make-job-monitor)))
    (is (hash-table-p (nshell.domain.job-control::job-monitor-jobs monitor)))
    (is (= 1 (nshell.domain.job-control::job-monitor-next-id monitor)))
    (is (fboundp 'nshell.domain.job-control::%make-job-monitor))))

(test monitor-creates-jobs
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job 1 pipe))
     (id (nshell.domain.job-control:monitor-add-job monitor job)))
    (is (= 1 id))
    (is (nshell.domain.job-control:monitor-find-job monitor id))))

(test pbt-invalid-job-state-transitions-are-rejected
  "Generated invalid job states are rejected by the job state transition guard."
  (for-all ((state-number (gen-integer :min 0 :max 1000)))
    (let* ((cmd (nshell.domain.execution:make-command "ls"))
           (pipeline (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 1 pipeline))
           (invalid-state (intern (format nil "INVALID-~d" (abs state-number)) :keyword)))
      (is (not (nshell.domain.execution:job-state-valid-p invalid-state))
          "Generated state ~s unexpectedly became valid" invalid-state)
      (let ((rejected (handler-case
                          (progn
                            (nshell.domain.execution:job-state-transition job invalid-state)
                            nil)
                        (error () t))))
        (is-true rejected
                 "Invalid generated state ~s should be rejected" invalid-state)))))
