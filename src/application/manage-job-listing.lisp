(in-package #:nshell.application)

(defun make-job-listing (id status command)
  (unless (and (integerp id) (plusp id))
    (error "Job listing id must be a positive integer: ~s" id))
  (unless (stringp status)
    (error "Job listing status must be a string: ~s" status))
  (unless (stringp command)
    (error "Job listing command must be a string: ~s" command))
  (%allocate-job-listing id status command))

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
