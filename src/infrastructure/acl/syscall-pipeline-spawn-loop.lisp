(in-package #:nshell.infrastructure.acl)

(defun %pipeline-spawn-loop (commands pipes redirects redirect-streams
                             &key (default-input t) default-output preserve-fds
                               after-spawn error-sentinel)
  "Iterate over COMMANDS, spawning each as a pipeline stage connected via PIPES.
Returns (values procs pgid redirect-streams error-p) where ERROR-P is the
value of ERROR-SENTINEL when a spawn fails, or NIL on success.

DEFAULT-OUTPUT is forwarded to %spawn-pipeline-stage as :default-output.
ERROR-SENTINEL is stored as the error indicator on failure."
  (let ((count (length commands))
        (procs nil)
        (pgid nil)
        (error-p nil)
        (complete nil))
    (unwind-protect
         (progn
           (loop for index from 0 below count
                 for cmd-node in commands
                 for stage-redirects = (nth index redirects)
                 for prev-pipe = (and (plusp index) (nth (1- index) pipes))
                 for next-pipe = (and (< index (1- count)) (nth index pipes))
                 while (null error-p)
                 do (handler-case
                        (multiple-value-bind (proc updated-streams)
                            (%spawn-pipeline-stage cmd-node
                                                   stage-redirects
                                                   prev-pipe
                                                   next-pipe
                                                   redirect-streams
                                                   :default-input default-input
                                                   :default-output default-output
                                                   :preserve-fds preserve-fds
                                                   :pgid pgid)
                          (setf redirect-streams updated-streams)
                          (if proc
                              (progn
                                (push proc procs)
                                (unless pgid (setf pgid (sb-ext:process-pid proc))))
                              (setf error-p error-sentinel)))
                      (error (err)
                        (setf error-p error-sentinel)
                        (format *error-output* "nshell: ~a: ~a~%"
                                (nshell.domain.parsing:command-node-command cmd-node)
                                err))))
           (when (and (null error-p) after-spawn)
             (handler-case (funcall after-spawn)
               (error (err)
                 (setf error-p error-sentinel)
                 (format *error-output* "nshell: pipeline: ~a~%" err))))
           (setf complete t)
           (values procs pgid redirect-streams error-p))
      (unless complete
        (%abort-pipeline procs pipes)
        (%close-pipeline-redirect-streams redirect-streams)))))
