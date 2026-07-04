(in-package #:nshell/test)
(def-suite job-control-domain-tests :description "Job control domain tests" :in nshell-tests)
(in-suite job-control-domain-tests)

(test job-monitor-raw-constructor-is-internal-boundary
  (let ((monitor (nshell.domain.job-control:make-job-monitor)))
    (is (hash-table-p (nshell.domain.job-control::job-monitor-jobs monitor)))
    (is (= 1 (nshell.domain.job-control::job-monitor-next-id monitor)))
    (is (fboundp 'nshell.domain.job-control::%make-job-monitor))))

(test monitor-collection-shape-is-internal-boundary
  "Job monitor exposes ordered traversal, not hash-table or alist shape."
  (dolist (name '("MONITOR-JOBS" "MONITOR-ENTRIES"))
    (multiple-value-bind (_symbol status)
        (find-symbol name "NSHELL.DOMAIN.JOB-CONTROL")
      (declare (ignore _symbol))
      (is (not (eq :external status)))))
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (second-job (make-test-job 0 "second"))
         (first-job (make-test-job 1 "first"))
         (second-id (nshell.domain.job-control:monitor-add-job monitor second-job))
         (first-id (nshell.domain.job-control:monitor-add-job monitor first-job))
         (entries (collect-monitor-entries monitor)))
    (is (equal (list second-id first-id) (mapcar #'car entries)))
    (is (equal (list second-job first-job) (mapcar #'cdr entries)))))

(test monitor-creates-jobs
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job 1 pipe))
     (id (nshell.domain.job-control:monitor-add-job monitor job)))
    (is (= 1 id))
    (is (nshell.domain.job-control:monitor-find-job monitor id))))

(test monitor-add-background-job-initializes-tracked-job
  "Background job registration owns the job aggregate initialization."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (id (nshell.domain.job-control:monitor-add-background-job
              monitor '(4321 4322) "left | right"))
         (job (nshell.domain.job-control:monitor-find-job monitor id)))
    (is (= 1 id))
    (is (equal '(4321 4322) (nshell.domain.execution:job-pids job)))
    (is (= 4321 (nshell.domain.execution:job-pgid job)))
    (is (string= "left | right" (nshell.domain.execution:job-command-line job)))
    (is (nshell.domain.execution:job-background-p job))
    (is (eq :running (nshell.domain.execution:job-state job)))))

(test monitor-update-returns-nil-for-missing-job
  "Missing job IDs are outside the monitor aggregate and produce no update."
  (let ((monitor (nshell.domain.job-control:make-job-monitor)))
    (is (null (nshell.domain.job-control:monitor-update monitor 404 :running)))))

(test monitor-records-exit-code-only-for-terminal-jobs
  "Exit codes are facts about terminal jobs, not active monitor updates."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job 1 pipe))
         (id (nshell.domain.job-control:monitor-add-job monitor job)))
    (nshell.domain.job-control:monitor-update monitor id :running 7)
    (is (null (nshell.domain.execution:job-exit-code job)))
    (nshell.domain.job-control:monitor-update monitor id :completed 0)
    (is (= 0 (nshell.domain.execution:job-exit-code job)))))

(test complete-job-owns-terminal-state-and-default-exit-code
  "Job-control owns completion transitions and nil exit-code normalization."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "sleep"))
         (id (nshell.domain.job-control:monitor-add-job monitor job)))
    (is (eq job (nshell.domain.job-control:complete-job monitor id nil)))
    (is (eq :completed (nshell.domain.execution:job-state job)))
    (is (= 0 (nshell.domain.execution:job-exit-code job)))
    (is (null (nshell.domain.job-control:complete-job monitor 999 7)))))

(test foreground-and-background-job-own-visibility-flag
  "Job-control owns foreground/background visibility changes."
  (let* ((monitor (nshell.domain.job-control:make-job-monitor))
         (job (make-test-job 0 "sleep"))
         (id (nshell.domain.job-control:monitor-add-job monitor job)))
    (is (eq job (nshell.domain.job-control:background-job monitor id)))
    (is (nshell.domain.execution:job-background-p job))
    (is (eq :background (nshell.domain.execution:job-state job)))
    (is (eq job (nshell.domain.job-control:foreground-job monitor id)))
    (is (not (nshell.domain.execution:job-background-p job)))
    (is (eq :running (nshell.domain.execution:job-state job)))
    (is (null (nshell.domain.job-control:background-job monitor 999)))
    (is (null (nshell.domain.job-control:foreground-job monitor 999)))))

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
