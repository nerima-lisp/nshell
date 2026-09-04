(in-package #:nshell.application)

(defmacro %job-spec (args)
  `(first ,args))

(defun %resolve-job-id (job-monitor args &key active-only-p)
  (let ((job-id
         (nshell.domain.job-control:monitor-resolve-job-spec
          job-monitor
          (%job-spec args))))
    (when (and job-id
               (or (not active-only-p)
                   (let ((job (nshell.domain.job-control:monitor-find-job
                               job-monitor job-id)))
                     (and job
                          (not (nshell.domain.execution:job-completed-p job))))))
      job-id)))

(defmacro %job-spec-label (args)
  `(or (%job-spec ,args) "current"))

(defun %missing-job-output (command job-spec)
  (format nil "~a: no such job: ~a~%" command job-spec))

(define-job-selection-builtin %builtin-fg fg)
(define-job-selection-builtin %builtin-bg bg)

(defun %select-job-listings (job-monitor args)
  (let ((listings (jobs job-monitor)))
    (if (null args)
        (values listings nil)
        (let (selected missing)
          (dolist (job-spec args)
            (let* ((job-id
                     (nshell.domain.job-control:monitor-resolve-job-spec
                      job-monitor job-spec))
                   (listing (and job-id
                                 (find job-id listings
                                       :key #'job-listing-id
                                       :test #'=))))
              (if listing
                  (push listing selected)
                  (push job-spec missing))))
          (values (nreverse selected) (nreverse missing))))))

(define-builtin %builtin-jobs (context args) ()
  (let ((job-monitor (shell-context-job-monitor context)))
    (multiple-value-bind (listings missing)
        (%select-job-listings job-monitor args)
      (values
       (with-output-to-string (out)
         (dolist (listing listings)
           (format-job-listing listing out))
         (dolist (job-spec missing)
           (write-string (%missing-job-output "jobs"
                                               (or job-spec "current"))
                         out)))
       (if missing 1 0)))))

(define-builtin %builtin-disown (context args) ()
  (let* ((job-monitor (shell-context-job-monitor context))
         (job-spec (%job-spec args))
         (job-id (%resolve-job-id job-monitor args)))
    (if job-id
        (progn
          (disown job-id job-monitor)
          (values nil 0))
        (values (if args
                    (format nil "disown: job [~a] not found~%"
                            (or job-spec "current"))
                    (format nil "disown: no current job~%"))
                1))))
(defun %parse-integer-designator (text)
  (when (stringp text)
    (handler-case
        (parse-integer text :junk-allowed nil)
      (parse-error () nil))))
(defun %parse-positive-integer (text)
  (let ((value (%parse-integer-designator text)))
    (when (and value (plusp value))
      value)))
(defun %find-job-id-by-pid (job-monitor pid)
  (let ((found nil))
    (nshell.domain.job-control:monitor-map-jobs
     job-monitor
     (lambda (job-id job)
       (when (and (null found)
                  (member pid
                          (nshell.domain.execution:job-pids job)
                          :test #'=))
         (setf found job-id))))
    found))
(defun %resolve-wait-job-id (job-monitor job-spec)
  (cond
    ((null job-spec)
     (nshell.domain.job-control:monitor-resolve-job-spec
      job-monitor nil))
    ((and (stringp job-spec)
          (plusp (length job-spec))
          (or (char= (char job-spec 0) #\%)
              (string= job-spec "+")
              (string= job-spec "-")))
     (nshell.domain.job-control:monitor-resolve-job-spec
      job-monitor job-spec))
    (t
     (or (let ((pid (%parse-positive-integer job-spec)))
           (and pid (%find-job-id-by-pid job-monitor pid)))
         (nshell.domain.job-control:monitor-resolve-job-spec
          job-monitor job-spec)))))
(define-builtin %builtin-wait (context args) ()
  (let* ((job-monitor (shell-context-job-monitor context))
         (process-registry (shell-context-process-registry context))
         (specs
           (if args
               args
               (let (active-job-ids)
                 (nshell.domain.job-control:monitor-map-jobs
                  job-monitor
                  (lambda (job-id job)
                    (unless
                        (nshell.domain.execution:job-completed-p job)
                      (push job-id active-job-ids))))
                 (nreverse active-job-ids))))
         (last-code 0)
         (missing nil))
    (dolist (job-spec specs)
      (let ((job-id (%resolve-wait-job-id job-monitor job-spec)))
        (multiple-value-bind (job exit-code)
            (if job-id
                (wait-for-job job-id process-registry job-monitor)
                (values nil nil))
          (if job
              (setf last-code exit-code)
              (push (or job-spec "current") missing)))))
    (if missing
        (values
         (with-output-to-string (out)
           (dolist (job-spec (nreverse missing))
             (format out "wait: no such job: ~a~%" job-spec)))
         1)
        (values nil last-code))))
(defun %resolve-kill-job-id (job-monitor target)
  (when (and (stringp target)
             (plusp (length target))
             (or (char= (char target 0) #\%)
                 (string= target "+")
                 (string= target "-")))
    (nshell.domain.job-control:monitor-resolve-job-spec
     job-monitor target)))
(defun %kill-one-target (job-monitor target signal)
  (let ((job-id (%resolve-kill-job-id job-monitor target)))
    (cond
      ((and job-id (signal-job job-id signal job-monitor))
       t)
      ((let ((pid (%parse-integer-designator target)))
         (when pid
           (nshell.infrastructure.acl:kill-process pid signal)
           t)))
      (t nil))))
(defun %kill-list-output ()
  (format nil "~{~a~^ ~}~%"
          (mapcar #'car +job-signal-specs+)))
(define-builtin %builtin-kill (context args) ()
  (multiple-value-bind (signal-designator targets list-signals-p parse-error)
      (%parse-kill-arguments args)
    (cond
      (parse-error
       (values parse-error 1))
      (list-signals-p
       (values (%kill-list-output) 0))
      ((null targets)
       (%builtin-usage "kill" "kill [-signal] pid|%job"))
      (t
       (let ((job-monitor (shell-context-job-monitor context))
             (code 0))
         (values
          (with-output-to-string (out)
            (dolist (target targets)
              (handler-case
                  (unless (%kill-one-target
                           job-monitor target signal-designator)
                    (setf code 1)
                    (format out "kill: no such process or job: ~a~%"
                            target))
                (error (condition)
                  (setf code 1)
                  (format out "kill: ~a: ~a~%"
                          target condition))))
          code)))))))
