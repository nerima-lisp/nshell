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
