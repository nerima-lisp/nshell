(in-package #:nshell.application)

(defvar *abandoned-process-output-function* nil
  "NIL, or a function of the stdout and stderr text an external command had
written when a non-local exit abandoned its wait. The --json runner binds it so
a run stopped at its deadline still reports the output produced so far.")

(defun %report-abandoned-process-output (stdout-buffer stderr-buffer)
  (when *abandoned-process-output-function*
    (funcall *abandoned-process-output-function*
             (get-output-stream-string stdout-buffer)
             (if stderr-buffer (get-output-stream-string stderr-buffer) ""))))

(defun %call-capturing-standard-output (thunk)
  "Call THUNK with *STANDARD-OUTPUT* bound to a string stream and return what
it wrote, as WITH-OUTPUT-TO-STRING does. When a non-local exit abandons THUNK,
hand what it wrote to *ABANDONED-PROCESS-OUTPUT-FUNCTION*."
  (let ((stream (make-string-output-stream))
        (finished-p nil))
    (unwind-protect
         (progn
           (let ((*standard-output* stream))
             (funcall thunk))
           (setf finished-p t)
           (get-output-stream-string stream))
      (unless (or finished-p (null *abandoned-process-output-function*))
        (funcall *abandoned-process-output-function*
                 (get-output-stream-string stream) "")))))

(defun %finish-external-pipeline-process
    (process stdout-buffer stderr-buffer redirect-plan command pgid)
  (let ((finished-p nil)
        (copiers
          (%start-external-process-copiers
           process stdout-buffer stderr-buffer))
        (timeout
          (nshell.infrastructure.acl:%foreground-external-command-timeout)))
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
           (multiple-value-prog1
            (if (null timeout)
                (nshell.infrastructure.acl:%wait-process-with-copiers-or-stop
                 process copiers
                 (lambda ()
                   (collect-output
                    (nshell.infrastructure.acl:process-exit-status-code
                     process)))
                 #'continue-stopped-process)
                (nshell.infrastructure.acl:%wait-process-with-copiers
                 process copiers timeout
                 (lambda ()
                   (collect-output
                    (nshell.infrastructure.acl:process-exit-status-code
                     process)))
                 (lambda ()
                   (report-timeout)
                   (collect-output 124))))
            (setf finished-p t))
        (unless finished-p
          (%report-abandoned-process-output stdout-buffer stderr-buffer))
        (when (and process
                   (nshell.infrastructure.acl:process-alive-p process)
                   (not (eq (nshell.infrastructure.acl:process-status process) :stopped)))
          (ignore-errors (nshell.infrastructure.acl:process-wait process)))))))
