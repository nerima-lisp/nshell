(in-package #:nshell.infrastructure.acl)

(defun %make-pipeline-pipes (count)
  (loop repeat (max 0 (1- count))
        collect (multiple-value-list (sb-posix:pipe))))

(defun %close-pipeline-redirect-streams (redirect-streams)
  (dolist (stream redirect-streams)
    (ignore-errors (close stream))))

(defun %abort-pipeline (procs pipes)
  (%close-pipeline-fds pipes)
  (%terminate-pipeline-processes procs))

(defun %prepare-pipeline (commands redirects)
  (let* ((count (length commands))
         (redirects (or redirects
                        (make-list count :initial-element nil))))
    (values redirects (%make-pipeline-pipes count))))

(defun %assign-sync-pipeline-process-group (proc pgid)
  (let ((pid (and proc (sb-ext:process-pid proc))))
    (when (and (integerp pid) (plusp pid))
      (unless pgid
        (setf pgid pid))
      (%assign-process-group pid pgid)))
  pgid)

(defun %assign-async-pipeline-process-group (proc pgid)
  (when proc
    (let ((pid (sb-ext:process-pid proc)))
      (when (plusp pid)
        (unless pgid
          (setf pgid pid))
        (ignore-errors (set-process-group pid pgid)))))
  pgid)

(defun %run-pipeline-command (cmd args input output error-output environment resolved-cmd
                              &key preserve-fds)
  (if resolved-cmd
      (sb-ext:run-program resolved-cmd args
        :input input
        :output output
        :error error-output
        :wait nil
        :search nil
        :environment environment
        :preserve-fds preserve-fds)
      (progn
        (format *error-output*
                "~a"
                (%external-command-not-found-message cmd))
        nil)))

(defun %run-synchronous-pipeline (procs pgid pipes pipefail-p)
  (flet ((finish-pipeline ()
           (let ((timeout (%foreground-external-command-timeout)))
             (%wait-pipeline-with-output
              procs
              timeout
              (lambda ()
                (format *error-output*
                        "nshell: pipeline timed out after ~a seconds~%"
                        timeout)
                124)
              pipefail-p))))
    (%close-pipeline-fds pipes)
    (if pgid
        (%with-foreground-process-group pgid (finish-pipeline))
        (finish-pipeline))))

(defun %spawn-pipeline-stage (cmd-node stage-redirects prev-pipe next-pipe redirect-streams
                              &key (default-input t)
                                (default-output :stream)
                                preserve-fds)
  (let* ((wrapper-p
           (nshell.domain.parsing:redirects-require-shell-wrapper-p
            stage-redirects))
         ;; Keep pipe topology in the parent, but let the child wrapper apply
         ;; explicit redirects in source order when arbitrary descriptors are used.
         (stream-redirects (if wrapper-p nil stage-redirects))
         (previous-redirect-streams redirect-streams)
         (started nil))
    (multiple-value-bind (input output error-output
                          input-pipe-stream output-pipe-stream redirect-streams)
        (%pipeline-stage-streams stream-redirects prev-pipe next-pipe redirect-streams
                                 :default-input default-input
                                 :default-output default-output)
      (let* ((cmd (nshell.domain.parsing:command-node-command cmd-node))
             (args (mapcar #'nshell.domain.parsing:arg-value
                           (nshell.domain.parsing:command-node-args cmd-node)))
             (environment (%get-environment))
             (resolved-cmd (%resolve-external-command cmd environment))
             (wrapper-cmd (and wrapper-p
                               resolved-cmd
                               (%resolve-external-command "sh" environment)))
             (effective-cmd (if wrapper-p wrapper-cmd resolved-cmd))
             (effective-args
               (if wrapper-p
                   (list* "-c"
                          (nshell.domain.parsing:shell-redirect-script
                           stage-redirects)
                          "nshell-fd-wrapper"
                          resolved-cmd
                          args)
                   args)))
        (unwind-protect
             (multiple-value-prog1
                 (values
                  (progn
                    (%close-unused-next-pipe-writer next-pipe output-pipe-stream)
                    (%run-pipeline-command cmd
                                           effective-args
                                           input
                                           output
                                           error-output
                                           environment
                                           effective-cmd
                                           :preserve-fds preserve-fds))
                  redirect-streams)
               (setf started t))
          (unless started
            (%close-new-redirect-streams redirect-streams previous-redirect-streams))
          (when input-pipe-stream
            (ignore-errors (close input-pipe-stream)))
          (when output-pipe-stream
            (ignore-errors (close output-pipe-stream))))))))

(defun %close-pipeline-fds (pipes)
  (dolist (pipe pipes)
    (let ((read-fd (first pipe))
          (write-fd (second pipe)))
      (when (integerp read-fd)
        (ignore-errors (sb-posix:close read-fd))
        (setf (first pipe) nil))
      (when (integerp write-fd)
        (ignore-errors (sb-posix:close write-fd))
        (setf (second pipe) nil)))))
