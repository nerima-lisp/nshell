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
           (%wait-pipeline-with-output
            procs
            *external-command-timeout*
            (lambda ()
              (format *error-output*
                      "nshell: pipeline timed out after ~a seconds~%"
                      *external-command-timeout*)
              124)
            pipefail-p)))
    (%close-pipeline-fds pipes)
    (if pgid
        (%with-foreground-process-group pgid (function finish-pipeline))
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

(defun %pipeline-exit-status (statuses pipefail-p)
  (if pipefail-p
      (or (find-if (lambda (status) (not (zerop status))) statuses)
          0)
      (or (car (last statuses)) 0)))

(defun %wait-pipeline-processes (procs &optional (pipefail-p nil))
  (let ((statuses nil))
    (dolist (proc procs)
      (sb-ext:process-wait proc)
      ;; PROCS is stored with the last stage at the head. PUSH restores
      ;; source order, which is the order pipefail must inspect.
      (push (process-exit-status-code proc) statuses))
    (%pipeline-exit-status statuses pipefail-p)))

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

(defun %terminate-pipeline-processes (procs)
  (when procs
    (let* ((first-proc (car (last procs)))
           (pgid (sb-ext:process-pid first-proc))
           ;; A failed SETPGID leaves a pipeline in the callers process group.
           ;; Only signal a group after verifying that its leader is the child.
           (actual-pgid (and (integerp pgid)
                             (plusp pgid)
                             (ignore-errors (sb-posix:getpgid pgid))))
           (owns-process-group-p (and (integerp actual-pgid)
                                      (plusp actual-pgid)
                                      (= pgid actual-pgid))))
      (flet ((terminate (signal)
               (if owns-process-group-p
                   (ignore-errors (%send-process-group-signal pgid signal))
                   (dolist (proc procs)
                     (when (sb-ext:process-alive-p proc)
                       (ignore-errors (sb-ext:process-kill proc signal)))))))
        (terminate sb-unix:sigterm)
        (%wait-pipeline-exit-with-timeout procs 0.5)
        (terminate sb-unix:sigkill)
        (dolist (proc procs)
          (ignore-errors (sb-ext:process-wait proc)))))))

(defun %wait-pipeline-exit-with-timeout (procs timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second)))))
    (loop while (and (some #'sb-ext:process-alive-p procs)
                     (< (get-internal-real-time) deadline))
          do (sleep 0.01))
    (not (some #'sb-ext:process-alive-p procs))))

(defun %wait-pipeline-with-output (procs timeout-seconds timeout-fn pipefail-p)
  (let ((copier (%start-process-output-copier (car procs) *standard-output*)))
    (unwind-protect
         (if (or (null timeout-seconds)
                 (%wait-pipeline-exit-with-timeout procs timeout-seconds))
             (progn
               (prog1 (%wait-pipeline-processes procs pipefail-p)
                 (%join-process-output-copiers (list copier))))
             (progn
               (%terminate-pipeline-processes procs)
               (%join-process-output-copiers (list copier))
               (funcall timeout-fn)))
      (%join-process-output-copiers (list copier)))))

(defun %pipeline-spawn-loop (commands pipes redirects redirect-streams
                             &key (default-input t) default-output preserve-fds
                               after-spawn pgid-assign-fn error-sentinel)
  "Iterate over COMMANDS, spawning each as a pipeline stage connected via PIPES.
Returns (values procs pgid redirect-streams error-p) where ERROR-P is the
value of ERROR-SENTINEL when a spawn fails, or NIL on success.

DEFAULT-OUTPUT  — forwarded to %spawn-pipeline-stage as :default-output.
PGID-ASSIGN-FN  — called as (funcall pgid-assign-fn proc pgid) after each
                  successful spawn to assign the process to a group.  It must
                  return the (possibly updated) PGID to use for subsequent
                  stages.
ERROR-SENTINEL  — value stored as the error indicator on failure (e.g. 127 for
                  sync pipelines, T for async pipelines)."
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

(defun spawn-pipeline (commands &key redirects
                                  (default-input t)
                                  (default-output :stream)
                                  preserve-fds
                                  (pipefail-p nil)
                                  after-spawn)
  "Execute COMMANDS connected by OS-level pipes and return the last exit code."
  (multiple-value-bind (redirects pipes)
      (%prepare-pipeline commands redirects)
    (let ((redirect-streams nil))
      (unwind-protect
           (multiple-value-bind (procs pgid updated-streams spawn-error-code)
               (%pipeline-spawn-loop
                commands
                pipes
                redirects
                redirect-streams
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
                   spawn-error-code)
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
                commands
                pipes
                redirects
                redirect-streams
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
