(in-package #:nshell/test)

(defun %kill-registered-job-processes (context)
  "SIGKILL and reap every process group still registered in CONTEXT."
  (let ((processes nil))
    (maphash (lambda (job-id entry)
               (declare (ignore job-id))
               (setf processes
                     (append (nshell.application::%job-process-list entry) processes)))
             (nshell.application::shell-context-process-registry context))
    (dolist (process processes)
      (ignore-errors
        (nshell.infrastructure.acl:kill-process
         (- (nshell.infrastructure.acl:process-pid process)) :sigkill))
      (ignore-errors (nshell.infrastructure.acl:process-wait process)))))

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

  (it "excludes-completed-jobs-from-active-selection"
    "fg/bg selection accepts only jobs that are not completed."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (job-id (nshell.domain.job-control:monitor-add-job
                    monitor (make-test-job 0 "true"))))
      (nshell.domain.job-control:complete-job monitor job-id 0)
      (expect nil :to-be
              (nshell.application::%resolve-job-id
               monitor (list (format nil "~d" job-id))
               :active-only-p t))
      (expect job-id :to-be
              (nshell.application::%resolve-job-id
               monitor (list (format nil "~d" job-id))))))

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

  (it "stopped-foreground-command-is-listed-resumed-by-bg-and-finished-by-fg"
    "A foreground child that stops itself is listed as Stopped, runs after bg, and fg waits for it to finish and leave the list."
    (let ((context (make-test-builtins-context)))
      (host-kit:with-temporary-directory (directory)
        (let ((child-file (sb-ext:native-namestring
                           (merge-pathnames "e02-child.txt" directory))))
          (unwind-protect
               (progn
                 (expect (+ 128 sb-unix:sigtstp) :to-equal
                         (nth-value 1
                           (nshell.application::%run-terminal-command
                            context "/bin/sh"
                            (list "-c"
                                  (format nil "kill -STOP $$; sleep 1; printf E02_CHILD_DONE > '~a'"
                                          child-file)))))
                 (assert-builtin-call (context "jobs" nil)
                   :contains (list "Stopped" "sleep 1"))
                 (assert-builtin-call (context "bg" '("%1"))
                   :code 0)
                 (assert-builtin-call (context "jobs" nil)
                   :contains (list "Running" "sleep 1"))
                 (assert-builtin-call (context "fg" '("%1"))
                   :code 0)
                 (expect "E02_CHILD_DONE" :to-equal
                         (and (probe-file child-file)
                              (host-kit:read-file-string child-file)))
                 (assert-builtin-call (context "jobs" nil)
                   :output-empty t))
            (%kill-registered-job-processes context))))))

  (it "bg-resumes-a-stopped-foreground-command-with-its-descendant"
    "bg continues the whole stopped group, so the descendant finishes and the child's wait returns."
    (let ((context (make-test-builtins-context)))
      (host-kit:with-temporary-directory (directory)
        (let ((child-file (sb-ext:native-namestring
                           (merge-pathnames "e02-bg-child.txt" directory))))
          (unwind-protect
               (progn
                 (expect (+ 128 sb-unix:sigtstp) :to-equal
                         (nth-value 1
                           (nshell.application::%run-terminal-command
                            context "/bin/sh"
                            (list "-c"
                                  (format nil "sleep 1 & kill -STOP 0; wait; printf E02_BG_CHILD_REAPED_1 > '~a'"
                                          child-file)))))
                 (assert-builtin-call (context "bg" '("%1"))
                   :code 0)
                 (wait-for-file-content child-file "E02_BG_CHILD_REAPED_1"
                                        :attempts 100 :delay 0.05)
                 (expect "E02_BG_CHILD_REAPED_1" :to-equal
                         (and (probe-file child-file)
                              (host-kit:read-file-string child-file))))
            (%kill-registered-job-processes context))))))

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
