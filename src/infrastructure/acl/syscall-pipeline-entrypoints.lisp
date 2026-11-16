(in-package #:nshell.infrastructure.acl)

(defun spawn-pipeline (commands &key redirects
                                (default-input t)
                                (default-output :stream)
                                preserve-fds
                                (pipefail-p nil)
                                after-spawn
                                stage-environments
                                skip-start-barrier-p)
  "Execute COMMANDS connected by OS-level pipes and return status values.

The first value is the pipeline exit code.  The second value is a list of
per-stage exit codes in source order."
  (multiple-value-bind (redirects pipes)
      (%prepare-pipeline commands redirects)
    (let ((skip-start-barrier-p
           (and skip-start-barrier-p (= 1 (length commands)) (null after-spawn)))
          (redirect-streams nil)
          (owned-procs nil)
          (complete nil))
      (unwind-protect
          (multiple-value-bind (procs pgid updated-streams stage-results)
              (%pipeline-spawn-loop
               commands pipes redirects redirect-streams
               :default-input default-input
               :default-output default-output
               :preserve-fds preserve-fds
               :after-spawn after-spawn
               :stage-environments stage-environments
               :skip-start-barrier-p skip-start-barrier-p)
            (setf redirect-streams updated-streams owned-procs procs)
            (multiple-value-prog1
                (if procs
                    (let ((last-stage (car (last stage-results))))
                      (multiple-value-bind (status statuses timed-out-p)
                          (%run-synchronous-pipeline
                           procs pgid pipes pipefail-p skip-start-barrier-p
                           (unless (integerp last-stage) last-stage))
                        (if (some #'integerp stage-results)
                            (let ((statuses
                                   (mapcar (lambda (stage)
                                             (if (integerp stage)
                                                 stage
                                               (process-exit-status-code stage)))
                                           stage-results)))
                              (values (if timed-out-p
                                          status
                                        (%pipeline-exit-status statuses pipefail-p))
                                      statuses))
                          (values status statuses))))
                  (values (%pipeline-exit-status stage-results pipefail-p)
                          stage-results))
              (setf complete t)))
        (unless complete (%abort-pipeline owned-procs pipes))
        (%close-pipeline-redirect-streams redirect-streams)
        (%close-pipeline-fds pipes)))))

(defun spawn-pipeline-async (commands &key redirects
                                        (default-input t)
                                        (default-output t)
                                        (start-p t)
                                        preserve-fds
                                        after-spawn
                                        stage-environments)
  "Return started processes and source-ordered process-or-127 stage results."
  (multiple-value-bind (redirects pipes)
      (%prepare-pipeline commands redirects)
    (let ((redirect-streams nil) (owned-procs nil) (complete nil))
      (unwind-protect
           (multiple-value-bind (procs pgid updated-streams stage-results)
               (%pipeline-spawn-loop
                commands pipes redirects redirect-streams
                :default-input default-input
                :default-output default-output
                :preserve-fds preserve-fds
                :after-spawn after-spawn
                :stage-environments stage-environments)
             (setf redirect-streams updated-streams owned-procs procs)
             (multiple-value-prog1
                 (progn
                   (%close-pipeline-fds pipes)
                   (when (and start-p pgid)
                     (process-continue-group pgid procs))
                   (values (reverse procs) stage-results))
               (setf complete t)))
        (unless complete (%abort-pipeline owned-procs pipes))
        (%close-pipeline-redirect-streams redirect-streams)
        (%close-pipeline-fds pipes)))))
