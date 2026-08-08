(in-package #:nshell/test)

(describe "job-control-integration-tests"
  (it "job-creation-assigns-unique-ids"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job1 (make-test-job 0 "sleep" :args '("1")))
           (job2 (make-test-job 1 "sleep" :args '("2")))
           (id1 (nshell.domain.job-control:monitor-add-job monitor job1))
           (id2 (nshell.domain.job-control:monitor-add-job monitor job2)))
      (expect (= id1 id2) :to-be-falsy)
      (expect 1 :to-equal id1)
      (expect 2 :to-equal id2)))

  (it "job-state-transitions-created-running-stopped-completed"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :args '("1")))
           (id (nshell.domain.job-control:monitor-add-job monitor job)))
      (expect :created :to-be (nshell.domain.execution:job-state job))
      (nshell.domain.job-control:monitor-update monitor id :running)
      (expect :running :to-be (nshell.domain.execution:job-state job))
      (nshell.domain.job-control:monitor-update monitor id :stopped)
      (expect :stopped :to-be (nshell.domain.execution:job-state job))
      (nshell.domain.job-control:monitor-update monitor id :completed 0)
      (expect :completed :to-be (nshell.domain.execution:job-state job))
      (expect 0 :to-equal (nshell.domain.execution:job-exit-code job))))

  (it "jobs-returns-current-job-list"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "echo" :args '("hello"))))
      (nshell.domain.job-control:monitor-add-job monitor job)
      (let ((returned (mapcar #'test-monitor-entry-job
                              (collect-monitor-entries monitor))))
        (expect 1 :to-equal (length returned))
        (expect (search "echo hello"
                    (nshell.domain.execution:job-command-line (first returned))) :to-be-truthy))))

  (it "reap-children-cleans-up-zombies"
    "Verify that process-wait properly cleans up child processes."
    (let ((proc (sb-ext:run-program "true" nil :wait nil :search t)))
      ;; Wait for the process via SBCL's process-wait
      (sb-ext:process-wait proc)
      (let ((pid (sb-ext:process-pid proc)))
        (expect (integerp pid) :to-be-truthy)
        (expect (sb-ext:process-alive-p proc) :to-be-falsy)))))

  (it "wait-job-flags-request-wcontinued-when-available"
    (let* ((wcontinued-symbol (find-symbol "WCONTINUED" "SB-POSIX"))
           (wcontinued (and wcontinued-symbol
                            (boundp wcontinued-symbol)
                            (symbol-value wcontinued-symbol))))
      (expect (logior sb-posix:wnohang
                      sb-posix:wuntraced
                      (or wcontinued 0))
              :to-equal
              (nshell.infrastructure.acl::%waitpid-flags
               :nohang t
               :untraced t
               :continued t))))
