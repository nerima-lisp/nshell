(in-package #:nshell.domain.job-control)

(defstruct (job-monitor (:constructor make-job-monitor ())
                        (:copier nil))
  (jobs-table (make-hash-table) :type hash-table)
  (next-id-int 1 :type integer)
  (job-history-list nil :type list))

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

(defun %monitor-job (monitor job-id)
  (gethash job-id (%monitor-jobs-table monitor)))

(defun %remember-job (monitor job-id)
  (setf (job-monitor-job-history-list monitor)
        (cons job-id
              (remove job-id (job-monitor-job-history-list monitor)
                      :test #'=))))

(defun %forget-job (monitor job-id)
  (setf (job-monitor-job-history-list monitor)
        (remove job-id (job-monitor-job-history-list monitor)
                :test #'=)))

(defun %monitor-job-history (monitor)
  (let ((history
          (remove-if-not (lambda (job-id)
                           (%monitor-job monitor job-id))
                         (job-monitor-job-history-list monitor))))
    (setf (job-monitor-job-history-list monitor) history)
    history))

(defun %active-job-p (monitor job-id)
  (let ((job (%monitor-job monitor job-id)))
    (and job
         (not (nshell.domain.execution:job-completed-p job)))))

(defun %active-job-history (monitor)
  (remove-if-not (lambda (job-id)
                  (%active-job-p monitor job-id))
                (%monitor-job-history monitor)))

(defun %monitor-job-ids (monitor)
  (sort (loop for job-id being the hash-keys of (%monitor-jobs-table monitor)
              collect job-id)
        #'<))

(defun monitor-add-job (monitor job)
  (let ((id (%allocate-monitor-id monitor)))
    (%store-monitor-job monitor id job)
    (%remember-job monitor id)
    id))

(defun monitor-add-background-job (monitor pids command-line &key (pipefail-p nil))
  (when pids
    (let ((job (nshell.domain.execution:make-job 0 nil)))
      (nshell.domain.execution:job-register-background-processes
       job pids command-line :pipefail-p pipefail-p)
      (monitor-add-job monitor job))))

(defun %record-terminal-exit-code (job exit-code)
  (nshell.domain.execution:job-record-terminal-exit-code job exit-code))

(defun %transition-monitored-job (job state exit-code)
  (nshell.domain.execution:job-state-transition job state)
  (%record-terminal-exit-code job exit-code))

(defun monitor-update (monitor job-id state &optional exit-code)
  (let ((job (%monitor-job monitor job-id)))
    (when job
      (%transition-monitored-job job state exit-code)
      (unless (nshell.domain.execution:job-completed-p job)
        (%remember-job monitor job-id))
      job)))

(defun monitor-current-job-id (monitor)
  "Return the most recently active job ID, or NIL when none exists."
  (first (%active-job-history monitor)))

(defun monitor-previous-job-id (monitor)
  "Return the previously active job ID, or NIL when none exists."
  (second (%active-job-history monitor)))

(defun %parse-job-spec-id (text)
  (handler-case
      (let ((id (parse-integer text :junk-allowed nil)))
        (and id (plusp id) id))
    (parse-error () nil)
    (type-error () nil)))

(defun %job-spec-id (monitor job-spec)
  (labels ((matching-command-job-id (needle mode)
             (when (plusp (length needle))
               (find-if
                (lambda (job-id)
                  (let ((job (%monitor-job monitor job-id)))
                    (and job
                         (%active-job-p monitor job-id)
                         (let ((command
                                 (nshell.domain.execution:job-command-display-string
                                  job)))
                           (ecase mode
                             (:prefix
                              (and (<= (length needle) (length command))
                                   (string= needle command
                                            :end2 (length needle))))
                             (:substring
                              (not (null (search needle command)))))))))
                (%active-job-history monitor)))))
    (cond
      ((null job-spec)
       (monitor-current-job-id monitor))
      ((integerp job-spec)
       (and (plusp job-spec) job-spec))
      ((stringp job-spec)
       (cond
         ((or (string= job-spec "+")
              (string= job-spec "%+")
              (string= job-spec "%%"))
          (monitor-current-job-id monitor))
         ((or (string= job-spec "-")
              (string= job-spec "%-"))
          (monitor-previous-job-id monitor))
         ((and (plusp (length job-spec))
               (char= (char job-spec 0) #\%))
          (let ((body (subseq job-spec 1)))
            (cond
              ((and (plusp (length body))
                    (char= (char body 0) #\?))
               (matching-command-job-id (subseq body 1) :substring))
              ((plusp (length body))
               (let ((numeric-id (%parse-job-spec-id body)))
                 (if numeric-id
                     numeric-id
                     (matching-command-job-id body :prefix))))
              (t nil))))
         (t
          (%parse-job-spec-id job-spec))))
      (t nil))))

(defun monitor-resolve-job-spec (monitor job-spec)
  "Resolve JOB-SPEC to an existing job ID, or NIL when it is invalid.

JOB-SPEC accepts an integer ID, a bare numeric string, %N, %+,
%%, +, -, %-, %TEXT for a command prefix, and %?TEXT for a command
substring. An omitted spec selects the current active job."
  (let ((job-id (%job-spec-id monitor job-spec)))
    (when (and job-id (%monitor-job monitor job-id))
      job-id)))

(defun monitor-map-jobs (monitor function)
  "Call FUNCTION with each existing public job id and job from an ordered id snapshot."
  (dolist (job-id (%monitor-job-ids monitor))
    (let ((job (%monitor-job monitor job-id)))
      (when job
        (funcall function job-id job)))))

(defun monitor-find-job (monitor job-id)
  (%monitor-job monitor job-id))

(defun monitor-remove-job (monitor job-id)
  (let ((removed (remhash job-id (%monitor-jobs-table monitor))))
    (when removed
      (%forget-job monitor job-id))
    removed))

(defun suspend-job (monitor job-id kont)
  (declare (ignore kont))
  (monitor-update monitor job-id :stopped))

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
