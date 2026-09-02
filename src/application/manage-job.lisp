(in-package #:nshell.application)

(defun %set-acl-foreground-pgid (pgid)
  (let ((symbol (find-symbol "*FOREGROUND-PGID*" "NSHELL.INFRASTRUCTURE.ACL")))
    (when symbol
      (setf (symbol-value symbol) (or pgid 0))))
  (values))

(defun %continue-process-group (pgid)
  (nshell.infrastructure.acl:kill-process (- pgid) :sigcont))

(defmacro %with-terminal-foreground-pgroup (pgid &body body)
  (let ((previous (gensym "PREVIOUS-FOREGROUND-PGID-")))
    `(let ((,previous
             (ignore-errors
               (funcall
                (symbol-function
                 'nshell.infrastructure.acl:get-foreground-pgroup)))))
       (unwind-protect
            (progn
              (ignore-errors
                (funcall
                 (symbol-function
                  'nshell.infrastructure.acl:set-foreground-pgroup)
                 ,pgid))
              ,@body)
         (ignore-errors
           (funcall
            (symbol-function
             'nshell.infrastructure.acl:set-foreground-pgroup)
            (or ,previous (%shell-process-group-id))))))))

(defun fg (job-id &optional (job-monitor *job-monitor*))
  "Move JOB-ID to the foreground, wait for it, then restore the shell PGID."
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
                 (%with-terminal-foreground-pgroup
                   pgid
                   (funcall (symbol-function '%wait-job-pgid)
                            job job-id job-monitor)))
            (setf *foreground-job-pgid* nil)
            (%set-acl-foreground-pgid nil)))
        job))))

(defun bg (job-id &optional (job-monitor *job-monitor*))
  "Continue JOB-ID in the background."
  (let ((job (%require-job job-id job-monitor)))
    (when job
      (let ((pgid (nshell.domain.execution:job-control-pgid job)))
        (when pgid
          (%continue-process-group pgid))
        (nshell.domain.job-control:background-job job-monitor job-id)
        job))))

(defun disown (job-id &optional (job-monitor *job-monitor*))
  "Remove JOB-ID from the job monitor."
  (nshell.domain.job-control:monitor-remove-job job-monitor job-id))

(defun %shell-process-group-id ()
  (or *shell-pgid*
      (setf *shell-pgid* (nshell.infrastructure.acl:current-process-id))))

(defun %foreground-signal-target-pgid ()
  (let ((shell-pgid (%shell-process-group-id))
        (pgid (or *foreground-job-pgid*
                  (ignore-errors (nshell.infrastructure.acl:get-foreground-pgroup)))))
    (when (and shell-pgid
               pgid
               (nshell.domain.execution:valid-process-group-id-p pgid)
               (/= pgid shell-pgid))
      pgid)))


(defun %job-wait-event-from-observation (pid state detail)
  (case state
    (:stopped
     (%make-job-wait-event pid :stopped nil))
    (:exited
     (%make-job-wait-event pid :exited detail))
    (:signaled
     (%make-job-wait-event pid :signaled (+ 128 detail)))
    ((:no-child :interrupted)
     (%make-job-wait-event nil state nil))
    (otherwise
     (%make-job-wait-event pid :unknown nil))))

(defun %wait-job-pgid-event (pgid)
  (multiple-value-bind (pid state detail)
      (nshell.infrastructure.acl:wait-job (- pgid) :untraced t)
    (%job-wait-event-from-observation pid state detail)))

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
(defun signal-job (job-id signal &optional (job-monitor *job-monitor*))
  "Send SIGNAL to JOB-ID and synchronize the monitor after a successful signal."
  (labels ((record-signal-state ()
                                (let ((current-job
                                       (nshell.domain.job-control:monitor-find-job
                                        job-monitor job-id)))
                                  (when (and current-job
                                             (not (nshell.domain.execution:job-completed-p
                                                   current-job)))
                                    (cond
                                     ((nshell.infrastructure.acl:process-stop-signal-p
                                       signal)
                                      (nshell.domain.job-control:suspend-job
                                       job-monitor job-id nil))
                                     ((and (nshell.infrastructure.acl:process-continue-signal-p
                                           signal)
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
                (nshell.infrastructure.acl:kill-process (- pgid) signal)
                (setf signaled-p t))
              (dolist (pid pids)
                (nshell.infrastructure.acl:kill-process pid signal)
                (setf signaled-p t)))
          (when signaled-p
            (record-signal-state))
          job)))))
(defun %complete-waited-job (job-id process-registry job job-monitor processes)
  (%wait-job-processes processes)
  (let ((exit-code (%job-process-exit-code job processes)))
    (nshell.domain.job-control:complete-job
     job-monitor job-id exit-code)
    (remhash job-id process-registry)
    (values job exit-code)))

(defun wait-for-job (job-id process-registry
                       &optional (job-monitor *job-monitor*))
  "Wait for JOB-ID using the registered SBCL process objects.

The process registry is shared with the background reaper.  Waiting through
the same process objects avoids a second waitpid consumer and preserves the
exit status when the reaper has already completed the domain job."
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
             (%complete-waited-job
              job-id process-registry job job-monitor processes)))))))
(defun %job-process-exit-code (job processes)
  (let ((statuses
          (mapcar
           (lambda (process)
             (nshell.infrastructure.acl:process-exit-status-code process))
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
  (dolist (process processes)
    (when process
      (sb-ext:process-wait process)))
  processes)
(defun %job-process-list (entry)
  (cond
    ((null entry) nil)
    ((listp entry) entry)
    (t (list entry))))
