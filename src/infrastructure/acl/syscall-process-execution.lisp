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
       (ensure-timeout-seconds *external-command-timeout*
                              "external command timeout")))

(defmacro %with-foreground-process-group-if ((pgid) &body body)
  (let ((pgid-var (gensym "PGID-")))
    `(let ((,pgid-var ,pgid))
       (if ,pgid-var
           (%with-foreground-process-group ,pgid-var ,@body)
           (progn ,@body)))))

(defun run-external-exec (cmd args)
  "Execute CMD with ARGS for the exec builtin.

FD-backed standard streams pass through directly; other output streams are
drained under the normal foreground timeout policy."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (%report-external-command-not-found cmd)
          (return-from run-external-exec 127))
        (let ((proc (%spawn-in-own-process-group
                     resolved-cmd args environment
                     *standard-input* (%external-output-target *standard-output*)
                     :error (%external-output-target *error-output*))))
          (if proc
              (let* ((pid (process-pid proc))
                     (pgid (and (integerp pid) (plusp pid) pid))
                     (timeout (%foreground-external-command-timeout)))
                (%with-foreground-process-group-if (pgid)
                  (values
                   (%wait-process-with-output
                    proc *standard-output* timeout
                    (lambda ()
                      (format *error-output* "~a"
                              (%external-command-timeout-message cmd timeout))
                      124)
                    *error-output*))))
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
        (let ((proc (%spawn-in-own-process-group
                     resolved-cmd args environment *standard-input*
                     (%external-output-target *standard-output*)
                     :error (if *redirected-stderr*
                                (%external-output-target *error-output*)
                                :output))))
          (if proc
              (let* ((pid (process-pid proc))
                     (pgid (and (integerp pid) (plusp pid) pid))
                     (timeout (%foreground-external-command-timeout)))
                (%with-foreground-process-group-if (pgid)
                  (%wait-process-with-output
                   proc *standard-output* timeout
                   (lambda ()
                     (format *error-output* "~a"
                             (%external-command-timeout-message cmd timeout))
                     124)
                   *error-output*)))
              1)))
    (error (err)
      (format *error-output* "nshell: ~a: ~a~%" cmd err)
      1)))

