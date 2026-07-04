(in-package #:nshell.domain.job-control)

(defstruct (job-monitor (:constructor %make-job-monitor ()))
  (jobs (make-hash-table) :type hash-table)
  (next-id 1 :type integer))

(defun make-job-monitor ()
  (%make-job-monitor))

(defun monitor-add-job (monitor job)
  (let ((id (job-monitor-next-id monitor)))
    (setf (gethash id (job-monitor-jobs monitor)) job)
    (incf (job-monitor-next-id monitor))
    id))

(defun monitor-add-background-job (monitor pids command-line)
  (when pids
    (let ((job (nshell.domain.execution:make-job 0 nil)))
      (setf (nshell.domain.execution:job-pids job) (copy-list pids)
            (nshell.domain.execution:job-pgid job) (first pids)
            (nshell.domain.execution:job-command-line job) command-line
            (nshell.domain.execution:job-background-p job) t)
      (nshell.domain.execution:job-state-transition job :running)
      (monitor-add-job monitor job))))

(defun %monitor-job (monitor job-id)
  (gethash job-id (job-monitor-jobs monitor)))

(defun %record-terminal-exit-code (job exit-code)
  (when (and exit-code
             (nshell.domain.execution:job-completed-p job))
    (setf (nshell.domain.execution:job-exit-code job) exit-code))
  job)

(defun %transition-monitored-job (job state exit-code)
  (nshell.domain.execution:job-state-transition job state)
  (%record-terminal-exit-code job exit-code))

(defun monitor-update (monitor job-id state &optional exit-code)
  (let ((job (%monitor-job monitor job-id)))
    (when job
      (%transition-monitored-job job state exit-code))))

(defun monitor-jobs (monitor)
  (loop for v being the hash-values of (job-monitor-jobs monitor) collect v))

(defun monitor-entries (monitor)
  "Return all tracked jobs as (id . job) alist."
  (loop for k being the hash-keys of (job-monitor-jobs monitor)
        for v being the hash-values of (job-monitor-jobs monitor)
        collect (cons k v)))

(defun monitor-find-job (monitor job-id)
  (%monitor-job monitor job-id))

(defun monitor-remove-job (monitor job-id)
  (remhash job-id (job-monitor-jobs monitor)))

(defun suspend-job (monitor job-id kont)
  (declare (ignore kont))
  (monitor-update monitor job-id :stopped))

(defun resume-job (monitor job-id)
  (monitor-update monitor job-id :running))

(defun foreground-job (monitor job-id)
  (let ((job (monitor-find-job monitor job-id)))
    (when job
      (setf (nshell.domain.execution:job-background-p job) nil)
      (monitor-update monitor job-id :running)
      job)))

(defun background-job (monitor job-id)
  (let ((job (monitor-find-job monitor job-id)))
    (when job
      (setf (nshell.domain.execution:job-background-p job) t)
      (monitor-update monitor job-id :background)
      job)))
