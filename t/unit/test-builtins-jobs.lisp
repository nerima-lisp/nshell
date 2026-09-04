(in-package #:nshell/test)
 
(describe "builtin-job-tests"
  (it "fg-and-bg-builtins-propagate-status-and-missing-job-errors"
    "fg/bg builtins return job status and missing-job failures."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (job (make-test-job 0 "sleep"))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job)))
      (let ((nshell.application:*job-monitor*
              (nshell.domain.job-control:make-job-monitor)))
        (assert-builtin-call (context "bg" (list (format nil "~d" job-id)))
          :code 0
          :output-null t)
        (assert-builtin-call (context "fg" (list (format nil "~d" job-id)))
          :code 0
          :output-null t)))
    (let ((context (make-test-builtins-context))
          (monitor (nshell.domain.job-control:make-job-monitor)))
      (let ((nshell.application:*job-monitor* monitor))
        (assert-builtin-call (context "bg" nil)
          :code 1
          :output (format nil "bg: no such job: current~%"))
        (assert-builtin-call (context "fg" nil)
          :code 1
          :output (format nil "fg: no such job: current~%"))
        (assert-builtin-call (context "bg" '("42"))
          :code 1
          :output (format nil "bg: no such job: 42~%"))
        (assert-builtin-call (context "fg" '("42"))
          :code 1
          :output (format nil "fg: no such job: 42~%")))))

  (it "jobs-and-disown-builtins-use-context-monitor"
    "jobs/disown builtins operate on the shell context monitor, not the global monitor."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (job (make-test-job 0 "sleep" :args '("10")))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job)))
      (let ((nshell.application:*job-monitor*
              (nshell.domain.job-control:make-job-monitor)))
        (assert-builtin-call (context "jobs" nil)
          :code 0
          :contains (list (format nil "[~d]" job-id) "Created" "sleep 10"))
        (assert-builtin-call (context "disown" (list (format nil "~d" job-id)))
          :code 0
          :output-null t)
        (expect (nshell.domain.job-control:monitor-find-job monitor job-id) :to-be-null)
        (assert-builtin-call (context "disown" (list (format nil "~d" job-id)))
          :code 1
          :output (format nil "disown: job [~d] not found~%" job-id)))))

  (it "disown-without-a-job-id-operates-on-the-current-job"
    "Bare disown targets the current job when one exists, and reports a clear error otherwise."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (job (make-test-job 0 "sleep" :args '("10")))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job)))
      (assert-builtin-call (context "disown" nil)
        :code 0
        :output-null t)
      (expect (nshell.domain.job-control:monitor-find-job monitor job-id) :to-be-null))
    (let ((context (make-test-builtins-context)))
      (assert-builtin-call (context "disown" nil)
        :code 1
        :output (format nil "disown: no current job~%"))))

  )
