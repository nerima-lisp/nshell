(in-package #:nshell.infrastructure.acl)

(defun %foreground-external-command-timeout ()
  "Return the timeout to apply to a foreground external command's wait: NIL
when *STANDARD-OUTPUT* is connected to a real interactive terminal right now
-- the user is present and can Ctrl-C a runaway command, so nshell must not
kill a long-lived foreground program like an editor or SSH session -- and
*EXTERNAL-COMMAND-TIMEOUT* otherwise, i.e. whenever this command's output is
redirected to a file/pipe or nshell itself is non-interactive. Per-command
redirects already rebind *STANDARD-OUTPUT*, so this naturally covers `cmd >
file` typed at an interactive prompt too."
  (and (not (interactive-stream-p *standard-output*))
       *external-command-timeout*))

(defmacro %with-foreground-process-group-if ((pgid) &body body)
  (let ((pgid-var (gensym "PGID-")))
    `(let ((,pgid-var ,pgid))
       (if ,pgid-var
           (%with-foreground-process-group ,pgid-var ,@body)
           (progn ,@body)))))

(defun run-external-exec (cmd args)
  "Execute CMD with ARGS for the exec builtin.

Standard streams pass through directly and noninteractive execution uses the
normal foreground timeout policy."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (%report-external-command-not-found cmd)
          (return-from run-external-exec 127))
        (let ((proc (%spawn-in-own-process-group
                     resolved-cmd args environment
                     *standard-input* *standard-output*
                     :error *error-output*)))
          (if proc
              (let* ((pid (sb-ext:process-pid proc))
                     (pgid (and (integerp pid) (plusp pid) pid))
                     (timeout (%foreground-external-command-timeout)))
                (%with-foreground-process-group-if (pgid)
                  (if (or (null timeout)
                          (%wait-process-exit-with-timeout proc timeout))
                      (progn
                        (sb-ext:process-wait proc)
                        (process-exit-status-code proc))
                      (progn
                        (%terminate-process proc)
                        (format *error-output* "~a"
                                (%external-command-timeout-message cmd timeout))
                        124))))
              1)))
    (error (err)
      (format *error-output* "exec: ~a: ~a~%" cmd err)
      1)))

(defun run-external (cmd args)
  "Execute CMD with ARGS synchronously, printing output. Returns exit code."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (%report-external-command-not-found cmd)
          (return-from run-external 127))
        (let ((proc (%spawn-external-command resolved-cmd args environment
                                             :input *standard-input*
                                             :output :stream)))
          (if proc
              (let* ((pid (sb-ext:process-pid proc))
                     (pgid (and (integerp pid) (plusp pid) pid))
                     (timeout (%foreground-external-command-timeout)))
                (when pgid
                  (%assign-process-group pid pgid))
                (%with-foreground-process-group-if (pgid)
                  (%wait-process-with-output
                   proc *standard-output* timeout
                   (lambda ()
                     (format *error-output* "~a"
                             (%external-command-timeout-message cmd timeout))
                     124))))
              1)))
    (error (err)
      (format *error-output* "nshell: ~a: ~a~%" cmd err)
      1)))

(defun run-external-capture (cmd args)
  "Execute CMD with ARGS synchronously, capturing stdout for command
substitution. Returns the captured output and a shell exit code."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (return-from run-external-capture
            (values (%external-command-not-found-message cmd) 127)))
        (let* ((separate-stderr-p (and *redirected-stderr* t))
               (forward-stdin-p (and *redirected-stdin* t))
               (input (and forward-stdin-p *standard-input*)))
          (process-kit:with-process
              (process (process-kit:spawn
                        resolved-cmd args
                        :input (and input :stream)
                        :output :stream
                        :error (if separate-stderr-p :stream :output)
                        :environment (or environment
                                         (copy-list (sb-ext:posix-environ)))))
            (let ((pid (process-kit:process-id process)))
              (unwind-protect
                   (progn
                     (when (and (integerp pid) (plusp pid))
                       (setf *foreground-pgid* pid))
                     (let ((result (process-kit:communicate
                                    process
                                    :input input
                                    :timeout *external-command-timeout*
                                    :on-timeout :return)))
                       (when separate-stderr-p
                         (write-string (process-kit:process-result-stderr result)
                                       *error-output*))
                       (if (process-kit:process-result-timed-out-p result)
                           (values (%external-command-timeout-message
                                    cmd *external-command-timeout*)
                                   124)
                           (values (process-kit:process-result-stdout result)
                                   (%process-result-shell-exit result)))))
                (setf *foreground-pgid* 0))))))
    (error (err)
      (values (format nil "nshell: ~a: ~a~%" cmd err) 1))))
