(in-package #:nshell.domain.job-control)

(defstruct (job-monitor (:constructor %make-job-monitor ()))
  (jobs-table (make-hash-table) :type hash-table)
  (next-id-int 1 :type integer))

(defun make-job-monitor ()
  (%make-job-monitor))

(defun monitor-empty-p (monitor)
  (zerop (hash-table-count (job-monitor-jobs-table monitor))))

(defun monitor-next-job-id (monitor)
  (job-monitor-next-id-int monitor))

(defun %monitor-jobs-table (monitor)
  (job-monitor-jobs-table monitor))

(defun %monitor-next-id (monitor)
  (job-monitor-next-id-int monitor))

(defun %allocate-monitor-id (monitor)
  (let ((id (%monitor-next-id monitor)))
    (incf (job-monitor-next-id-int monitor))
    id))

(defun %store-monitor-job (monitor job-id job)
  (setf (gethash job-id (%monitor-jobs-table monitor)) job)
  job-id)

(defun %monitor-job-ids (monitor)
  (sort (loop for job-id being the hash-keys of (%monitor-jobs-table monitor)
              collect job-id)
        #'<))

(defun monitor-add-job (monitor job)
  (let ((id (%allocate-monitor-id monitor)))
    (%store-monitor-job monitor id job)))

(defun monitor-add-background-job (monitor pids command-line)
  (when pids
    (let ((job (nshell.domain.execution:make-job 0 nil)))
      (nshell.domain.execution:job-register-background-processes
       job pids command-line)
      (monitor-add-job monitor job))))

(defun %monitor-job (monitor job-id)
  (gethash job-id (%monitor-jobs-table monitor)))

(defun %record-terminal-exit-code (job exit-code)
  (nshell.domain.execution:job-record-terminal-exit-code job exit-code))

(defun %transition-monitored-job (job state exit-code)
  (nshell.domain.execution:job-state-transition job state)
  (%record-terminal-exit-code job exit-code))

(defun monitor-update (monitor job-id state &optional exit-code)
  (let ((job (%monitor-job monitor job-id)))
    (when job
      (%transition-monitored-job job state exit-code))))

(defun monitor-map-jobs (monitor function)
  "Call FUNCTION with each existing public job id and job from an ordered id snapshot."
  (dolist (job-id (%monitor-job-ids monitor))
    (let ((job (%monitor-job monitor job-id)))
      (when job
        (funcall function job-id job)))))

(defun monitor-find-job (monitor job-id)
  (%monitor-job monitor job-id))

(defun monitor-remove-job (monitor job-id)
  (remhash job-id (%monitor-jobs-table monitor)))

(defun suspend-job (monitor job-id kont)
  (declare (ignore kont))
  (monitor-update monitor job-id :stopped))

(defun resume-job (monitor job-id)
  (monitor-update monitor job-id :running))

(defun foreground-job (monitor job-id)
  (let ((job (monitor-find-job monitor job-id)))
    (when job
      (nshell.domain.execution:job-set-background-visible job nil)
      (monitor-update monitor job-id :running)
      job)))

(defun background-job (monitor job-id)
  (let ((job (monitor-find-job monitor job-id)))
    (when job
      (nshell.domain.execution:job-set-background-visible job t)
      (monitor-update monitor job-id :background)
      job)))

(defun complete-job (monitor job-id &optional (exit-code 0))
  (monitor-update monitor job-id :completed (or exit-code 0)))
