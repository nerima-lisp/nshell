(in-package #:nshell.application)

(defun %write-process-output-target (target mode output)
  (when target
    (with-open-file (stream target
                            :direction :output
                            :if-exists mode
                            :if-does-not-exist :create)
      (write-string output stream))))

(defun %route-external-process-output
    (endpoint target mode output return-output-p)
  (cond
    ((eq endpoint :stdout)
     (if return-output-p
         output
         (write-string output *standard-output*)))
    ((eq endpoint :stderr)
     (write-string output *error-output*)
     nil)
    (target
     (%write-process-output-target target mode output)
     nil)
    (return-output-p
     output)
    (t
     nil)))

(defun %finish-external-process-output
    (stdout-buffer stderr-buffer redirect-plan exit-code)
  (let* ((output (get-output-stream-string stdout-buffer))
         (errout (and stderr-buffer
                      (get-output-stream-string stderr-buffer))))
    (%with-external-process-redirect-plan
        (redirect-plan
         :stdout-target stdout-target
         :stdout-mode stdout-mode
         :stderr-target stderr-target
         :stderr-mode stderr-mode
         :stdout-endpoint stdout-endpoint
         :stderr-endpoint stderr-endpoint
         :merge-stderr-p merge-stderr-p)
      (if merge-stderr-p
          (values (%route-external-process-output
                   stdout-endpoint stdout-target stdout-mode output t)
                  exit-code)
          (let ((returned-output
                  (%route-external-process-output
                   stdout-endpoint stdout-target stdout-mode output t)))
            (%route-external-process-output
             stderr-endpoint stderr-target stderr-mode (or errout "") nil)
            (values returned-output exit-code))))))
