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
                      (get-output-stream-string stderr-buffer)))
         (stdout-target
           (%external-process-redirect-plan-stdout-target redirect-plan))
         (stdout-mode
           (%external-process-redirect-plan-stdout-mode redirect-plan))
         (stderr-target
           (%external-process-redirect-plan-stderr-target redirect-plan))
         (stderr-mode
           (%external-process-redirect-plan-stderr-mode redirect-plan))
         (stdout-endpoint
           (%external-process-redirect-plan-stdout-endpoint redirect-plan))
         (stderr-endpoint
           (%external-process-redirect-plan-stderr-endpoint redirect-plan)))
    (if (%external-process-redirect-plan-merge-stderr-p redirect-plan)
        (values (%route-external-process-output
                 stdout-endpoint
                 stdout-target
                 stdout-mode
                 output
                 t)
                exit-code)
        (let ((returned-output
                (%route-external-process-output
                 stdout-endpoint
                 stdout-target
                 stdout-mode
                 output
                 t)))
          (%route-external-process-output
           stderr-endpoint
           stderr-target
           stderr-mode
           (or errout "")
           nil)
          (values returned-output exit-code)))))
