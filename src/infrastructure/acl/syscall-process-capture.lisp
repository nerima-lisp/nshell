(in-package #:nshell.infrastructure.acl)

(defun run-external-capture (cmd args)
  "Execute CMD with ARGS synchronously, capturing stdout for command
substitution. Returns the captured output and a shell exit code. Stderr is
forwarded separately when the current command has redirected stderr; stdin is
forwarded only when command substitution explicitly permits it. The shared
process layer drains streams and applies the configured timeout."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (return-from run-external-capture
            (values (%external-command-not-found-message cmd) 127)))
        (let* ((separate-stderr-p (and *redirected-stderr* t))
               (input (and *redirected-stdin* *standard-input*))
               (timeout (ensure-timeout-seconds
                         *external-command-timeout*
                         "external command timeout"))
               (output (make-string-output-stream))
               (process (%spawn-in-own-process-group
                         resolved-cmd args environment input :stream
                         :error (if separate-stderr-p :stream :output)))
               (pid (process-pid process)))
          (unwind-protect
               (progn
                 (when (and (integerp pid) (plusp pid))
                   (setf *foreground-pgid* pid))
                 (multiple-value-bind (exit timed-out-p)
                     (%wait-process-with-output
                      process output timeout
                      (lambda ()
                        (format *error-output* "~a"
                                (%external-command-timeout-message cmd timeout))
                        124)
                      *error-output*)
                   (if timed-out-p
                       (values (%external-command-timeout-message cmd timeout)
                               exit)
                       (values (get-output-stream-string output) exit))))
            (setf *foreground-pgid* 0))))
    (error (err)
      (values (format nil "nshell: ~a: ~a~%" cmd err) 1))))
