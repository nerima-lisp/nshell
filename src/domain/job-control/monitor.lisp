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

(defun monitor-update (monitor job-id state &optional exit-code)
  (let ((job (gethash job-id (job-monitor-jobs monitor))))
    (when job
      (nshell.domain.execution:job-state-transition job state)
      (when exit-code
        (setf (nshell.domain.execution:job-exit-code job) exit-code))
      job)))

(defun monitor-jobs (monitor)
  (loop for v being the hash-values of (job-monitor-jobs monitor) collect v))

(defun monitor-entries (monitor)
  "Return all tracked jobs as (id . job) alist."
  (loop for k being the hash-keys of (job-monitor-jobs monitor)
        for v being the hash-values of (job-monitor-jobs monitor)
        collect (cons k v)))

(defun monitor-find-job (monitor job-id)
  (gethash job-id (job-monitor-jobs monitor)))

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
      (monitor-update monitor job-id :running)
      job)))
