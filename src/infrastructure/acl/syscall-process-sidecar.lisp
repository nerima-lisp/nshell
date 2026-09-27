(in-package #:nshell.infrastructure.acl)

(defparameter +sidecar-version-timeout-seconds+ 10
  "Maximum time allowed for the sidecar version probe.")

(defstruct (sidecar-handle
            (:constructor %make-sidecar-handle
                (process pgid input output error cleanup-state)))
  process
  pgid
  input
  output
  error
  cleanup-state)

(defun spawn-sidecar (command arguments &rest options)
  (let ((input (getf options :input))
        (output (getf options :output))
        (error-output (getf options :error)))
    (handler-case
        (multiple-value-bind (resolved-command environment)
            (%prepare-external-command command)
          (cond
            ((null resolved-command)
             (values nil :command-not-found))
            (t
             (let ((process (%spawn-in-own-process-group
                             resolved-command arguments environment
                             input output :error error-output)))
               (if process
                   (let* ((pid (ignore-errors (sb-ext:process-pid process)))
                          (process-input (if (eq input :stream)
                                             (sb-ext:process-input process)
                                             input))
                          (process-output (if (eq output :stream)
                                              (sb-ext:process-output process)
                                              output))
                          (process-error (if (eq error-output :stream)
                                             (sb-ext:process-error process)
                                             (if (eq error-output :output)
                                                 process-output
                                                 error-output))))
                     (values
                      (%make-sidecar-handle
                       process pid process-input process-output process-error
                       :running)
                      :started))
                   (values nil :spawn-failed))))))
      (error (condition)
        (values nil (list :spawn-error (princ-to-string condition)))))))

(defun sidecar-alive-p (handle)
  (and (sidecar-handle-p handle)
       (eq :running (sidecar-handle-cleanup-state handle))
       (ignore-errors
        (sb-ext:process-alive-p (sidecar-handle-process handle)))))

(defun %close-sidecar-stream (stream)
  (when (streamp stream)
    (ignore-errors (close stream))))

(defun stop-sidecar (handle)
  (if (or (not (sidecar-handle-p handle))
          (eq :stopped (sidecar-handle-cleanup-state handle)))
      nil
      (progn
        (setf (sidecar-handle-cleanup-state handle) :stopping)
        (%terminate-process (sidecar-handle-process handle))
        (%close-sidecar-stream (sidecar-handle-input handle))
        (%close-sidecar-stream (sidecar-handle-output handle))
        (%close-sidecar-stream (sidecar-handle-error handle))
        (ignore-errors
         (sb-ext:process-close (sidecar-handle-process handle)))
        (setf (sidecar-handle-cleanup-state handle) :stopped)
        t)))

(defun sidecar-exit-status (handle)
  (if (and (sidecar-handle-p handle)
           (not (sidecar-alive-p handle)))
      (ignore-errors (process-exit-status-code
                      (sidecar-handle-process handle)))
      nil))

(defun run-sidecar-version (command)
  (unless command
    (return-from run-sidecar-version (values nil :disabled)))
  (multiple-value-bind (handle status)
      (spawn-sidecar command '("--version")
                      :input nil :output :stream :error :output)
    (if (null handle)
        (values nil status)
        (let ((version nil)
              (reader
                (sb-thread:make-thread
                 (lambda ()
                   (setf version
                         (handler-case
                             (with-output-to-string (stream)
                               (loop for line = (read-line
                                                 (sidecar-handle-output handle)
                                                 nil nil)
                                     while line
                                     do (write-line line stream)))
                           (error (condition)
                             (declare (ignore condition))
                             nil)))
                   nil)
                 :name "nshell assistant sidecar version reader"))
              (deadline (+ (get-internal-real-time)
                           (round (* +sidecar-version-timeout-seconds+
                                     internal-time-units-per-second))))
              (timed-out-p nil))
          (loop while (sb-ext:process-alive-p
                       (sidecar-handle-process handle))
                do (if (>= (get-internal-real-time) deadline)
                       (progn (setf timed-out-p t) (return))
                       (sleep 0.01)))
          (unless timed-out-p
            (ignore-errors (sb-ext:process-wait (sidecar-handle-process handle))))
          (when timed-out-p
            (stop-sidecar handle))
          (ignore-errors
           (sb-thread:join-thread reader :default nil :timeout 0.2))
          (let ((exit-status (sidecar-exit-status handle)))
            (stop-sidecar handle)
          (values (and version
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    version))
                  (cond (timed-out-p :timeout)
                        ((zerop (or exit-status 1)) :ok)
                        (t :version-failed))))))))
