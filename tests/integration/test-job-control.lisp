(in-package #:nshell/test)

(def-suite job-control-integration-tests
  :description "Job control integration tests"
  :in nshell-tests)

(in-suite job-control-integration-tests)

(test job-creation-assigns-unique-ids
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job1 (make-test-job 0 "sleep" :args '("1")))
         (job2 (make-test-job 1 "sleep" :args '("2")))
         (id1 (nshell.domain.job-control:monitor-add-job monitor job1))
         (id2 (nshell.domain.job-control:monitor-add-job monitor job2)))
    (is (not (= id1 id2)))
    (is (= 1 id1))
    (is (= 2 id2))))

(test job-state-transitions-created-running-stopped-completed
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "sleep" :args '("1")))
         (id (nshell.domain.job-control:monitor-add-job monitor job)))
    (is (eq :created (nshell.domain.execution:job-state job)))
    (nshell.domain.job-control:monitor-update monitor id :running)
    (is (eq :running (nshell.domain.execution:job-state job)))
    (nshell.domain.job-control:monitor-update monitor id :stopped)
    (is (eq :stopped (nshell.domain.execution:job-state job)))
    (nshell.domain.job-control:monitor-update monitor id :completed 0)
    (is (eq :completed (nshell.domain.execution:job-state job)))
    (is (= 0 (nshell.domain.execution:job-exit-code job)))))

(test jobs-returns-current-job-list
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "echo" :args '("hello"))))
    (nshell.domain.job-control:monitor-add-job monitor job)
    (let ((returned (mapcar #'cdr (collect-monitor-entries monitor))))
      (is (= 1 (length returned)))
      (is (search "echo hello"
                  (nshell.domain.execution:job-command-line (first returned)))))))

(test reap-children-cleans-up-zombies
  "Verify that process-wait properly cleans up child processes."
  (let ((proc (sb-ext:run-program "true" nil :wait nil :search t)))
    ;; Wait for the process via SBCL's process-wait
    (sb-ext:process-wait proc)
    (let ((pid (sb-ext:process-pid proc)))
      (is (integerp pid))
      (is (not (sb-ext:process-alive-p proc))
          "Process should be dead after process-wait"))))
