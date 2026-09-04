(in-package #:nshell.infrastructure.acl)

(defun %pipeline-spawn-loop (commands pipes redirects redirect-streams
                             &key (default-input t) default-output preserve-fds
                               after-spawn pgid-assign-fn error-sentinel)
  "Iterate over COMMANDS, spawning each as a pipeline stage connected via PIPES.
Returns (values procs pgid redirect-streams error-p) where ERROR-P is the
value of ERROR-SENTINEL when a spawn fails, or NIL on success.

DEFAULT-OUTPUT is forwarded to %spawn-pipeline-stage as :default-output.
PGID-ASSIGN-FN is called as (funcall pgid-assign-fn proc pgid) after each
successful spawn to assign the process to a group. It returns the PGID for
subsequent stages.
ERROR-SENTINEL is stored as the error indicator on failure."
  (let ((count (length commands))
        (procs nil)
        (pgid nil)
        (error-p nil))
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
                                            :preserve-fds preserve-fds)
                   (setf redirect-streams updated-streams)
                   (if proc
                       (progn
                         (setf pgid (funcall pgid-assign-fn proc pgid))
                         (push proc procs))
                       (setf error-p error-sentinel)))
               (error (err)
                 (setf error-p error-sentinel)
                 (format *error-output* "nshell: ~a: ~a~%"
                         (nshell.domain.parsing:command-node-command cmd-node)
                         err))))
    (when (and (null error-p) after-spawn)
      (ignore-errors (funcall after-spawn)))
    (values procs pgid redirect-streams error-p)))
