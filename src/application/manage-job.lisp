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

(defun %run-terminal-command (context command args)
  (let ((process (nshell.infrastructure.acl::%spawn-terminal-command command args)))
    (unless process
      (return-from %run-terminal-command
        (values (format nil "nshell: ~a: command not found~%" command) 127)))
    (let ((pgid (sb-ext:process-pid process)))
      (unwind-protect
           (progn
             (setf *foreground-job-pgid* pgid)
             (%set-acl-foreground-pgid pgid)
             (%with-terminal-foreground-pgroup pgid
               (sb-ext:process-kill process sb-unix:sigcont :pid)
               (if (eq :stopped (%wait-terminal-processes (list process)))
                   (let* ((monitor (shell-context-job-monitor context))
                          (id (nshell.domain.job-control:monitor-add-background-job
                               monitor (list pgid)
                               (%string-join (cons command args) " ")
                               :pipefail-p (shell-context-pipefail-p context))))
                     (%store-shell-process-registry-entry context id process)
                     (nshell.domain.job-control:suspend-job monitor id nil)
                     (values nil (+ 128 sb-unix:sigtstp)))
                   (values nil (nshell.infrastructure.acl:process-exit-status-code
                                process)))))
        (setf *foreground-job-pgid* nil)
        (%set-acl-foreground-pgid nil)))))

(defun %run-terminal-pipeline (context commands redirects)
  (let ((processes (nshell.infrastructure.acl:spawn-pipeline-async
                    commands :redirects redirects :start-p nil)))
    (unless processes
      (return-from %run-terminal-pipeline (values nil 127 (list 127))))
    (let ((pgid (sb-ext:process-pid (first processes)))
          (retained-p nil))
      (unwind-protect
           (progn
             (setf *foreground-job-pgid* pgid)
             (%set-acl-foreground-pgid pgid)
             (%with-terminal-foreground-pgroup pgid
               (dolist (process processes)
                 (sb-ext:process-kill process sb-unix:sigcont :pid))
               (if (eq :stopped (%wait-terminal-processes processes))
                   (let* ((monitor (shell-context-job-monitor context))
                          (id (nshell.domain.job-control:monitor-add-background-job
                               monitor (mapcar #'sb-ext:process-pid processes)
                               (%string-join
                                (mapcar (lambda (command)
                                          (%string-join
                                           (cons (nshell.domain.parsing:command-node-command command)
                                                 (%line-command-args command)) " "))
                                        commands)
                                " | ")
                               :pipefail-p (shell-context-pipefail-p context))))
                     (%store-shell-process-registry-entry context id processes)
                     (nshell.domain.job-control:suspend-job monitor id nil)
                     (setf retained-p t)
                     (values nil (+ 128 sb-unix:sigtstp)
                             (mapcar (lambda (process)
                                       (if (eq :stopped (sb-ext:process-status process))
                                           (+ 128 sb-unix:sigtstp)
                                           (nshell.infrastructure.acl:process-exit-status-code process)))
                                     processes)))
                   (let ((statuses (mapcar #'nshell.infrastructure.acl:process-exit-status-code
                                           processes)))
                     (values nil
                             (if (shell-context-pipefail-p context)
                                 (or (find-if-not #'zerop statuses) 0)
                                 (car (last statuses)))
                             statuses)))))
        (setf *foreground-job-pgid* nil)
        (%set-acl-foreground-pgid nil)
        (unless retained-p
          (nshell.infrastructure.acl::%abort-pipeline (reverse processes) nil))))))

(defun fg (job-id &optional (job-monitor *job-monitor*) process-registry)
  "Move JOB-ID to the foreground, wait for it, then restore the shell PGID."
  (let ((job (%require-job job-id job-monitor)))
    (when job
      (let ((pgid (nshell.domain.execution:job-control-pgid job)))
        (when pgid
          (setf *foreground-job-pgid* pgid)
          (unwind-protect
               (progn
                 (%set-acl-foreground-pgid pgid)
                 (nshell.domain.job-control:foreground-job job-monitor job-id)
                 (%with-terminal-foreground-pgroup
                   pgid
                   (%continue-process-group pgid)
                   (let ((processes (and process-registry
                                         (%job-process-list
                                          (gethash job-id process-registry)))))
                     (if processes
                         (return-from fg
                           (%wait-registered-foreground-job
                            job job-id job-monitor process-registry processes))
                         (funcall (symbol-function '%wait-job-pgid)
                                  job job-id job-monitor)))))
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
