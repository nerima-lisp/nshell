(in-package #:nshell.infrastructure.acl)

(defun %make-pipeline-pipes (count)
  (let ((pipes nil) (complete nil))
    (unwind-protect
         (prog1
             (progn
               (loop repeat (max 0 (1- count))
                     do (push (multiple-value-list (sb-posix:pipe)) pipes))
               (nreverse pipes))
           (setf complete t))
      (unless complete (%close-pipeline-fds pipes)))))

(defun %close-pipeline-redirect-streams (redirect-streams)
  (dolist (stream redirect-streams)
    (ignore-errors (close stream))))

(defun %abort-pipeline (procs pipes)
  (%close-pipeline-fds pipes)
  (%terminate-pipeline-processes procs)
  (dolist (proc procs)
    (ignore-errors (sb-ext:process-close proc))))

(defun %prepare-pipeline (commands redirects)
  (let* ((count (length commands))
         (redirects (or redirects
                        (make-list count :initial-element nil))))
    (values redirects (%make-pipeline-pipes count))))

(defun %run-pipeline-command (cmd args input output error-output environment resolved-cmd
                              &key preserve-fds pgid)
  (if resolved-cmd
      (multiple-value-bind (read-fd write-fd) (sb-posix:pipe)
        (let ((proc nil) (error-stream nil) (complete nil))
          (unwind-protect
               (let ((helper (%resolve-external-command
                              "cl-process-kit-spawn" (sb-ext:posix-environ))))
                 (unless helper (error "cl-process-kit-spawn is unavailable"))
                 (setf error-stream (sb-sys:make-fd-stream
                                     read-fd :input t :element-type '(unsigned-byte 8)
                                     :auto-close t)
                       read-fd nil)
                 (setf proc
                       (sb-ext:run-program
                        helper
                        (append (list "--error-fd" (write-to-string write-fd)
                                      "--pgroup" (write-to-string (or pgid 0)))
                                (loop for fd in preserve-fds
                                      append (list "--pass" (write-to-string fd)))
                                (list "--" "/bin/sh" "-c"
                                      "kill -STOP $$; exec \"$@\""
                                      "nshell-pipeline" resolved-cmd)
                                args)
                        :input input :output output :error error-output
                        :wait nil :search nil :environment environment
                        :preserve-fds (cons write-fd preserve-fds)))
                 (sb-posix:close write-fd)
                 (setf write-fd nil)
                 (when (read-byte error-stream nil nil)
                   (error "Pipeline helper failed before exec"))
                 ;; The leader must stay alive until every stage has joined it.
                 (sb-ext:process-wait proc t)
                 (unless (and (eq :stopped (sb-ext:process-status proc))
                              (= (or pgid (sb-ext:process-pid proc))
                                 (sb-posix:getpgid (sb-ext:process-pid proc))))
                   (error "Pipeline stage did not reach its process-group barrier"))
                 (setf complete t)
                 proc)
            (unless complete
              (when proc
                (ignore-errors (sb-ext:process-kill proc sb-unix:sigkill))
                (ignore-errors (sb-ext:process-wait proc))
                (ignore-errors (sb-ext:process-close proc))))
            (when error-stream (close error-stream))
            (when read-fd (sb-posix:close read-fd))
            (when write-fd (sb-posix:close write-fd)))))
      (progn
        (format *error-output*
                "~a"
                (%external-command-not-found-message cmd))
        nil)))

(defun %run-synchronous-pipeline (procs pgid pipes pipefail-p)
  (flet ((finish-pipeline ()
           (when pgid (%send-process-group-signal pgid sb-unix:sigcont))
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
                                preserve-fds pgid)
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
      (unwind-protect
           (let* ((cmd (nshell.domain.parsing:command-node-command cmd-node))
                  (args (mapcar #'nshell.domain.parsing:arg-value
                                (nshell.domain.parsing:command-node-args cmd-node)))
                  (environment (%get-environment))
                  (resolved-cmd (%resolve-external-command cmd environment))
                  (wrapper-cmd (and wrapper-p
                                    resolved-cmd
                                    "/bin/sh"))
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
                                           :preserve-fds preserve-fds
                                           :pgid pgid))
                  redirect-streams)
               (setf started t)))
        (unless started
          (%close-new-redirect-streams redirect-streams previous-redirect-streams))
        (when input-pipe-stream
          (ignore-errors (close input-pipe-stream)))
        (when output-pipe-stream
          (ignore-errors (close output-pipe-stream)))))))

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
