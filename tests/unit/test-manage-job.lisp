(in-package #:nshell/test)

(def-suite manage-job-service-tests
  :description "Application job-management service tests"
  :in nshell-tests)

(in-suite manage-job-service-tests)

(test jobs-prints-current-monitor-entries
  "JOBS formats the supplied monitor entries and returns them."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "echo" :args '("hello"))))
    (nshell.domain.job-control:monitor-add-job monitor job)
    (let ((nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
      (let ((output (capture-standard-output
                      (let ((entries (nshell.application:jobs monitor)))
                        (is (= 1 (length entries)))))))
        (is (search "[1]" output))
        (is (search "Created" output))
        (is (search "echo hello" output))))))

(test bg-marks-job-as-background-and-publishes-continuation
  "BG updates the job state without requiring terminal control when PGID is zero."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (dispatcher (nshell.application:make-event-dispatcher))
         (job (make-test-job 0 "sleep" :args '("10")))
         (job-id (nshell.domain.job-control:monitor-add-job monitor job))
         (nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
    (with-event-capture (continued dispatcher :job-continued)
        (nshell.domain.events:domain-event-type event)
      (is (eq job (nshell.application:bg job-id dispatcher monitor)))
      (is (eq :background (nshell.domain.execution:job-state job)))
      (is (nshell.domain.execution:job-background-p job))
      (is (null (nshell.application:drain-events dispatcher)))
      (is (equal '(:job-continued) (nreverse continued))))))

(test disown-removes-job-from-monitor
  "DISOWN removes a tracked job and returns true for an existing id."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "sleep" :args '("10")))
         (job-id (nshell.domain.job-control:monitor-add-job monitor job))
         (nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
    (is (nshell.application:disown job-id monitor))
    (is (null (nshell.domain.job-control:monitor-find-job monitor job-id)))))

(test missing-job-commands-return-nil-and-report
  "BG/FG report missing jobs instead of signaling application errors."
  (let ((empty-monitor (nshell.domain.job-control:make-job-monitor))
        (nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
    (let ((bg-output (with-output-to-string (*standard-output*)
                       (is (null (nshell.application:bg 42 nil empty-monitor)))))
          (fg-output (with-output-to-string (*standard-output*)
                       (is (null (nshell.application:fg 42 nil nil nil empty-monitor))))))
      (is (search "bg: no such job: 42" bg-output))
      (is (search "fg: no such job: 42" fg-output)))))

(test fg-clears-foreground-pgid-when-wait-fails
  "FG does not leave stale foreground process-group state after wait errors."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "sleep" :args '("10") :pgid 4321))
         (job-id (nshell.domain.job-control:monitor-add-job monitor job))
         (set-foreground-calls nil)
         (nshell.application:*shell-pgid* 1000)
         (nshell.application:*foreground-job-pgid* nil)
         (nshell.infrastructure.acl::*foreground-pgid* 0))
    (with-temporary-functions
        (('nshell.application::%continue-process-group
          (lambda (pgid)
            (is (= 4321 pgid))))
       ('nshell.application::%wait-job-pgid
        (lambda (waited-job)
          (is (eq job waited-job))
          (is (= 4321 nshell.application:*foreground-job-pgid*))
          (is (= 4321 nshell.infrastructure.acl::*foreground-pgid*))
          (error "wait failed")))
         ('nshell.infrastructure.acl:get-foreground-pgroup
          (lambda () 1000))
         ('nshell.infrastructure.acl:set-foreground-pgroup
          (lambda (pgid)
            (push pgid set-foreground-calls))))
      (handler-case
          (nshell.application:fg job-id nil nil nil monitor)
        (error (condition)
          (is (search "wait failed" (princ-to-string condition)))))
      (is (null nshell.application:*foreground-job-pgid*))
      (is (= 0 nshell.infrastructure.acl::*foreground-pgid*))
      (is (equal '(1000 4321) set-foreground-calls)))))

(test wait-job-pgid-waits-for-known-pipeline-pids
  "Foreground wait reaps every known pipeline PID and uses the last stage status."
  (let* ((job (make-test-job 0 "producer" :pgid 111))
         (events '((222 :exited 7)
                   (111 :exited 0)))
         (waited-pids nil))
    (setf (nshell.domain.execution:job-pids job) '(111 222))
    (with-temporary-function
        ('nshell.application::%wait-job-pgid-event
         (lambda (pgid)
           (is (= 111 pgid))
           (let ((event (pop events)))
             (unless event
               (error "unexpected extra wait"))
             (destructuring-bind (pid state status-code) event
               (push pid waited-pids)
               (values pid state status-code)))))
      (is (eq job (nshell.application::%wait-job-pgid job))))
    (is (null events))
    (is (equal '(222 111) (nreverse waited-pids)))
    (is (eq :completed (nshell.domain.execution:job-state job)))
    (is (= 7 (nshell.domain.execution:job-exit-code job)))))

(test wait-job-pgid-stops-on-stopped-event
  "Foreground wait preserves stopped jobs instead of completing a partially stopped pipeline."
  (let* ((job (make-test-job 0 "sleep" :pgid 111))
         (events '((111 :stopped nil)
                   (222 :exited 0))))
    (setf (nshell.domain.execution:job-pids job) '(111 222))
    (with-temporary-function
        ('nshell.application::%wait-job-pgid-event
         (lambda (pgid)
           (is (= 111 pgid))
           (let ((event (pop events)))
             (unless event
               (error "unexpected extra wait"))
             (destructuring-bind (pid state status-code) event
               (values pid state status-code)))))
      (is (eq job (nshell.application::%wait-job-pgid job))))
    (is (equal '((222 :exited 0)) events))
    (is (eq :stopped (nshell.domain.execution:job-state job)))
    (is (null (nshell.domain.execution:job-exit-code job)))))

(test foreground-signal-target-ignores-shell-process-group
  "Foreground signal forwarding never targets the shell's own process group."
  (let ((nshell.application:*shell-pgid* 1000)
        (nshell.application:*foreground-job-pgid* nil))
    (with-temporary-function
        ('nshell.infrastructure.acl:get-foreground-pgroup
         (lambda () 1000))
      (is (null (nshell.application::%foreground-signal-target-pgid)))))
  (let ((nshell.application:*shell-pgid* 1000)
        (nshell.application:*foreground-job-pgid* 1000))
    (with-temporary-function
        ('nshell.infrastructure.acl:get-foreground-pgroup
         (lambda () 2000))
      (is (null (nshell.application::%foreground-signal-target-pgid)))))
  (let ((nshell.application:*shell-pgid* 1000)
        (nshell.application:*foreground-job-pgid* nil))
    (with-temporary-function
        ('nshell.infrastructure.acl:get-foreground-pgroup
         (lambda () 2000))
      (is (= 2000 (nshell.application::%foreground-signal-target-pgid))))))
