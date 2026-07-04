(in-package #:nshell.application)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defvar *job-monitor* (nshell.domain.job-control:make-job-monitor))
(defvar *shell-pgid* (sb-posix:getpid))
(defvar *foreground-job-pgid* nil)

(defun %set-acl-foreground-pgid (pgid)
  (let ((symbol (find-symbol "*FOREGROUND-PGID*" "NSHELL.INFRASTRUCTURE.ACL")))
    (when symbol
      (setf (symbol-value symbol) (or pgid 0))))
  (values))

(defun %valid-job-pgid-p (pgid)
  (and (integerp pgid) (plusp pgid)))

(defun %continue-process-group (pgid)
  (sb-posix:kill (- pgid) sb-unix:sigcont))

(defun fg (job-id &optional dispatcher process-registry terminal-fns
                    (job-monitor *job-monitor*))
  "Move JOB-ID to the foreground, wait for it, then restore the shell PGID."
  (declare (ignore process-registry terminal-fns))
  (let ((job (%require-job job-id "fg" job-monitor)))
    (when job
      (let ((pgid (nshell.domain.execution:job-pgid job)))
        (when (%valid-job-pgid-p pgid)
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
  (let ((job (%require-job job-id "bg" job-monitor)))
    (when job
      (let ((pgid (nshell.domain.execution:job-pgid job)))
        (when (%valid-job-pgid-p pgid)
          (%continue-process-group pgid))
        (nshell.domain.job-control:background-job job-monitor job-id)
        (when dispatcher
          (publish-event dispatcher
                         (nshell.domain.events:make-job-continued-event job-id)))
        job))))

(defun jobs (&optional (job-monitor *job-monitor*))
  "Print and return current jobs."
  (let ((entries (nshell.domain.job-control:monitor-entries job-monitor)))
    (dolist (entry entries)
      (let ((jid (car entry))
            (job (cdr entry)))
        (format t "[~d] ~a ~a~%"
                jid
                (%status-label job)
                (%job-command-string job))))
    entries))

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
               (%valid-job-pgid-p pgid)
               (/= pgid *shell-pgid*))
      pgid)))

(defun %job-command-string (job)
  (or (and (> (length (nshell.domain.execution:job-command-line job)) 0)
           (nshell.domain.execution:job-command-line job))
      (let ((pipeline (nshell.domain.execution:job-pipeline job)))
        (if pipeline
            (format nil "~{~{~a~^ ~}~^ | ~}"
                    (mapcar #'nshell.domain.execution:command-to-list
                            (nshell.domain.execution:pipeline-commands pipeline)))
            ""))))

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
           (values pid :stopped nil))
          ((sb-posix:wifexited status)
           (values pid :exited (sb-posix:wexitstatus status)))
          ((sb-posix:wifsignaled status)
           (values pid :signaled (+ 128 (sb-posix:wtermsig status))))
          (t
           (values pid :unknown nil))))
    (sb-posix:syscall-error (condition)
      (let ((errno (sb-posix:syscall-errno condition)))
        (cond
          ((= errno sb-posix:echild)
           (values nil :no-child nil))
          ((= errno sb-posix:eintr)
           (values nil :interrupted nil))
          (t
           (error condition)))))))

(defun %wait-job-pgid (job job-id job-monitor)
  (let* ((pgid (nshell.domain.execution:job-pgid job))
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
             (complete-job ()
               (let ((status-code (or last-stage-status latest-status)))
                 (nshell.domain.job-control:monitor-update
                  job-monitor job-id :completed status-code))))
      (loop
        (multiple-value-bind (pid state status-code)
            (%wait-job-pgid-event pgid)
          (case state
            (:stopped
             (nshell.domain.job-control:monitor-update
              job-monitor job-id :stopped)
             (return job))
            ((:exited :signaled)
             (record-completion pid status-code)
             (when (and known-pids (null pending-pids))
               (return (complete-job))))
            (:no-child
             (return (complete-job)))
            (:interrupted)
            (:unknown)))))))

(defun %require-job (job-id command &optional (job-monitor *job-monitor*))
  (or (nshell.domain.job-control:monitor-find-job job-monitor job-id)
      (progn
        (format t "~a: no such job: ~a~%" command job-id)
        nil)))
