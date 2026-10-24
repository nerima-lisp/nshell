(in-package #:nshell.infrastructure.acl)

(defparameter *external-command-timeout* +default-external-command-timeout+
  "Maximum seconds for synchronous non-interactive external commands.")

(defun %spawn-terminal-command (command args)
  (multiple-value-bind (resolved environment) (%prepare-external-command command)
    (when resolved
      ;; Hold user code until the caller hands this process group the terminal.
      (%run-pipeline-command command args *standard-input* t t environment resolved))))

(defun process-pid (process)
  (cond
    ((pty-process-p process) (pty-process-pid process))
    ((native-process-p process) (native-process-pid process))
    (t (sb-ext:process-pid process))))

(defun process-status (process)
  (cond
    ((pty-process-p process) (pty-process-status process))
    ((native-process-p process) (native-process-status process))
    (t (sb-ext:process-status process))))

(defun %wait-sbcl-process (process &optional check-for-stopped)
  ;; SBCL's wake pipe can close an already closed FD on successive CONT/STOP
  ;; notifications. Serve stream copiers without installing that wake pipe.
  (loop for state = (sb-ext:process-status process)
        while (or (eq state :running)
                  (and (eq state :stopped) (not check-for-stopped)))
        do (sb-sys:serve-all-events 0.01)
        finally (return (if (eq state :stopped)
                            process
                            (sb-ext:process-wait process)))))

(defun process-wait (process &optional check-for-stopped)
  (cond
    ((pty-process-p process) (pty-process-wait process))
    ((native-process-p process) (%wait-native-process process check-for-stopped))
    (t (%wait-sbcl-process process check-for-stopped))))

(defun process-continue (process)
  (cond
    ((pty-process-p process) (pty-process-continue process))
    ((native-process-p process)
     (let ((sent (%native-process-kill process sb-unix:sigcont)))
       (when (and sent (eq :stopped (native-process-status process)))
         (%mark-native-process-running process))
       sent))
    (t
     (sb-sys:without-interrupts
       (sb-thread:with-mutex (sb-impl::*active-processes-lock*)
         (multiple-value-bind (sent errno)
             (sb-ext:process-kill process sb-unix:sigcont :pid)
           (when (and sent (eq :stopped (sb-impl::process-%status process)))
             (setf (sb-impl::process-%status process) :running
                   (sb-impl::process-%exit-code process) nil))
           (values sent errno)))))))
(defun process-continue-group (pgid processes)
  "Continue PGID and refresh its registered process statuses under the waitpid lock."
  (sb-sys:without-interrupts
    (sb-thread:with-mutex (sb-impl::*active-processes-lock*)
      (handler-case
          (funcall (symbol-function 'kill-process) (- pgid) :sigcont)
        (sb-posix:syscall-error (condition)
          (unless (= (sb-posix:syscall-errno condition) sb-posix:esrch)
            (error condition))))
      (dolist (process processes)
        (cond
          ((native-process-p process)
           (%mark-native-process-running process))
          ((not (pty-process-p process))
           (when (eq :stopped (sb-impl::process-%status process))
             (setf (sb-impl::process-%status process) :running
                   (sb-impl::process-%exit-code process) nil)))))
      t)))

(defun process-alive-p (process)
  (cond
    ((pty-process-p process)
     (member (pty-process-status process) '(:running :stopped)))
    ((native-process-p process) (%native-process-alive-p process))
    (t (sb-ext:process-alive-p process))))

(defun process-exit-status-code (proc)
  (cond
    ((pty-process-p proc)
     (progn
       (unless (member (pty-process-status proc) '(:exited :signaled))
         (pty-process-wait proc))
       (or (pty-process-exit-status proc) 0)))
    ((native-process-p proc) (%native-process-exit-status-code proc))
    (t
     (let ((code (sb-ext:process-exit-code proc)))
       (if (and code (eq (process-status proc) :signaled))
           (+ 128 code)
           (or code 0))))))

(defun %wait-process-exit-with-timeout (proc timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second))))
        (sleep-seconds 0.0001))
    (loop while (and (process-alive-p proc)
                     (< (get-internal-real-time) deadline))
          for remaining-seconds = (/ (- deadline (get-internal-real-time))
                                     (float internal-time-units-per-second))
          do (sleep (min sleep-seconds (max 0 remaining-seconds)))
             (setf sleep-seconds (min 0.01 (* 2 sleep-seconds))))
    (unless (process-alive-p proc)
      (ignore-errors (process-wait proc))
      t)))

(defun %terminate-process (proc &optional expected-pgid)
  (when proc
    (let ((pid (process-pid proc)))
      (flet ((terminate (signal)
               (let* ((alive-p (ignore-errors (process-alive-p proc)))
                      (status (ignore-errors (process-status proc)))
                      (signalable-p (and alive-p
                                         (member status '(:running :stopped))))
                      (actual-pgid (and (integerp pid) (plusp pid)
                                        (ignore-errors (sb-posix:getpgid pid))))
                      (owns-process-group-p
                        (and signalable-p
                             (or (null expected-pgid)
                                 (eql expected-pgid actual-pgid))
                             (integerp actual-pgid)
                             (plusp actual-pgid) (= pid actual-pgid))))
                 ;; Signal the process group only when this process created
                 ;; it; otherwise a timeout could kill the shell's own
                 ;; foreground group or an unrelated group reused by the OS.
                 ;; Recheck status before every signal so SIGKILL cannot target
                 ;; a later process generation after SIGTERM exits this one.
                 (if owns-process-group-p
                     (ignore-errors (%send-process-group-signal pid signal))
                     (when signalable-p
                       (ignore-errors (kill-process pid signal)))))))
        (terminate sb-unix:sigterm)
        (%wait-process-exit-with-timeout proc 0.5)
        (terminate sb-unix:sigkill)
        (%wait-process-exit-with-timeout proc 0.5)
        (unless (process-alive-p proc)
          (ignore-errors (process-wait proc)))))))

(defmacro %with-process-output-copiers ((copiers) &body body)
  "Run BODY while guaranteeing that process output COPIERS are joined."
  `(unwind-protect (progn ,@body)
     (%join-process-output-copiers ,copiers)))

(defun %wait-processes-with-output-copiers (procs copiers timeout-seconds terminate-fn)
  (let ((deadline (when timeout-seconds
                    (+ (funcall *process-output-clock*)
                       (round (* timeout-seconds internal-time-units-per-second)))))
        (timed-out-p nil)
        (copiers-joined-p nil))
    (unwind-protect
         (progn
           (loop while (or (some #'process-alive-p procs)
                           (some #'sb-thread:thread-alive-p copiers))
                 do (when (and deadline
                               (>= (funcall *process-output-clock*) deadline))
                      (setf timed-out-p t)
                      (funcall terminate-fn)
                      (let ((drain-deadline
                              (+ (funcall *process-output-clock*)
                                 (round (* 0.5 internal-time-units-per-second)))))
                        (loop while (some #'sb-thread:thread-alive-p copiers)
                              do (when (>= (funcall *process-output-clock*)
                                           drain-deadline)
                                   (dolist (copier copiers)
                                     (when (sb-thread:thread-alive-p copier)
                                       (ignore-errors
                                         (sb-thread:terminate-thread copier))))
                                   (return))
                                 (sb-sys:serve-all-events 0.01)))
                      (return))
                    (sb-sys:serve-all-events 0.01))
           (let ((copier-results (mapcar #'%join-stream-copier copiers)))
             (setf copiers-joined-p t)
             (values timed-out-p
                     (every (lambda (result) (eq :eof result)) copier-results))))
      (unless copiers-joined-p
        (dolist (copier copiers)
          (when (sb-thread:thread-alive-p copier)
            (ignore-errors (sb-thread:terminate-thread copier)))
          (%join-stream-copier copier))))))

(defun %wait-process-with-copiers (proc copiers timeout-seconds success-fn timeout-fn)
  (let ((copiers (remove nil copiers)))
    (multiple-value-bind (timed-out-p output-complete-p)
        (%wait-processes-with-output-copiers
         (list proc) copiers timeout-seconds
         (lambda ()
           (when (process-alive-p proc)
             (%terminate-process proc))))
      (unless output-complete-p
        (if timed-out-p
            (format *error-output*
                    "nshell: output capture incomplete after timeout~%")
            (error "Process output copier did not reach EOF")))
      (if timed-out-p
          (funcall timeout-fn)
          (progn
            (process-wait proc)
            (funcall success-fn))))))

(defun %wait-process-with-copiers-or-stop (proc copiers success-fn stop-fn)
  "Wait for PROC while allowing a stopped process to be continued."
  (loop
    (process-wait proc t)
    (if (eq (process-status proc) :stopped)
        (let ((decision (funcall stop-fn)))
          (unless (eq decision :continue-wait) (return decision))
          (sleep 0.05))
        (return (funcall (%with-process-output-copiers (copiers)
                           success-fn))))))

(defun %wait-process-with-output (proc output timeout-seconds timeout-fn
                                 &optional error-output)
  (let ((copiers nil))
    (unwind-protect
         (progn
           (push (%start-process-output-copier proc output) copiers)
           (let ((error-stream (process-error proc)))
             (when (and error-stream
                        (not (eq error-stream (process-output proc))))
               (push (%start-stream-copier error-stream error-output
                                          "nshell process error copier")
                     copiers)))
           (%wait-process-with-copiers proc copiers timeout-seconds
             (lambda () (values (process-exit-status-code proc) nil))
             (lambda () (values (funcall timeout-fn) t))))
      (dolist (copier copiers)
        (when (and copier (sb-thread:thread-alive-p copier))
          (sb-thread:terminate-thread copier))
        (%join-stream-copier copier))
      (process-close proc))))

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
                     (multiple-value-bind (process input-transferred-p)
                         (%spawn-in-own-process-group
                          resolved-cmd args environment input output
                          :input-source-owned-p
                          (not (null (member input redirect-streams :test #'eq))))
                       (when input-transferred-p
                         (setf redirect-streams
                               (remove input redirect-streams :test #'eq)))
                       process))))
             (error (err)
               (format *error-output* "nshell: ~a: ~a~%" cmd err)
               nil))
        (dolist (stream redirect-streams) (ignore-errors (close stream)))))))
