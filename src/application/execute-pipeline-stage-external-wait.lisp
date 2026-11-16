(in-package #:nshell.application)

(defvar *output-captures* nil
  "The string streams collecting a running command's output, innermost first,
as (STREAM . :STDOUT) or (STREAM . :STDERR). :SUBSTITUTION marks where a
command substitution starts; what is captured inside it is not shell output.")

(defun flush-pending-captured-output (stdout stderr)
  "Write what the active captures outside every command substitution hold to
STDOUT and STDERR, outermost first, and empty them. Only a caller about to
unwind past the captures calls this: the --json deadline and its exec."
  (let* ((captures *output-captures*)
         (barrier (position :substitution captures :from-end t))
         (outside (if barrier (nthcdr (1+ barrier) captures) captures)))
    (dolist (capture (reverse outside))
      (write-string (get-output-stream-string (car capture))
                    (if (eq (cdr capture) :stderr) stderr stdout)))))

(defun %call-capturing-standard-output (thunk)
  "Call THUNK with *STANDARD-OUTPUT* bound to a string stream and return what
it wrote, as WITH-OUTPUT-TO-STRING does, keeping the stream on
*OUTPUT-CAPTURES* while THUNK runs."
  (let ((stream (make-string-output-stream)))
    (let ((*standard-output* stream)
          (*output-captures* (acons stream :stdout *output-captures*)))
      (funcall thunk))
    (get-output-stream-string stream)))

(defun %finish-external-pipeline-process
    (process stdout-buffer stderr-buffer redirect-plan command pgid)
  (let ((*output-captures*
          (let ((captures (acons stdout-buffer :stdout *output-captures*)))
            (if stderr-buffer (acons stderr-buffer :stderr captures) captures)))
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
        (when (and process
                   (nshell.infrastructure.acl:process-alive-p process)
                   (not (eq (nshell.infrastructure.acl:process-status process) :stopped)))
          (ignore-errors (nshell.infrastructure.acl:process-wait process)))))))
