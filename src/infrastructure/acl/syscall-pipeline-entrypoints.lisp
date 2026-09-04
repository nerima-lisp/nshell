(in-package #:nshell.infrastructure.acl)

(defun spawn-pipeline (commands &key redirects
                                  (default-input t)
                                  (default-output :stream)
                                  preserve-fds
                                  (pipefail-p nil)
                                  after-spawn)
  "Execute COMMANDS connected by OS-level pipes and return status values.

The first value is the pipeline exit code.  The second value is a list of
per-stage exit codes in source order."
  (multiple-value-bind (redirects pipes)
      (%prepare-pipeline commands redirects)
    (let ((redirect-streams nil))
      (unwind-protect
           (multiple-value-bind (procs pgid updated-streams spawn-error-code)
               (%pipeline-spawn-loop
                commands pipes redirects redirect-streams
                :default-input default-input
                :default-output default-output
                :preserve-fds preserve-fds
                :after-spawn after-spawn
                :error-sentinel 127
                :pgid-assign-fn (function %assign-sync-pipeline-process-group))
             (setf redirect-streams updated-streams)
             (if spawn-error-code
                 (progn
                   (%abort-pipeline procs pipes)
                   (values spawn-error-code (list spawn-error-code)))
                 (%run-synchronous-pipeline procs pgid pipes pipefail-p)))
        (%close-pipeline-redirect-streams redirect-streams)
        (%close-pipeline-fds pipes)))))

(defun spawn-pipeline-async (commands &key redirects
                                        (default-input t)
                                        (default-output t)
                                        preserve-fds
                                        after-spawn)
  "Execute COMMANDS connected by OS-level pipes asynchronously."
  (multiple-value-bind (redirects pipes)
      (%prepare-pipeline commands redirects)
    (let ((redirect-streams nil))
      (unwind-protect
           (multiple-value-bind (procs pgid updated-streams spawn-error)
               (%pipeline-spawn-loop
                commands pipes redirects redirect-streams
                :default-input default-input
                :default-output default-output
                :preserve-fds preserve-fds
                :after-spawn after-spawn
                :error-sentinel t
                :pgid-assign-fn (function %assign-async-pipeline-process-group))
             (declare (ignore pgid))
             (setf redirect-streams updated-streams)
             (if spawn-error
                 (progn
                   (%abort-pipeline procs pipes)
                   nil)
                 (nreverse procs)))
        (%close-pipeline-redirect-streams redirect-streams)
        (%close-pipeline-fds pipes)))))
