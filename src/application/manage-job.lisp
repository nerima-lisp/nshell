(in-package #:nshell.application)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defvar *job-monitor* (nshell.domain.job-control:make-job-monitor))
(defvar *shell-pgid* (sb-posix:getpid))
(defvar *foreground-job-pgid* nil)

(defstruct (job-listing
            (:constructor %allocate-job-listing (id status command))
            (:copier nil))
  (id 0 :read-only t)
  (status "" :read-only t)
  (command "" :read-only t))

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

(defun %set-acl-foreground-pgid (pgid)
  (let ((symbol (find-symbol "*FOREGROUND-PGID*" "NSHELL.INFRASTRUCTURE.ACL")))
    (when symbol
      (setf (symbol-value symbol) (or pgid 0))))
  (values))

(defun %continue-process-group (pgid)
  (sb-posix:kill (- pgid) sb-unix:sigcont))

(defun fg (job-id &optional dispatcher process-registry terminal-fns
                    (job-monitor *job-monitor*))
  "Move JOB-ID to the foreground, wait for it, then restore the shell PGID."
  (declare (ignore process-registry terminal-fns))
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
        job))))

(defun bg (job-id &optional dispatcher (job-monitor *job-monitor*))
  "Continue JOB-ID in the background."
  (let ((job (%require-job job-id job-monitor)))
    (when job
      (let ((pgid (nshell.domain.execution:job-control-pgid job)))
        (when pgid
          (%continue-process-group pgid))
        (nshell.domain.job-control:background-job job-monitor job-id)
        (when dispatcher
          (publish-event dispatcher
                         (nshell.domain.events:make-job-continued-event job-id)))
        job))))

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

(defun interrupt-foreground ()
  "Send SIGINT to the foreground job process group."
  (let ((pgid (%foreground-signal-target-pgid)))
    (when pgid
      (sb-posix:kill (- pgid) sb-unix:sigint))))

(defun suspend-foreground ()
  "Send SIGTSTP to the foreground job process group."
  (let ((pgid (%foreground-signal-target-pgid)))
    (when pgid
      (sb-posix:kill (- pgid) sb-unix:sigtstp))))

(defun %foreground-signal-target-pgid ()
  (let ((pgid (or *foreground-job-pgid*
                  (ignore-errors (nshell.infrastructure.acl:get-foreground-pgroup)))))
    (when (and pgid
               (nshell.domain.execution:valid-process-group-id-p pgid)
               (/= pgid *shell-pgid*))
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
  (let ((previous (ignore-errors (nshell.infrastructure.acl:get-foreground-pgroup))))
    (unwind-protect
         (progn
           (ignore-errors (nshell.infrastructure.acl:set-foreground-pgroup pgid))
           (funcall thunk))
      (ignore-errors
        (nshell.infrastructure.acl:set-foreground-pgroup (or previous *shell-pgid*))))))

(defun %wait-job-pgid-event (pgid)
  (handler-case
      (multiple-value-bind (pid status)
          (sb-posix:waitpid (- pgid) sb-posix:wuntraced)
        (cond
          ((sb-posix:wifstopped status)
           (%make-job-wait-event pid :stopped nil))
          ((sb-posix:wifexited status)
           (%make-job-wait-event pid :exited (sb-posix:wexitstatus status)))
          ((sb-posix:wifsignaled status)
           (%make-job-wait-event pid :signaled (+ 128 (sb-posix:wtermsig status))))
          (t
           (%make-job-wait-event pid :unknown nil))))
    (sb-posix:syscall-error (condition)
      (let ((errno (sb-posix:syscall-errno condition)))
        (cond
          ((= errno sb-posix:echild)
           (%make-job-wait-event nil :no-child nil))
          ((= errno sb-posix:eintr)
           (%make-job-wait-event nil :interrupted nil))
          (t
           (error condition)))))))

(defun %wait-job-pgid (job job-id job-monitor)
  (let* ((pgid (nshell.domain.execution:job-control-pgid job))
         (known-pids (nshell.domain.execution:job-known-pids job))
         (pending-pids (copy-list known-pids))
         (last-pid (nshell.domain.execution:job-last-pid job))
         (last-stage-status nil)
         (latest-status nil))
    (labels ((record-completion (pid status-code)
               (when status-code
                 (setf latest-status status-code)
                 (when (and last-pid pid (= pid last-pid))
                   (setf last-stage-status status-code)))
               (when (and pid pending-pids)
                 (setf pending-pids (remove pid pending-pids :test #'=))))
             (finish-job ()
               (let ((status-code (or last-stage-status latest-status)))
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
