(in-package #:nshell.application)

(defun %finish-external-pipeline-process
    (process stdout-buffer stderr-buffer redirect-plan command pgid)
  (let ((copiers
          (%start-external-process-copiers
           process stdout-buffer stderr-buffer))
        (timeout
          (nshell.infrastructure.acl::%foreground-external-command-timeout)))
    (flet ((collect-output (status)
             (%finish-external-process-output
              stdout-buffer stderr-buffer redirect-plan status))
           (continue-stopped-process ()
             (%continue-stopped-external-process pgid))
           (report-timeout ()
             (format *error-output*
                     "nshell: ~a: timed out after ~a seconds~%"
                     command timeout)))
      (unwind-protect
           (if (null timeout)
               (nshell.infrastructure.acl::%wait-process-with-copiers-or-stop
                process copiers
                (lambda ()
                  (collect-output
                   (nshell.infrastructure.acl:process-exit-status-code
                    process)))
                #'continue-stopped-process)
               (nshell.infrastructure.acl::%wait-process-with-copiers
                process copiers timeout
                (lambda ()
                  (collect-output
                   (nshell.infrastructure.acl:process-exit-status-code
                    process)))
                (lambda ()
                  (report-timeout)
                  (collect-output 124))))
        (when (and process
                   (sb-ext:process-alive-p process)
                   (not (eq (sb-ext:process-status process) :stopped)))
          (ignore-errors (sb-ext:process-wait process)))))))
