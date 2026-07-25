(in-package #:nshell/test)

(describe "manage-job-service-tests"
  (it "jobs-returns-current-job-listings"
    "JOBS returns structured listings without writing to standard output."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "echo" :args '("hello"))))
      (nshell.domain.job-control:monitor-add-job monitor job)
      (let ((nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
        (let (listings)
          (let ((output (capture-standard-output
                          (setf listings (nshell.application:jobs monitor)))))
            (expect "" :to-equal output))
          (expect 1 :to-equal (length listings))
          (let ((listing (first listings)))
            (expect (nshell.application:job-listing-p listing) :to-be-truthy)
            (expect 1 :to-equal (nshell.application:job-listing-id listing))
            (expect "Created" :to-equal (nshell.application:job-listing-status listing))
            (expect "echo hello" :to-equal (nshell.application:job-listing-command listing))
            (expect (format nil "[1] Created echo hello~%") :to-equal (nshell.application:format-job-listing listing)))))))

  (it "job-listing-construction-is-use-case-owned"
    "Job listings expose read access only; construction stays inside the use case."
    (let ((listing (first (let* ((monitor (nshell.domain.job-control:make-job-monitor))
                                 (job (make-test-job 0 "printf" :args '("ok"))))
                      (nshell.domain.job-control:monitor-add-job monitor job)
                      (nshell.application:jobs monitor)))))
      (expect (nshell.application:job-listing-p listing) :to-be-truthy)
      (expect (eq :external
                   (nth-value 1 (find-symbol "MAKE-JOB-LISTING"
                                             "NSHELL.APPLICATION"))) :to-be-falsy)
      (expect (fboundp 'nshell.application::copy-job-listing) :to-be-falsy)
      (expect (fboundp '(setf nshell.application:job-listing-command)) :to-be-falsy)
      (expect "printf ok" :to-equal (nshell.application:job-listing-command listing))))

  (it "bg-marks-job-as-background-and-publishes-continuation"
    "BG updates the job state without requiring terminal control when PGID is zero."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (dispatcher (nshell.application:make-event-dispatcher))
           (job (make-test-job 0 "sleep" :args '("10")))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
      (with-event-capture (continued dispatcher :job-continued)
          (nshell.domain.events:domain-event-type event)
        (expect job :to-be (nshell.application:bg job-id dispatcher monitor))
        (expect :background :to-be (nshell.domain.execution:job-state job))
        (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
        (expect (nshell.application:drain-events dispatcher) :to-be-null)
        (expect '(:job-continued) :to-equal (nreverse continued)))))

  (it "disown-removes-job-from-monitor"
    "DISOWN removes a tracked job and returns true for an existing id."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :args '("10")))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
      (expect (nshell.application:disown job-id monitor) :to-be-truthy)
      (expect (nshell.domain.job-control:monitor-find-job monitor job-id) :to-be-null)))

  (it "missing-job-commands-return-nil-without-output"
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
          (expect bg-result :to-be-null)
          (expect fg-result :to-be-null)
          (expect "" :to-equal bg-output)
          (expect "" :to-equal fg-output)))))

  (it "fg-clears-foreground-pgid-when-wait-fails"
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
              (expect 4321 :to-equal pgid)))
         ('nshell.application::%wait-job-pgid
          (lambda (waited-job waited-job-id waited-monitor)
            (expect job :to-be waited-job)
            (expect job-id :to-equal waited-job-id)
            (expect monitor :to-be waited-monitor)
            (expect 4321 :to-equal nshell.application:*foreground-job-pgid*)
            (expect 4321 :to-equal nshell.infrastructure.acl::*foreground-pgid*)
            (error "wait failed")))
           ('nshell.infrastructure.acl:get-foreground-pgroup
            (lambda () 1000))
           ('nshell.infrastructure.acl:set-foreground-pgroup
            (lambda (pgid)
              (push pgid set-foreground-calls))))
        (handler-case
            (nshell.application:fg job-id nil nil nil monitor)
          (error (condition)
            (expect (search "wait failed" (princ-to-string condition)) :to-be-truthy)))
        (expect nshell.application:*foreground-job-pgid* :to-be-null)
        (expect 0 :to-equal nshell.infrastructure.acl::*foreground-pgid*)
        (expect '(1000 4321) :to-equal set-foreground-calls))))

  (it "wait-job-pgid-waits-for-known-pipeline-pids"
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
             (expect 111 :to-equal pgid)
             (let ((event (pop events)))
               (unless event
                 (error "unexpected extra wait"))
               (destructuring-bind (pid state status-code) event
                 (push pid waited-pids)
                 (nshell.application::%make-job-wait-event pid state status-code)))))
        (expect job :to-be (nshell.application::%wait-job-pgid job job-id monitor)))
      (expect events :to-be-null)
      (expect '(222 111) :to-equal (nreverse waited-pids))
      (expect :completed :to-be (nshell.domain.execution:job-state job))
      (expect 7 :to-equal (nshell.domain.execution:job-exit-code job))))

  (it "wait-job-pgid-stops-on-stopped-event"
    "Foreground wait preserves stopped jobs instead of completing a partially stopped pipeline."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :pgid 111 :pids '(111 222)))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (events '((111 :stopped nil)
                     (222 :exited 0))))
      (with-temporary-function
          ('nshell.application::%wait-job-pgid-event
           (lambda (pgid)
             (expect 111 :to-equal pgid)
             (let ((event (pop events)))
               (unless event
                 (error "unexpected extra wait"))
               (destructuring-bind (pid state status-code) event
                 (nshell.application::%make-job-wait-event pid state status-code)))))
        (expect job :to-be (nshell.application::%wait-job-pgid job job-id monitor)))
      (expect '((222 :exited 0)) :to-equal events)
      (expect :stopped :to-be (nshell.domain.execution:job-state job))
      (expect (nshell.domain.execution:job-exit-code job) :to-be-null)))

  (it "wait-job-event-shape-is-internal-boundary"
    "Foreground wait events are internal application values, not exported API."
    (dolist (name '("JOB-WAIT-EVENT" "%MAKE-JOB-WAIT-EVENT"
                    "JOB-WAIT-EVENT-PID" "JOB-WAIT-EVENT-STATE"
                    "JOB-WAIT-EVENT-STATUS-CODE"))
      (multiple-value-bind (_symbol status)
          (find-symbol name "NSHELL.APPLICATION")
        (declare (ignore _symbol))
        (expect (eq :external status) :to-be-falsy))))

  (it "foreground-signal-target-ignores-shell-process-group"
    "Foreground signal forwarding never targets the shell's own process group."
    (let ((nshell.application:*shell-pgid* 1000)
          (nshell.application:*foreground-job-pgid* nil))
      (with-temporary-function
          ('nshell.infrastructure.acl:get-foreground-pgroup
           (lambda () 1000))
        (expect (nshell.application::%foreground-signal-target-pgid) :to-be-null)))
    (let ((nshell.application:*shell-pgid* 1000)
          (nshell.application:*foreground-job-pgid* 1000))
      (with-temporary-function
          ('nshell.infrastructure.acl:get-foreground-pgroup
           (lambda () 2000))
        (expect (nshell.application::%foreground-signal-target-pgid) :to-be-null)))
    (let ((nshell.application:*shell-pgid* 1000)
          (nshell.application:*foreground-job-pgid* nil))
      (with-temporary-function
          ('nshell.infrastructure.acl:get-foreground-pgroup
           (lambda () 2000))
        (expect 2000 :to-equal (nshell.application::%foreground-signal-target-pgid)))))

  (it "status-label-maps-job-states-to-strings"
    "status-label returns the correct display label for each job state."
    (flet ((label (state)
             (let ((job (make-test-job 0 "x")))
               (nshell.domain.execution:job-state-transition job state)
               (nshell.application::%status-label job))))
      (expect "Running" :to-equal (label :running))
      (expect "Running" :to-equal (label :background))
      (expect "Stopped" :to-equal (label :stopped))
      (expect "Done" :to-equal (label :completed))
      (expect "Done" :to-equal (label :done))
      (expect "Created" :to-equal (label :created)))))
