(in-package #:nshell.infrastructure.acl)

(defparameter *external-command-timeout* nil
  "Maximum seconds for synchronous external commands. NIL disables the timeout.")

(defun process-exit-status-code (proc)
  "Return shell-compatible exit status for an SBCL process."
  (let ((code (sb-ext:process-exit-code proc)))
    (if (and code (eq (sb-ext:process-status proc) :signaled))
        (+ 128 code)
        (or code 0))))

(defun %wait-process-exit-with-timeout (proc timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second))))
        (sleep-seconds 0.0001))
    (loop while (and (sb-ext:process-alive-p proc)
                     (< (get-internal-real-time) deadline))
          for remaining-seconds = (/ (- deadline (get-internal-real-time))
                                     (float internal-time-units-per-second))
          do (sleep (min sleep-seconds (max 0 remaining-seconds)))
             (setf sleep-seconds (min 0.01 (* 2 sleep-seconds))))
    (unless (sb-ext:process-alive-p proc)
      (ignore-errors (sb-ext:process-wait proc))
      t)))

(defun %terminate-process (proc)
  (when proc
    (let* ((pid (sb-ext:process-pid proc))
           (actual-pgid (and (integerp pid) (plusp pid)
                             (ignore-errors (sb-posix:getpgid pid))))
           (owns-process-group-p (and (integerp actual-pgid)
                                      (plusp actual-pgid) (= pid actual-pgid))))
      (flet ((terminate (signal)
               (if owns-process-group-p
                   (ignore-errors (%send-process-group-signal pid signal))
                   (when (sb-ext:process-alive-p proc)
                     (ignore-errors (sb-ext:process-kill proc signal))))))
        (terminate sb-unix:sigterm)
        (%wait-process-exit-with-timeout proc 0.5)
        (terminate sb-unix:sigkill)
        (ignore-errors (sb-ext:process-wait proc))))))

(defmacro %with-process-output-copiers ((copiers) &body body)
  "Run BODY while guaranteeing that process output COPIERS are joined."
  `(unwind-protect (progn ,@body)
     (%join-process-output-copiers ,copiers)))

(defun %wait-process-with-copiers (proc copiers timeout-seconds success-fn timeout-fn)
  (%with-process-output-copiers (copiers)
    (if (or (null timeout-seconds)
            (%wait-process-exit-with-timeout proc timeout-seconds))
        (progn (sb-ext:process-wait proc) (funcall success-fn))
        (progn (%terminate-process proc) (funcall timeout-fn)))))

(defun %wait-process-with-copiers-or-stop (proc copiers success-fn stop-fn)
  "Wait for PROC while allowing a stopped process to be continued."
  (loop
    (sb-ext:process-wait proc t)
    (if (eq (sb-ext:process-status proc) :stopped)
        (let ((decision (funcall stop-fn)))
          (unless (eq decision :continue-wait) (return decision))
          (sleep 0.05))
        (return (%with-process-output-copiers (copiers)
                  (funcall success-fn))))))

(defun %wait-process-with-output (proc output timeout-seconds timeout-fn)
  (let ((copier (%start-process-output-copier proc output)))
    (%wait-process-with-copiers proc (list copier) timeout-seconds
      (lambda () (values (process-exit-status-code proc) nil))
      (lambda () (values (funcall timeout-fn) t)))))

(defun spawn-async (cmd args &key redirects)
  "Spawn CMD with ARGS asynchronously. Returns the process or NIL on error."
  (let ((redirect-streams nil))
    (flet ((register (stream) (push stream redirect-streams)))
      (unwind-protect
           (handler-case
               (let ((input (%resolve-input-redirect redirects #'register))
                     (output (%resolve-output-redirect redirects #'register)))
                 (multiple-value-bind (resolved-cmd environment)
                     (%prepare-external-command cmd)
                   (when resolved-cmd
                     (%spawn-in-own-process-group resolved-cmd args environment
                                                  input output))))
             (error (err)
               (format *error-output* "nshell: ~a: ~a~%" cmd err)
               nil))
        (dolist (stream redirect-streams) (ignore-errors (close stream)))))))
