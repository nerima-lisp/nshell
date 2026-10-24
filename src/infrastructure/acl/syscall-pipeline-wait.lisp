(in-package #:nshell.infrastructure.acl)

(defun %pipeline-exit-status (statuses pipefail-p)
  (if pipefail-p
      (or (find-if (lambda (status) (not (zerop status))) statuses)
          0)
      (or (car (last statuses)) 0)))

(defun %wait-pipeline-processes (procs &optional (pipefail-p nil))
  (let ((statuses nil))
    (dolist (proc procs)
      (process-wait proc)
      (push (process-exit-status-code proc) statuses))
    (values (%pipeline-exit-status statuses pipefail-p)
            statuses)))
(defun %pipeline-process-group-owned-p (procs pgid)
  (and (integerp pgid)
       (plusp pgid)
       (some (lambda (proc)
               (and (process-alive-p proc)
                    (eql pgid
                         (ignore-errors
                           (sb-posix:getpgid (process-pid proc))))))
             procs)))

(defun %terminate-pipeline-processes (procs)
  (when procs
    (let* ((first-proc (car (last procs)))
           (pgid (process-pid first-proc)))
      (labels
          ((terminate (signal)
             (if (%pipeline-process-group-owned-p procs pgid)
                 (ignore-errors (%send-process-group-signal pgid signal))
                 (dolist (proc procs)
                   (when (process-alive-p proc)
                     (ignore-errors
                       (kill-process (process-pid proc) signal)))))))
        (terminate sb-unix:sigterm)
        (%wait-pipeline-exit-with-timeout procs 0.5)
        (terminate sb-unix:sigkill)
        (%wait-pipeline-exit-with-timeout procs 0.5)
        (dolist (proc procs)
          (unless (process-alive-p proc)
            (ignore-errors (process-wait proc))))))))

(defun %wait-pipeline-exit-with-timeout (procs timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second)))))
    (loop while (and (some #'process-alive-p procs)
                     (< (get-internal-real-time) deadline))
          do (sleep 0.01))
    (not (some #'process-alive-p procs))))

(defun %wait-pipeline-with-output (procs timeout-seconds timeout-fn pipefail-p)
  (let ((copiers nil))
    (unwind-protect
         (progn
           (push (%start-process-output-copier (car procs) *standard-output*) copiers)
           (push (%start-stream-copier (process-error (car procs))
                                      *standard-output*
                                      "nshell pipeline error copier")
                 copiers)
           (setf copiers (remove nil copiers))
           (multiple-value-bind (timed-out-p output-complete-p)
               (%wait-processes-with-output-copiers
                procs copiers timeout-seconds
                (lambda () (%terminate-pipeline-processes procs)))
             (unless output-complete-p
               (if timed-out-p
                   (format *error-output*
                           "nshell: pipeline output capture incomplete after timeout~%")
                   (error "Pipeline output copier did not reach EOF")))
             (if timed-out-p
                 (let ((code (funcall timeout-fn)))
                   (values code (list code)))
                 (%wait-pipeline-processes procs pipefail-p))))
      (dolist (copier copiers)
        (when (sb-thread:thread-alive-p copier)
          (ignore-errors (sb-thread:terminate-thread copier)))
        (%join-stream-copier copier)))))
