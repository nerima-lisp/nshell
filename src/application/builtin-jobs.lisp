(in-package #:nshell.application)

(defun %parse-job-id (args)
  (if args
      (or (parse-integer (first args) :junk-allowed t) 0)
      0))

(defun %builtin-fg (context args)
  (let ((job (fg (%parse-job-id args)
                 (shell-context-dispatcher context)
                 (shell-context-process-registry context)
                 (shell-context-terminal-fns context)
                 (shell-context-job-monitor context))))
    (values nil (if job 0 1))))

(defun %builtin-bg (context args)
  (let ((job (bg (%parse-job-id args)
                 (shell-context-dispatcher context)
                 (shell-context-job-monitor context))))
    (values nil (if job 0 1))))

(defun %builtin-jobs (context args)
  (declare (ignore args))
  (values
   (with-output-to-string (out)
     (let ((*standard-output* out))
       (jobs (shell-context-job-monitor context))))
   0))

(defun %builtin-disown (context args)
  (let ((job-monitor (shell-context-job-monitor context)))
    (if args
        (let ((job-id (%parse-job-id args)))
          (if (nshell.domain.job-control:monitor-find-job job-monitor job-id)
              (progn
                (disown job-id job-monitor)
                (values nil 0))
              (values (format nil "disown: job [~d] not found~%" job-id) 1)))
        (%builtin-usage "disown" "disown job-id"))))
