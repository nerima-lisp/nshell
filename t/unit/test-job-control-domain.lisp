(in-package #:nshell/test)

(describe "job-control-domain-tests"
  (it "job-monitor-construction-exposes-aggregate-facts"
    (let ((monitor (nshell.domain.job-control:make-job-monitor)))
      (expect (nshell.domain.job-control:job-monitor-p monitor) :to-be-truthy)
      (expect (nshell.domain.job-control:monitor-empty-p monitor) :to-be-truthy)
      (expect 1 :to-equal (nshell.domain.job-control:monitor-next-job-id monitor))))

  (it "monitor-collection-shape-is-internal-boundary"
    "Job monitor exposes ordered traversal, not hash-table or alist shape."
    (dolist (name '("MONITOR-JOBS" "MONITOR-ENTRIES"
                    "%MAKE-JOB-MONITOR" "COPY-JOB-MONITOR"
                    "JOB-MONITOR-JOBS-TABLE" "JOB-MONITOR-NEXT-ID-INT"))
      (multiple-value-bind (_symbol status)
          (find-symbol name "NSHELL.DOMAIN.JOB-CONTROL")
        (declare (ignore _symbol))
        (expect (eq :external status) :to-be-falsy)))
    (expect (fboundp 'nshell.domain.job-control:make-job-monitor) :to-be-truthy)
    (expect (fboundp 'nshell.domain.job-control::%make-job-monitor) :to-be-falsy)
    (expect (fboundp 'nshell.domain.job-control::copy-job-monitor) :to-be-falsy)
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (second-job (make-test-job 0 "second"))
           (first-job (make-test-job 1 "first"))
           (second-id (nshell.domain.job-control:monitor-add-job monitor second-job))
           (first-id (nshell.domain.job-control:monitor-add-job monitor first-job))
           (entries (collect-monitor-entries monitor)))
      (expect (every #'test-monitor-entry-p entries) :to-be-truthy)
      (expect (list second-id first-id) :to-equal (mapcar #'test-monitor-entry-job-id entries))
      (expect (list second-job first-job) :to-equal (mapcar #'test-monitor-entry-job entries))))

  (it "monitor-map-jobs-uses-stable-id-snapshot"
    "Monitor traversal is ordered by a stable id snapshot and skips jobs removed before visitation."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (first-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "first")))
           (second-id (nshell.domain.job-control:monitor-add-job
                       monitor (make-test-job 0 "second")))
           (third-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "third")))
           (visited nil))
      (nshell.domain.job-control:monitor-map-jobs
       monitor
       (lambda (job-id job)
         (declare (ignore job))
         (push job-id visited)
         (when (= job-id first-id)
           (nshell.domain.job-control:monitor-remove-job monitor second-id))))
      (expect (list first-id third-id) :to-equal (nreverse visited))))

  (it "monitor-creates-jobs"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (cmd (nshell.domain.execution:make-command "ls"))
           (pipe (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 1 pipe))
       (id (nshell.domain.job-control:monitor-add-job monitor job)))
      (expect 1 :to-equal id)
      (expect (nshell.domain.job-control:monitor-find-job monitor id) :to-be-truthy)))

  (it "monitor-add-background-job-initializes-tracked-job"
    "Background job registration owns the job aggregate initialization."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (id (nshell.domain.job-control:monitor-add-background-job
                monitor '(4321 4322) "left | right"))
           (job (nshell.domain.job-control:monitor-find-job monitor id)))
      (expect 1 :to-equal id)
      (expect '(4321 4322) :to-equal (nshell.domain.execution:job-pids job))
      (expect 4321 :to-equal (nshell.domain.execution:job-pgid job))
      (expect "left | right" :to-equal (nshell.domain.execution:job-command-line job))
      (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
      (expect :running :to-be (nshell.domain.execution:job-state job))))

  (it "monitor-update-returns-nil-for-missing-job"
    "Missing job IDs are outside the monitor aggregate and produce no update."
    (let ((monitor (nshell.domain.job-control:make-job-monitor)))
      (expect (nshell.domain.job-control:monitor-update monitor 404 :running) :to-be-null)))

  (it "monitor-records-exit-code-only-for-terminal-jobs"
    "Exit codes are facts about terminal jobs, not active monitor updates."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (cmd (nshell.domain.execution:make-command "ls"))
           (pipe (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 1 pipe))
           (id (nshell.domain.job-control:monitor-add-job monitor job)))
      (nshell.domain.job-control:monitor-update monitor id :running 7)
      (expect (nshell.domain.execution:job-exit-code job) :to-be-null)
      (nshell.domain.job-control:monitor-update monitor id :completed 0)
      (expect 0 :to-equal (nshell.domain.execution:job-exit-code job))))

  (it "complete-job-owns-terminal-state-and-default-exit-code"
    "Job-control owns completion transitions and nil exit-code normalization."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep"))
           (id (nshell.domain.job-control:monitor-add-job monitor job)))
      (expect job :to-be (nshell.domain.job-control:complete-job monitor id nil))
      (expect :completed :to-be (nshell.domain.execution:job-state job))
      (expect 0 :to-equal (nshell.domain.execution:job-exit-code job))
      (expect (nshell.domain.job-control:complete-job monitor 999 7) :to-be-null)))

  (it "foreground-and-background-job-own-visibility-flag"
    "Job-control owns foreground/background visibility changes."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep"))
           (id (nshell.domain.job-control:monitor-add-job monitor job)))
      (expect job :to-be (nshell.domain.job-control:background-job monitor id))
      (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
      (expect :background :to-be (nshell.domain.execution:job-state job))
      (expect job :to-be (nshell.domain.job-control:foreground-job monitor id))
      (expect (nshell.domain.execution:job-background-p job) :to-be-falsy)
      (expect :running :to-be (nshell.domain.execution:job-state job))
      (expect (nshell.domain.job-control:background-job monitor 999) :to-be-null)
      (expect (nshell.domain.job-control:foreground-job monitor 999) :to-be-null)))

  (it "tracks-current-and-previous-jobs-for-standard-job-specs"
    "Current and previous jobs follow the most recent active job."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (first-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "first")))
           (second-id (nshell.domain.job-control:monitor-add-job
                       monitor (make-test-job 0 "second")))
           (third-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "third"))))
      (expect third-id :to-equal
              (nshell.domain.job-control:monitor-current-job-id monitor))
      (expect second-id :to-equal
              (nshell.domain.job-control:monitor-previous-job-id monitor))
      (dolist (job-spec (list "%+" "%%" (format nil "%~d" third-id)
                              (format nil "~d" third-id) nil))
        (expect third-id :to-equal
                (nshell.domain.job-control:monitor-resolve-job-spec
                 monitor job-spec)))
      (expect second-id :to-equal
              (nshell.domain.job-control:monitor-resolve-job-spec monitor "%-"))
      (expect (nshell.domain.job-control:monitor-resolve-job-spec
               monitor "1junk") :to-be-null)
      (progn
        (expect (nshell.domain.job-control:monitor-resolve-job-spec
                 monitor "%") :to-be-null)
        (expect third-id :to-equal
                (nshell.domain.job-control:monitor-resolve-job-spec
                 monitor "%?ir"))
        (expect first-id :to-equal
                (nshell.domain.job-control:monitor-resolve-job-spec
                 monitor "%fir"))
        (expect second-id :to-equal
                (nshell.domain.job-control:monitor-resolve-job-spec
                 monitor "%?ond"))
        (expect (nshell.domain.job-control:monitor-resolve-job-spec
                 monitor "%missing") :to-be-null)
        (expect (nshell.domain.job-control:monitor-resolve-job-spec
                 monitor "%?") :to-be-null))
      (expect (nshell.domain.job-control:monitor-resolve-job-spec
               monitor "0") :to-be-null)
      (nshell.domain.job-control:background-job monitor first-id)
      (expect first-id :to-equal
              (nshell.domain.job-control:monitor-current-job-id monitor))
      (expect third-id :to-equal
              (nshell.domain.job-control:monitor-previous-job-id monitor))
      (nshell.domain.job-control:complete-job monitor first-id)
      (expect third-id :to-equal
              (nshell.domain.job-control:monitor-current-job-id monitor))
      (nshell.domain.job-control:monitor-remove-job monitor third-id)
      (expect second-id :to-equal
              (nshell.domain.job-control:monitor-current-job-id monitor))
      (expect (nshell.domain.job-control:monitor-previous-job-id monitor)
              :to-be-null))))
