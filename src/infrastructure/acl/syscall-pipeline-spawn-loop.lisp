(in-package #:nshell.infrastructure.acl)

(defun %pipeline-spawn-loop (commands pipes redirects redirect-streams
                             &key (default-input t) default-output preserve-fds
                               after-spawn stage-environments
                               skip-start-barrier-p)
  "Return processes in reverse order and source-ordered process-or-status entries."
  (let ((count (length commands))
        (procs nil)
        (stage-results nil)
        (pgid nil)
        (complete nil))
    (unwind-protect
         (progn
           (loop for index from 0 below count
                 for cmd-node in commands
                 for stage-redirects = (nth index redirects)
                 for prev-pipe = (and (plusp index) (nth (1- index) pipes))
                 for next-pipe = (and (< index (1- count)) (nth index pipes))
                 do (let ((proc nil))
                      (handler-case
                          (multiple-value-bind (process updated-streams)
                              (%spawn-pipeline-stage
                               cmd-node stage-redirects prev-pipe next-pipe redirect-streams
                               :default-input default-input
                               :default-output default-output
                               :preserve-fds preserve-fds
                               :pgid pgid
                               :stage-environment (nth index stage-environments)
                               :skip-start-barrier-p skip-start-barrier-p)
                            (setf redirect-streams updated-streams
                                  proc process))
                        (error (err)
                          (format *error-output* "nshell: ~a: ~a~%"
                                  (nshell.domain.parsing:command-node-command cmd-node)
                                  err)))
                      (if proc
                          (progn
                            (push proc procs)
                            (push proc stage-results)
                            (unless pgid (setf pgid (process-pid proc))))
                          (progn
                            (push 127 stage-results)
                            (when (and prev-pipe (first prev-pipe))
                              (sb-posix:close (first prev-pipe))
                              (setf (first prev-pipe) nil))
                            (when (and next-pipe (second next-pipe))
                              (sb-posix:close (second next-pipe))
                              (setf (second next-pipe) nil))))))
           (when after-spawn (funcall after-spawn))
           (setf complete t)
           (values procs pgid redirect-streams (nreverse stage-results)))
      (unless complete
        (%abort-pipeline procs pipes)
        (%close-pipeline-redirect-streams redirect-streams)))))
