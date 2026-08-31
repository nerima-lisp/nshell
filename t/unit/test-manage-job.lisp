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

  (it "bg-marks-job-as-background"
    "BG updates the job state without requiring terminal control when PGID is zero."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :args '("10")))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (nshell.application:*job-monitor* (nshell.domain.job-control:make-job-monitor)))
      (expect job :to-be (nshell.application:bg job-id monitor))
      (expect :background :to-be (nshell.domain.execution:job-state job))
      (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)))

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
                           (setf bg-result (nshell.application:bg 42 empty-monitor))))
              (fg-output (with-output-to-string (*standard-output*)
                           (setf fg-result
                                 (nshell.application:fg 42 empty-monitor)))))
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
            (nshell.application:fg job-id monitor)
          (error (condition)
            (expect (search "wait failed" (princ-to-string condition)) :to-be-truthy)))
        (expect nshell.application:*foreground-job-pgid* :to-be-null)
        (expect 0 :to-equal nshell.infrastructure.acl::*foreground-pgid*)
        (expect '(1000 4321) :to-equal set-foreground-calls))))
  (it "fg-restores-shell-pgid-after-a-successful-wait"
    "FG returns the job and hands the terminal back to the shell once wait returns."
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
              waited-job))
           ('nshell.infrastructure.acl:get-foreground-pgroup
            (lambda () 1000))
           ('nshell.infrastructure.acl:set-foreground-pgroup
            (lambda (pgid)
              (push pgid set-foreground-calls))))
        (expect job :to-be
                (nshell.application:fg job-id monitor)))
      (expect nshell.application:*foreground-job-pgid* :to-be-null)
      (expect '(1000 4321) :to-equal set-foreground-calls)))

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

  (it "wait-job-pgid-completes-after-child-reaped"
    "A no-child wait event completes a job whose children were already reaped."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "echo" :pgid 111 :pids '(111)))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job)))
      (with-temporary-function
          ('nshell.application::%wait-job-pgid-event
           (lambda (pgid)
             (expect 111 :to-equal pgid)
             (nshell.application::%make-job-wait-event nil :no-child nil)))
        (expect job :to-be
                (nshell.application::%wait-job-pgid job job-id monitor)))
      (expect :completed :to-be (nshell.domain.execution:job-state job))
      (expect 0 :to-equal (nshell.domain.execution:job-exit-code job))))

  (it "wait-job-pgid-uses-first-nonzero-pipefail-status"
    "Pipefail returns the first nonzero status in pipeline order."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "producer" :pgid 111 :pids '(111 222)))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (events '((222 :exited 0)
                     (111 :exited 7))))
      (setf (nshell.domain.execution:job-pipefail-p job) t)
      (with-temporary-function
          ('nshell.application::%wait-job-pgid-event
           (lambda (pgid)
             (expect 111 :to-equal pgid)
             (let ((event (pop events)))
               (unless event
                 (error "unexpected extra wait"))
               (destructuring-bind (pid state status-code) event
                 (nshell.application::%make-job-wait-event
                  pid state status-code)))))
        (expect job :to-be
                (nshell.application::%wait-job-pgid job job-id monitor)))
      (expect events :to-be-null)
      (expect :completed :to-be (nshell.domain.execution:job-state job))
      (expect 7 :to-equal (nshell.domain.execution:job-exit-code job))))

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
      (expect "Created" :to-equal (label :created))))

  (it "job-listing-construction-rejects-invalid-values"
    "Job listing validation rejects invalid identifiers and display fields."
    (expect (lambda ()
              (nshell.application::make-job-listing 0 "Running" "echo"))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.application::make-job-listing -1 "Running" "echo"))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.application::make-job-listing 1 nil "echo"))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.application::make-job-listing 1 "Running" nil))
            :to-throw 'error))

  (it "bg-continues-a-nonzero-process-group"
    "BG forwards continuation to a tracked process group before marking it background."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :args '("10") :pgid 4321))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (continue-calls nil))
      (with-temporary-function
          ('nshell.application::%continue-process-group
           (lambda (pgid)
             (push pgid continue-calls)))
        (expect job :to-be (nshell.application:bg job-id monitor)))
      (expect '(4321) :to-equal continue-calls)
      (expect :background :to-be (nshell.domain.execution:job-state job))))
  (it "signal-job-updates-stop-and-continue-state"
      "STOP and CONT signals keep monitor state aligned with successful delivery."
      (let* ((monitor (nshell.domain.job-control:make-job-monitor))
             (job (make-test-job 0 "sleep" :pgid 4321))
             (job-id (nshell.domain.job-control:monitor-add-job monitor job))
             (calls nil))
        (nshell.domain.job-control:background-job monitor job-id)
        (with-temporary-function
         ((quote nshell.infrastructure.acl:kill-process)
          (lambda (pid signal)
            (push (list pid signal) calls)
            0))
         (expect job :to-be
                 (nshell.application::signal-job job-id :sigstop monitor))
         (expect :stopped :to-be
                 (nshell.domain.execution:job-state job))
         (expect (list (list -4321 :sigstop)) :to-equal calls)
         (expect job :to-be
                 (nshell.application::signal-job job-id :sigcont monitor))
         (expect :background :to-be
                 (nshell.domain.execution:job-state job))
         (expect (list (list -4321 :sigcont)
                       (list -4321 :sigstop))
                 :to-equal calls))))

  (it "status-label-falls-back-for-unknown-state"
    "Unexpected internal job states remain visible as an explicit unknown label."
    (let ((job (make-test-job 0 "x")))
      (nshell.domain.execution::%set-job-state job :future)
      (expect "Unknown" :to-equal (nshell.application::%status-label job))))

  (it "parses-kill-options-and-signal-aliases"
    "KILL accepts numeric, named, long, list, and end-of-options forms."
    (flet ((parsed (&rest args)
             (multiple-value-list
              (nshell.application::%parse-kill-arguments args))))
      (expect :sigint :to-equal (first (parsed "-s" "INT" "123")))
      (expect '("-s" "123") :to-equal (second (parsed "--" "-s" "123")))
      (expect :sigkill :to-equal (first (parsed "--signal=SIGKILL" "%1")))
      (expect '("-9") :to-equal (second (parsed "-9")))
      (expect '("-") :to-equal (second (parsed "-")))
      (expect (third (parsed "-l")) :to-be-truthy)))

  (it "rejects-invalid-kill-options"
    "KILL reports malformed option arguments without partially parsed targets."
    (flet ((message (&rest args)
             (let ((value (nth-value 3
                            (nshell.application::%parse-kill-arguments args))))
               (if (listp value) (first value) value))))
      (expect "kill: option requires an argument -- signal~%"
              :to-equal (message "-s"))
      (expect "kill: invalid signal~%" :to-equal (message "--signal=NOPE"))
      (expect "kill: invalid signal~%" :to-equal (message "-s" "NOPE"))
      (expect (format nil "kill: unknown option: -NOPE~%")
              :to-equal (message "-NOPE"))))

  (it "parses-signal-designators-case-insensitively"
    "Signal names accept an optional SIG prefix and preserve numeric signals."
    (expect :sigterm :to-equal
            (nshell.application::%parse-signal-designator "sigterm"))
    (expect 15 :to-equal
            (nshell.application::%parse-signal-designator "15"))
    (expect (nshell.application::%parse-signal-designator "not-a-signal")
            :to-be-null))

  (it "normalizes-integer-and-job-wait-designators"
    "Numeric wait targets use PIDs while job syntax stays with the monitor."
    (expect 42 :to-equal (nshell.application::%parse-integer-designator "42"))
    (expect (nshell.application::%parse-integer-designator "42x") :to-be-null)
    (expect 7 :to-equal (nshell.application::%parse-positive-integer "7"))
    (expect (nshell.application::%parse-positive-integer "0") :to-be-null)
    (let ((monitor (nshell.domain.job-control:make-job-monitor)))
      (expect (nshell.domain.job-control:monitor-resolve-job-spec monitor nil)
              :to-equal
            (nshell.application::%resolve-wait-job-id monitor nil))))

  (it "resolves-wait-and-kill-targets-through-the-same-job-monitor"
    "PID targets use tracked process metadata while job targets use monitor selectors."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :pgid 4321 :pids '(4321 4322)))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (signals nil))
      (expect job-id :to-be
               (nshell.application::%resolve-wait-job-id monitor "4322"))
      (expect job-id :to-be
               (nshell.application::%resolve-wait-job-id monitor
                                                          (format nil "%~d" job-id)))
      (expect (nshell.application::%resolve-wait-job-id monitor "9999")
              :to-be-null)
      (with-temporary-function
          ((quote nshell.infrastructure.acl:kill-process)
           (lambda (pid signal)
             (push (list pid signal) signals)
             0))
        (expect t :to-be
                (nshell.application::%kill-one-target monitor "4322" :sigterm))
        (expect t :to-be
                (nshell.application::%kill-one-target
                 monitor (format nil "%~d" job-id) :sigint)))
      (expect '((-4321 :sigint) (4322 :sigterm)) :to-equal signals)
      (expect (nshell.application::%kill-one-target monitor "not-a-target" :sigterm)
              :to-be-null)))

  (it "renders-the-complete-kill-signal-list"
    "KILL -l exposes the stable signal names as one human-readable line."
    (expect (format nil "HUP INT QUIT ILL TRAP BUS FPE KILL USR1 SEGV USR2 PIPE ALRM TERM STOP TSTP CONT CHLD TTIN TTOU WINCH~%")
            :to-equal
            (nshell.application::%kill-list-output)))
  (it "classifies normalized wait observations without an OS wait"
    "Wait-status policy is testable independently from the ACL wait call."
    (flet ((classify (state detail)
             (nshell.application::%job-wait-event-from-observation
              321 state detail)))
      (let ((stopped (classify :stopped 19))
            (exited (classify :exited 9))
            (signaled (classify :signaled 9))
            (no-child (classify :no-child nil))
            (interrupted (classify :interrupted nil))
            (unknown (classify :future nil)))
        (expect :stopped :to-be
                (nshell.application::job-wait-event-state stopped))
        (expect nil :to-equal
                (nshell.application::job-wait-event-status-code stopped))
        (expect :exited :to-be
                (nshell.application::job-wait-event-state exited))
        (expect 9 :to-equal
                (nshell.application::job-wait-event-status-code exited))
        (expect :signaled :to-be
                (nshell.application::job-wait-event-state signaled))
        (expect 137 :to-equal
                (nshell.application::job-wait-event-status-code signaled))
        (expect :no-child :to-be
                (nshell.application::job-wait-event-state no-child))
        (expect :interrupted :to-be
                (nshell.application::job-wait-event-state interrupted))
        (expect :unknown :to-be
                (nshell.application::job-wait-event-state unknown)))))

  (it "continues foreground waiting across transient observations"
    "Interrupted and unknown wait observations do not complete a running job."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :pgid 4321 :pids '(4321)))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job))
           (events '((321 :interrupted nil)
                     (321 :future nil)
                     (nil :no-child nil))))
      (with-temporary-function
          ('nshell.application::%wait-job-pgid-event
           (lambda (pgid)
             (expect 4321 :to-equal pgid)
             (destructuring-bind (pid state detail) (pop events)
               (nshell.application::%job-wait-event-from-observation
                pid state detail))))
        (expect job :to-be
                (nshell.application::%wait-job-pgid job job-id monitor)))
      (expect :completed :to-be (nshell.domain.execution:job-state job))
      (expect 0 :to-equal (nshell.domain.execution:job-exit-code job))))
)
