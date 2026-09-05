(in-package #:nshell.infrastructure.acl)

(defun %pipeline-exit-status (statuses pipefail-p)
  (if pipefail-p
      (or (find-if (lambda (status) (not (zerop status))) statuses)
          0)
      (or (car (last statuses)) 0)))

(defun %wait-pipeline-processes (procs &optional (pipefail-p nil))
  (let ((statuses nil))
    (dolist (proc procs)
      (sb-ext:process-wait proc)
      (push (process-exit-status-code proc) statuses))
    (values (%pipeline-exit-status statuses pipefail-p)
            statuses)))

(defun %terminate-pipeline-processes (procs)
  (when procs
    (let* ((first-proc (car (last procs)))
           (pgid (sb-ext:process-pid first-proc))
           (owns-process-group-p
            (and (integerp pgid)
                 (plusp pgid)
                 (some (lambda (proc)
                         (and (sb-ext:process-alive-p proc)
                              (eql pgid (ignore-errors
                                          (sb-posix:getpgid
                                           (sb-ext:process-pid proc))))))
                       procs))))
      (flet ((terminate (signal)
               (if owns-process-group-p
                   (ignore-errors (%send-process-group-signal pgid signal))
                   (dolist (proc procs)
                     (when (sb-ext:process-alive-p proc)
                       (ignore-errors (sb-ext:process-kill proc signal)))))))
        (terminate sb-unix:sigterm)
        (%wait-pipeline-exit-with-timeout procs 0.5)
        (terminate sb-unix:sigkill)
        (dolist (proc procs)
          (ignore-errors (sb-ext:process-wait proc)))))))

(defun %wait-pipeline-exit-with-timeout (procs timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second)))))
    (loop while (and (some #'sb-ext:process-alive-p procs)
                     (< (get-internal-real-time) deadline))
          do (sleep 0.01))
    (not (some #'sb-ext:process-alive-p procs))))

(defun %wait-pipeline-with-output (procs timeout-seconds timeout-fn pipefail-p)
  (let ((copiers nil)
        (deadline (when timeout-seconds
                    (+ (get-internal-real-time)
                       (round (* timeout-seconds internal-time-units-per-second))))))
    (unwind-protect
         (progn
           (push (%start-process-output-copier (car procs) *standard-output*) copiers)
           (push (%start-stream-copier (sb-ext:process-error (car procs))
                                      *standard-output*
                                      "nshell pipeline error copier")
                 copiers)
           (setf copiers (remove nil copiers))
           (loop while (or (some #'sb-ext:process-alive-p procs)
                           (some #'sb-thread:thread-alive-p copiers))
                 do (when (and deadline (>= (get-internal-real-time) deadline))
                      (%terminate-pipeline-processes procs)
                      (let ((code (funcall timeout-fn)))
                        (return-from %wait-pipeline-with-output
                          (values code (list code)))))
                    (sleep 0.01))
           (%wait-pipeline-processes procs pipefail-p))
      ;; Descendants can retain a pipe after every owned stage has exited.
      ;; Do not let their missing EOF turn a timeout into an unbounded join.
      (dolist (copier copiers)
        (when (sb-thread:thread-alive-p copier)
          (sb-thread:terminate-thread copier))
        (%join-stream-copier copier)))))
