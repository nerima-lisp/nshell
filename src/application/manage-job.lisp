(in-package #:nshell.application)

(defvar *job-monitor* (nshell.domain.job-control:make-job-monitor))
(defvar *job-process-fns* nil)
(defvar *shell-pgid* 0)
(defvar *foreground-job-pgid* nil)

(define-value-struct job-listing
    ((id 0)
     (status "")
     (command ""))
  :constructor %allocate-job-listing)

(defun make-job-listing (id status command)
  (unless (and (integerp id) (plusp id))
    (error "Job listing id must be a positive integer: ~s" id))
  (unless (stringp status)
    (error "Job listing status must be a string: ~s" status))
  (unless (stringp command)
    (error "Job listing command must be a string: ~s" command))
  (%allocate-job-listing id status command))

(defstruct (job-wait-event (:constructor %make-job-wait-event (pid state status-code)))
  pid
  state
  status-code)

(defun %optional-job-process-fn (key)
  (getf *job-process-fns* key))

(defun %job-process-fn (key)
  (or (%optional-job-process-fn key)
      (error "Missing job process capability ~s" key)))

(defun %call-optional-job-process-fn (fn &rest args)
  "Call optional process capability FN with ARGS.
Returns the capability result as the primary value and any failure condition
as the secondary value, so unsupported terminal operations remain observable
without aborting job-control cleanup."
  (handler-case
      (values (apply fn args) nil)
    (error (condition)
      (values nil condition))))

(defun %set-acl-foreground-pgid (pgid)
  (let ((fn (%optional-job-process-fn :set-foreground-pgid-state)))
    (when fn
      (funcall fn pgid)))
  (values))

(defun %continue-process-group (pgid)
  (let ((fn (%optional-job-process-fn :continue-process-group)))
    (when fn
      (funcall fn pgid))))

(defun %get-foreground-pgroup ()
  (let ((fn (%optional-job-process-fn :get-foreground-pgroup)))
    (when fn
      (%call-optional-job-process-fn fn))))

(defun %set-foreground-pgroup (pgid)
  (let ((fn (%optional-job-process-fn :set-foreground-pgroup)))
    (when fn
      (%call-optional-job-process-fn fn pgid))))

(defun %kill-process (pid signal)
  (let ((fn (%optional-job-process-fn :kill-process)))
    (when fn
      (funcall fn pid signal))))

(defun %shell-process-group-id ()
  (or (and (integerp *shell-pgid*)
           (plusp *shell-pgid*)
           *shell-pgid*)
      (let ((fn (%optional-job-process-fn :current-process-id)))
        (and fn (%call-optional-job-process-fn fn)))
      0))

(defun fg (job-id &optional dispatcher process-registry terminal-fns
                    (job-monitor *job-monitor*) process-fns)
  "Move JOB-ID to the foreground, wait for it, then restore the shell PGID."
  (declare (ignore process-registry terminal-fns))
  (let ((*job-process-fns* (or process-fns *job-process-fns*)))
    (let ((job (%require-job job-id job-monitor)))
      (when job
        (let ((pgid (nshell.domain.execution:job-control-pgid job)))
          (when pgid
            (setf *foreground-job-pgid* pgid)
            (unwind-protect
                 (progn
                   (%set-acl-foreground-pgid pgid)
                   (%continue-process-group pgid)
                   (nshell.domain.job-control:foreground-job job-monitor job-id)
                   (when dispatcher
                     (publish-event dispatcher
                                    (nshell.domain.events:make-job-continued-event job-id)))
                   (%with-terminal-foreground-pgroup
                     pgid
                     (lambda () (%wait-job-pgid job job-id job-monitor))))
              (setf *foreground-job-pgid* nil)
              (%set-acl-foreground-pgid nil)))
          job)))))

(defun bg (job-id &optional dispatcher (job-monitor *job-monitor*) process-fns)
  "Continue JOB-ID in the background."
  (let ((*job-process-fns* (or process-fns *job-process-fns*)))
    (let ((job (%require-job job-id job-monitor)))
      (when job
        (let ((pgid (nshell.domain.execution:job-control-pgid job)))
          (when pgid
            (%continue-process-group pgid))
          (nshell.domain.job-control:background-job job-monitor job-id)
          (when dispatcher
            (publish-event dispatcher
                           (nshell.domain.events:make-job-continued-event job-id)))
          job)))))

(defun jobs (&optional (job-monitor *job-monitor*))
  "Return current job listings without writing to the terminal."
  (let (listings)
    (nshell.domain.job-control:monitor-map-jobs
     job-monitor
     (lambda (job-id job)
       (push (make-job-listing job-id
                               (%status-label job)
                               (%job-command-string job))
             listings)))
    (nreverse listings)))

(defun format-job-listing (listing &optional stream)
  "Render LISTING in the user-facing jobs format."
  (format stream "[~d] ~a ~a~%"
          (job-listing-id listing)
          (job-listing-status listing)
          (job-listing-command listing)))

(defun disown (job-id &optional (job-monitor *job-monitor*))
  "Remove JOB-ID from the job monitor."
  (nshell.domain.job-control:monitor-remove-job job-monitor job-id))

(defun %foreground-signal-target-pgid ()
  (let ((pgid (or *foreground-job-pgid*
                  (%get-foreground-pgroup))))
    (when (and pgid
               (nshell.domain.execution:valid-process-group-id-p pgid)
               (/= pgid (%shell-process-group-id)))
      pgid)))

(defun %job-command-string (job)
  (nshell.domain.execution:job-command-display-string job))

(defun %status-label (job)
  (case (nshell.domain.execution:job-state job)
    (:running "Running")
    (:background "Running")
    (:stopped "Stopped")
    ((:completed :done) "Done")
    (:created "Created")
    (otherwise "Unknown")))

(defun %with-terminal-foreground-pgroup (pgid thunk)
  (let ((previous (%get-foreground-pgroup)))
    (unwind-protect
         (progn
           (%set-foreground-pgroup pgid)
           (funcall thunk))
      (%set-foreground-pgroup (or previous (%shell-process-group-id))))))

(defun %classify-job-wait-status (pid status
                                    &key stopped-p exited-p exit-status
                                      signaled-p term-signal)
  (cond
    ((funcall stopped-p status)
     (%make-job-wait-event pid :stopped nil))
    ((funcall exited-p status)
     (%make-job-wait-event pid :exited (funcall exit-status status)))
    ((funcall signaled-p status)
     (%make-job-wait-event pid :signaled
                           (+ 128 (funcall term-signal status))))
    (t
     (%make-job-wait-event pid :unknown nil))))

(defun %classify-job-wait-error (errno)
  (cond
    ((member errno '(:echild :no-child))
     (%make-job-wait-event nil :no-child nil))
    ((member errno '(:eintr :interrupted))
     (%make-job-wait-event nil :interrupted nil))
    (t nil)))

(defun %wait-job-pgid-event (pgid)
  (multiple-value-bind (pid state detail)
      (funcall (%job-process-fn :wait-job) (- pgid) :untraced t)
    (case state
      (:stopped (%make-job-wait-event pid :stopped nil))
      (:exited (%make-job-wait-event pid :exited detail))
      (:signaled (%make-job-wait-event pid :signaled (+ 128 detail)))
      (:no-child (%make-job-wait-event nil :no-child nil))
      (:continued (%make-job-wait-event pid :continued nil))
      (otherwise (%make-job-wait-event pid :unknown nil)))))

(defun %wait-job-pgid (job job-id job-monitor)
  (let* ((pgid (nshell.domain.execution:job-control-pgid job))
         (known-pids (nshell.domain.execution:job-known-pids job))
         (pending-pids (copy-list known-pids))
         (last-pid (nshell.domain.execution:job-last-pid job))
         (last-stage-status nil)
         (latest-status nil)
         (statuses nil))
    (labels ((record-completion (pid status-code)
               (when status-code
                 (setf latest-status status-code)
                 (when pid
                   (push (cons pid status-code) statuses))
                 (when (and last-pid pid (= pid last-pid))
                   (setf last-stage-status status-code)))
               (when (and pid pending-pids)
                 (setf pending-pids (remove pid pending-pids :test #'=))))
             (finish-job ()
               (let ((status-code
                       (if (nshell.domain.execution:job-pipefail-p job)
                           (or (loop for pid in known-pids
                                     for entry = (assoc pid statuses :test #'=)
                                     when (and entry (not (zerop (cdr entry))))
                                     return (cdr entry))
                               0)
                           (or last-stage-status latest-status))))
                 (nshell.domain.job-control:complete-job
                  job-monitor job-id status-code))))
      (loop
        (let ((event (%wait-job-pgid-event pgid)))
          (case (job-wait-event-state event)
            (:stopped
             (nshell.domain.job-control:suspend-job job-monitor job-id nil)
             (return job))
            ((:exited :signaled)
             (record-completion (job-wait-event-pid event)
                                (job-wait-event-status-code event))
             (when (and known-pids (null pending-pids))
               (return (finish-job))))
            (:no-child
             (return (finish-job)))
            (:interrupted)
            (:unknown)))))))

(defun %require-job (job-id &optional (job-monitor *job-monitor*))
  (nshell.domain.job-control:monitor-find-job job-monitor job-id))
(defun signal-job (job-id signal &optional (job-monitor *job-monitor*) process-fns)
  "Send SIGNAL to JOB-ID and synchronize the monitor after a successful signal."
  (let ((*job-process-fns* (or process-fns *job-process-fns*)))
    (labels ((stop-signal-p (candidate)
               (member candidate '(:sigstop :sigtstp)))
             (continue-signal-p (candidate)
               (eq candidate :sigcont))
             (record-signal-state ()
               (let ((current-job
                       (nshell.domain.job-control:monitor-find-job
                        job-monitor job-id)))
                 (when (and current-job
                            (not (nshell.domain.execution:job-completed-p
                                  current-job)))
                   (cond
                     ((stop-signal-p signal)
                      (nshell.domain.job-control:suspend-job
                       job-monitor job-id nil))
                     ((and (continue-signal-p signal)
                           (nshell.domain.execution:job-stopped-p current-job))
                      (nshell.domain.job-control:background-job
                       job-monitor job-id)))))))
      (let ((job (%require-job job-id job-monitor)))
        (when job
          (let ((pgid (nshell.domain.execution:job-control-pgid job))
                (pids (nshell.domain.execution:job-known-pids job))
                (signaled-p nil))
            (if pgid
                (progn
                  (%kill-process (- pgid) signal)
                  (setf signaled-p t))
                (dolist (pid pids)
                  (%kill-process pid signal)
                  (setf signaled-p t)))
            (when signaled-p
              (record-signal-state))
            job))))))
(defun wait-for-job (job-id process-registry
                       &optional (job-monitor *job-monitor*) process-fns)
  "Wait for JOB-ID using the registered SBCL process objects.

The process registry is shared with the background reaper.  Waiting through
the same process objects avoids a second waitpid consumer and preserves the
exit status when the reaper has already completed the domain job."
  (let ((*job-process-fns* (or process-fns *job-process-fns*)))
    (let ((job (%require-job job-id job-monitor)))
      (cond
        ((null job)
         (values nil nil))
        ((nshell.domain.execution:job-completed-p job)
         (remhash job-id process-registry)
         (values job
                 (or (nshell.domain.execution:job-exit-code job)
                     0)))
        (t
         (let ((processes (%job-process-list (gethash job-id process-registry))))
           (if (null processes)
               (values nil nil)
               (progn
                 (%wait-job-processes processes)
                 (let ((exit-code (%job-process-exit-code job processes)))
                   (nshell.domain.job-control:complete-job
                    job-monitor job-id exit-code)
                   (remhash job-id process-registry)
                   (values job exit-code))))))))))
(defun %job-process-exit-code (job processes)
  (let ((statuses
          (mapcar
           (lambda (process)
             (let ((fn (%optional-job-process-fn :process-exit-status-code)))
               (and fn (funcall fn process))))
           (remove nil processes))))
    (if (nshell.domain.execution:job-pipefail-p job)
        (or (find-if (lambda (status)
                       (not (zerop status)))
                     statuses)
            0)
        (or (car (last statuses))
            (nshell.domain.execution:job-exit-code job)
            0))))
(defun %wait-job-processes (processes)
  (let ((fn (%optional-job-process-fn :process-wait)))
    (dolist (process processes)
      (when (and fn process)
        (funcall fn process))))
  processes)
(defun %job-process-list (entry)
  (cond
    ((null entry) nil)
    ((listp entry) entry)
    (t (list entry))))
