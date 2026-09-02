(in-package #:nshell.application)

(defvar *job-monitor* (nshell.domain.job-control:make-job-monitor))
(defvar *shell-pgid* nil)
(defvar *foreground-job-pgid* nil)

(define-value-struct job-listing
    ((id 0)
     (status "")
     (command ""))
  :constructor %allocate-job-listing)

(define-value-struct job-wait-event
    ((pid nil)
     (state nil)
     (status-code nil)))
