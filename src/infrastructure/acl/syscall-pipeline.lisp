(in-package #:nshell.infrastructure.acl)

(defun %pipeline-output-mode (redirect)
  (if (member (car redirect) '(:>> :2>> :&>>))
      :append
      :supersede))

(defun %open-pipeline-output-redirect (redirect redirect-streams)
  (let ((stream (open (cdr redirect)
                      :direction :output
                      :if-exists (%pipeline-output-mode redirect)
                      :if-does-not-exist :create)))
    (values stream (cons stream redirect-streams))))

(defun %pipeline-output-streams (stage-redirects next-pipe redirect-streams
                                 &key default-output)
  (let ((output nil)
        (output-materialized-p nil)
        (output-pipe-stream nil)
        (error-output t))
    (labels ((current-output ()
               (unless output-materialized-p
                 (setf output
                       (cond
                         (next-pipe
                          (let ((fd (second next-pipe)))
                            (when fd
                              (setf output-pipe-stream
                                    (sb-sys:make-fd-stream fd
                                                           :output t
                                                           :buffering :line))
                              (setf (second next-pipe) nil)
                              output-pipe-stream)))
                         (t default-output))
                       output-materialized-p t))
               output))
      (dolist (redirect stage-redirects)
        (case (car redirect)
          ((:> :>>)
           (multiple-value-bind (stream streams)
               (%open-pipeline-output-redirect redirect redirect-streams)
             (setf output stream
                   output-materialized-p t
                   redirect-streams streams)))
          ((:2> :2>>)
           (multiple-value-bind (stream streams)
               (%open-pipeline-output-redirect redirect redirect-streams)
             (setf error-output stream
                   redirect-streams streams)))
          ((:&> :&>>)
           (multiple-value-bind (stream streams)
               (%open-pipeline-output-redirect redirect redirect-streams)
             (setf output stream
                   output-materialized-p t
                   error-output stream
                   redirect-streams streams)))
          (:2>&1
           (setf error-output (current-output)))))
      (values (current-output)
              error-output
              output-pipe-stream
              redirect-streams))))

(defun %pipeline-stage-streams (stage-redirects prev-pipe next-pipe redirect-streams
                                &key (default-output :stream))
  (let ((input-pipe-stream nil)
        (output-pipe-stream nil))
    (let* ((input-redirect (%input-redirect-spec stage-redirects))
           (input (cond
                   ((and input-redirect (eq (car input-redirect) :<))
                    (let ((stream (open (cdr input-redirect)
                                        :direction :input
                                        :if-does-not-exist :error)))
                      (push stream redirect-streams)
                      stream))
                   ((and input-redirect (eq (car input-redirect) :<<<))
                    (let ((stream (%here-string-stream (cdr input-redirect))))
                      (push stream redirect-streams)
                      stream))
                   ((and input-redirect (eq (car input-redirect) :<<))
                    (let ((stream (%here-document-stream (cdr input-redirect))))
                      (push stream redirect-streams)
                      stream))
                   (prev-pipe
                    (let ((fd (first prev-pipe)))
                      (when fd
                        (setf input-pipe-stream
                              (sb-sys:make-fd-stream fd
                                                     :input t
                                                     :buffering :line))
                        (setf (first prev-pipe) nil)
                        input-pipe-stream)))
                   (t t))))
      (multiple-value-bind (output error-output resolved-output-pipe-stream redirect-streams)
          (%pipeline-output-streams stage-redirects next-pipe redirect-streams
                                    :default-output default-output)
        (setf output-pipe-stream resolved-output-pipe-stream)
        (values input
                output
                error-output
                input-pipe-stream
                output-pipe-stream
                redirect-streams)))))

(defun %close-new-redirect-streams (redirect-streams previous-redirect-streams)
  (loop for streams on redirect-streams
        until (eq streams previous-redirect-streams)
        do (ignore-errors (close (car streams)))))

(defun %close-unused-next-pipe-writer (next-pipe output-pipe-stream)
  (when (and next-pipe (null output-pipe-stream) (integerp (second next-pipe)))
    (ignore-errors (sb-posix:close (second next-pipe)))
    (setf (second next-pipe) nil)))

(defun %spawn-pipeline-stage (cmd-node stage-redirects prev-pipe next-pipe redirect-streams
                              &key (default-output :stream))
  (let ((previous-redirect-streams redirect-streams)
        (started nil))
    (multiple-value-bind (input output error-output input-pipe-stream output-pipe-stream redirect-streams)
        (%pipeline-stage-streams stage-redirects prev-pipe next-pipe redirect-streams
                                 :default-output default-output)
      (let* ((cmd (nshell.domain.parsing:command-node-command cmd-node))
             (args (mapcar #'nshell.domain.parsing:arg-value
                           (nshell.domain.parsing:command-node-args cmd-node)))
             (environment (%get-environment))
             (resolved-cmd (%resolve-external-command cmd environment)))
        (unwind-protect
             (multiple-value-prog1
                 (values
                  (progn
                    (%close-unused-next-pipe-writer next-pipe output-pipe-stream)
                    (if resolved-cmd
                        (sb-ext:run-program resolved-cmd args
                          :input input
                          :output output
                          :error error-output
                          :wait nil
                          :search nil
                          :environment environment)
                        (progn
                          (format *error-output*
                                  "~a"
                                  (%external-command-not-found-message cmd))
                          nil)))
                  redirect-streams)
               (setf started t))
          (unless started
            (%close-new-redirect-streams redirect-streams previous-redirect-streams))
          (when input-pipe-stream
            (ignore-errors (close input-pipe-stream)))
          (when output-pipe-stream
            (ignore-errors (close output-pipe-stream))))))))

(defun %drain-process-output (proc)
  (when (and proc (sb-ext:process-output proc))
    (handler-case
        (loop for line = (read-line (sb-ext:process-output proc) nil nil)
              while line
              do (write-line line))
      (error ()))))

(defun %wait-pipeline-processes (procs)
  (let ((last-proc (car procs))
        (exit 0))
    (dolist (proc procs)
      (sb-ext:process-wait proc)
      (when (eq proc last-proc)
        (setf exit (process-exit-status-code proc))))
    exit))

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
  (dolist (proc procs)
    (when (and proc (sb-ext:process-alive-p proc))
      (ignore-errors (sb-ext:process-kill proc 15))))
  (dolist (proc procs)
    (when (and proc (not (%wait-process-exit-with-timeout proc 0.5)))
      (when (sb-ext:process-alive-p proc)
        (ignore-errors (sb-ext:process-kill proc 9)))
      (ignore-errors (sb-ext:process-wait proc)))))

(defun %wait-pipeline-exit-with-timeout (procs timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second)))))
    (loop while (and (some #'sb-ext:process-alive-p procs)
                     (< (get-internal-real-time) deadline))
          do (sleep 0.01))
    (not (some #'sb-ext:process-alive-p procs))))

(defun %wait-pipeline-with-output (procs timeout-fn)
  (let ((copier (%start-process-output-copier (car procs) *standard-output*)))
    (unwind-protect
         (if (or (null *external-command-timeout*)
                 (%wait-pipeline-exit-with-timeout procs *external-command-timeout*))
             (progn
               (prog1 (%wait-pipeline-processes procs)
                 (%join-process-output-copier copier)))
             (progn
               (%terminate-pipeline-processes procs)
               (%join-process-output-copier copier)
               (funcall timeout-fn)))
      (%join-process-output-copier copier))))

(defun %pipeline-spawn-loop (commands pipes redirects redirect-streams
                             &key default-output pgid-assign-fn error-sentinel)
  "Iterate over COMMANDS, spawning each as a pipeline stage connected via PIPES.
Returns (values procs pgid redirect-streams error-p) where ERROR-P is the
value of ERROR-SENTINEL when a spawn fails, or NIL on success.

DEFAULT-OUTPUT  — forwarded to %spawn-pipeline-stage as :default-output.
PGID-ASSIGN-FN  — called as (funcall pgid-assign-fn proc pid pgid) after each
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
                                           :default-output default-output)
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
    (values procs pgid redirect-streams error-p)))

(defun spawn-pipeline (commands &key redirects)
  "Execute COMMANDS connected by OS-level pipes and return the last exit code."
  (let* ((count (length commands))
         (redirects (or redirects (make-list count :initial-element nil)))
         (pipes (loop repeat (max 0 (1- count))
                      collect (multiple-value-list (sb-posix:pipe))))
         (redirect-streams nil))
    (unwind-protect
         (multiple-value-bind (procs pgid updated-streams spawn-error-code)
             (%pipeline-spawn-loop commands pipes redirects redirect-streams
                                   :default-output :stream
                                   :error-sentinel 127
                                   :pgid-assign-fn
                                   (lambda (proc pgid)
                                     (let ((pid (and proc (sb-ext:process-pid proc))))
                                       (when (and (integerp pid) (plusp pid))
                                         (unless pgid
                                           (setf pgid pid))
                                         (%assign-process-group pid pgid)))
                                     pgid))
           (setf redirect-streams updated-streams)
           (if spawn-error-code
               (progn
                 (%close-pipeline-fds pipes)
                 (%terminate-pipeline-processes procs)
                 spawn-error-code)
               (flet ((finish-pipeline ()
                        (%wait-pipeline-with-output
                         procs
                         (lambda ()
                           (format *error-output*
                                   "nshell: pipeline timed out after ~a seconds~%"
                                   *external-command-timeout*)
                           124))))
                 (%close-pipeline-fds pipes)
                 (if pgid
                     (%with-foreground-process-group pgid #'finish-pipeline)
                     (finish-pipeline)))))
      (dolist (stream redirect-streams)
        (ignore-errors (close stream)))
      (%close-pipeline-fds pipes))))

(defun spawn-pipeline-async (commands &key redirects)
  "Execute COMMANDS connected by OS-level pipes asynchronously."
  (let* ((count (length commands))
         (redirects (or redirects (make-list count :initial-element nil)))
         (pipes (loop repeat (max 0 (1- count))
                      collect (multiple-value-list (sb-posix:pipe))))
         (redirect-streams nil))
    (unwind-protect
         (multiple-value-bind (procs pgid updated-streams spawn-error)
             (%pipeline-spawn-loop commands pipes redirects redirect-streams
                                   :default-output t
                                   :error-sentinel t
                                   :pgid-assign-fn
                                   (lambda (proc pgid)
                                     (when proc
                                       (let ((pid (sb-ext:process-pid proc)))
                                         (when (plusp pid)
                                           (unless pgid
                                             (setf pgid pid))
                                           (handler-case (set-process-group pid pgid)
                                             (error ())))))
                                     pgid))
           (declare (ignore pgid))
           (setf redirect-streams updated-streams)
           (if spawn-error
               (progn
                 (%close-pipeline-fds pipes)
                 (%terminate-pipeline-processes procs)
                 nil)
               (nreverse procs)))
      (dolist (stream redirect-streams)
        (ignore-errors (close stream)))
      (%close-pipeline-fds pipes))))
