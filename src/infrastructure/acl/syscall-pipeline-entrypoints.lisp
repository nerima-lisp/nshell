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
    (let ((redirect-streams nil) (owned-procs nil) (complete nil))
      (unwind-protect
           (multiple-value-bind (procs pgid updated-streams spawn-error-code)
               (%pipeline-spawn-loop
                commands pipes redirects redirect-streams
                :default-input default-input
                :default-output default-output
                :preserve-fds preserve-fds
                :after-spawn after-spawn
                :error-sentinel 127)
             (setf redirect-streams updated-streams owned-procs procs)
             (multiple-value-prog1
                 (if spawn-error-code
                     (progn
                       (%abort-pipeline procs pipes)
                       (values spawn-error-code (list spawn-error-code)))
                     (%run-synchronous-pipeline procs pgid pipes pipefail-p))
               (setf complete t)))
        (unless complete (%abort-pipeline owned-procs pipes))
        (%close-pipeline-redirect-streams redirect-streams)
        (%close-pipeline-fds pipes)))))

(defun spawn-pipeline-async (commands &key redirects
                                        (default-input t)
                                        (default-output t)
                                        (start-p t)
                                        preserve-fds
                                        after-spawn)
  "Execute COMMANDS connected by OS-level pipes asynchronously."
  (multiple-value-bind (redirects pipes)
      (%prepare-pipeline commands redirects)
    (let ((redirect-streams nil) (owned-procs nil) (complete nil))
      (unwind-protect
           (multiple-value-bind (procs pgid updated-streams spawn-error)
               (%pipeline-spawn-loop
                commands pipes redirects redirect-streams
                :default-input default-input
                :default-output default-output
                :preserve-fds preserve-fds
                :after-spawn after-spawn
                :error-sentinel t)
             (setf redirect-streams updated-streams owned-procs procs)
             (multiple-value-prog1
                 (if spawn-error
                     (progn
                       (%abort-pipeline procs pipes)
                       nil)
                     (progn
                       (%close-pipeline-fds pipes)
                       (when (and start-p pgid)
                         (%send-process-group-signal pgid sb-unix:sigcont))
                       (reverse procs)))
               (setf complete t)))
        (unless complete (%abort-pipeline owned-procs pipes))
        (%close-pipeline-redirect-streams redirect-streams)
        (%close-pipeline-fds pipes)))))
