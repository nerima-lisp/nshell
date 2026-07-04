(in-package #:nshell/test)

(def-suite manage-job-service-tests
  :description "Application job-management service tests"
  :in nshell-tests)

(in-suite manage-job-service-tests)

(test jobs-returns-current-job-listings
  "JOBS returns structured listings without writing to standard output."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "echo" :args '("hello"))))
    (nshell.domain.job-control:monitor-add-job monitor job)
    (let ((nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
      (let (listings)
        (let ((output (capture-standard-output
                        (setf listings (nshell.application:jobs monitor)))))
          (is (string= "" output)))
        (is (= 1 (length listings)))
        (let ((listing (first listings)))
          (is (nshell.application:job-listing-p listing))
          (is (= 1 (nshell.application:job-listing-id listing)))
          (is (string= "Created"
                       (nshell.application:job-listing-status listing)))
          (is (string= "echo hello"
                       (nshell.application:job-listing-command listing)))
          (is (string= (format nil "[1] Created echo hello~%")
                       (nshell.application:format-job-listing listing))))))))

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

(test missing-job-commands-return-nil-without-output
  "BG/FG return NIL for missing jobs without rendering user-facing errors."
  (let ((empty-monitor (nshell.domain.job-control:make-job-monitor))
        (nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
    (let (bg-result
          fg-result)
      (let ((bg-output (with-output-to-string (*standard-output*)
                         (setf bg-result (nshell.application:bg 42 nil empty-monitor))))
            (fg-output (with-output-to-string (*standard-output*)
                         (setf fg-result
                               (nshell.application:fg 42 nil nil nil empty-monitor)))))
        (is (null bg-result))
        (is (null fg-result))
        (is (string= "" bg-output))
        (is (string= "" fg-output))))))

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
        (lambda (waited-job waited-job-id waited-monitor)
          (is (eq job waited-job))
          (is (= job-id waited-job-id))
          (is (eq monitor waited-monitor))
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
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "producer" :pgid 111 :pids '(111 222)))
         (job-id (nshell.domain.job-control:monitor-add-job monitor job))
         (events '((222 :exited 7)
                   (111 :exited 0)))
         (waited-pids nil))
    (with-temporary-function
        ('nshell.application::%wait-job-pgid-event
         (lambda (pgid)
           (is (= 111 pgid))
           (let ((event (pop events)))
             (unless event
               (error "unexpected extra wait"))
             (destructuring-bind (pid state status-code) event
               (push pid waited-pids)
               (nshell.application::%make-job-wait-event pid state status-code)))))
      (is (eq job (nshell.application::%wait-job-pgid job job-id monitor))))
    (is (null events))
    (is (equal '(222 111) (nreverse waited-pids)))
    (is (eq :completed (nshell.domain.execution:job-state job)))
    (is (= 7 (nshell.domain.execution:job-exit-code job)))))

(test wait-job-pgid-stops-on-stopped-event
  "Foreground wait preserves stopped jobs instead of completing a partially stopped pipeline."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "sleep" :pgid 111 :pids '(111 222)))
         (job-id (nshell.domain.job-control:monitor-add-job monitor job))
         (events '((111 :stopped nil)
                   (222 :exited 0))))
    (with-temporary-function
        ('nshell.application::%wait-job-pgid-event
         (lambda (pgid)
           (is (= 111 pgid))
           (let ((event (pop events)))
             (unless event
               (error "unexpected extra wait"))
             (destructuring-bind (pid state status-code) event
               (nshell.application::%make-job-wait-event pid state status-code)))))
      (is (eq job (nshell.application::%wait-job-pgid job job-id monitor))))
    (is (equal '((222 :exited 0)) events))
    (is (eq :stopped (nshell.domain.execution:job-state job)))
    (is (null (nshell.domain.execution:job-exit-code job)))))

(test wait-job-event-shape-is-internal-boundary
  "Foreground wait events are internal application values, not exported API."
  (dolist (name '("JOB-WAIT-EVENT" "%MAKE-JOB-WAIT-EVENT"
                  "JOB-WAIT-EVENT-PID" "JOB-WAIT-EVENT-STATE"
                  "JOB-WAIT-EVENT-STATUS-CODE"))
    (multiple-value-bind (_symbol status)
        (find-symbol name "NSHELL.APPLICATION")
      (declare (ignore _symbol))
      (is (not (eq :external status))))))

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

(test status-label-maps-job-states-to-strings
  "status-label returns the correct display label for each job state."
  (flet ((label (state)
           (let ((job (make-test-job 0 "x")))
             (nshell.domain.execution:job-state-transition job state)
             (nshell.application::%status-label job))))
    (is (string= "Running" (label :running)))
    (is (string= "Running" (label :background)))
    (is (string= "Stopped" (label :stopped)))
    (is (string= "Done"    (label :completed)))
    (is (string= "Done"    (label :done)))
    (is (string= "Created" (label :created)))))
