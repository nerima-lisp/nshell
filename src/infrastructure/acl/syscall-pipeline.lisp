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
                          (setf output-pipe-stream
                                (sb-sys:make-fd-stream (second next-pipe)
                                                       :output t
                                                       :buffering :line)))
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
                    (setf input-pipe-stream
                          (sb-sys:make-fd-stream (first prev-pipe)
                                                 :input t
                                                 :buffering :line)))
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
  (when (and next-pipe (null output-pipe-stream))
    (ignore-errors (sb-posix:close (second next-pipe)))))

(defun %spawn-pipeline-stage (cmd-node stage-redirects prev-pipe next-pipe redirect-streams
                              &key (default-output :stream))
  (let ((previous-redirect-streams redirect-streams)
        (started nil))
    (multiple-value-bind (input output error-output input-pipe-stream output-pipe-stream redirect-streams)
        (%pipeline-stage-streams stage-redirects prev-pipe next-pipe redirect-streams
                                 :default-output default-output)
      (let* ((cmd (nshell.domain.parsing:command-node-command cmd-node))
             (args (mapcar #'nshell.domain.parsing:arg-value
                           (nshell.domain.parsing:command-node-args cmd-node))))
        (unwind-protect
             (multiple-value-prog1
                 (values
                  (progn
                    (%close-unused-next-pipe-writer next-pipe output-pipe-stream)
                    (sb-ext:run-program cmd args
                      :input input
                      :output output
                      :error error-output
                      :wait nil
                      :search t
                      :environment (%get-environment)))
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
    (ignore-errors (sb-posix:close (first pipe)))
    (ignore-errors (sb-posix:close (second pipe)))))

(defun %wait-process-exit-with-timeout (proc timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second)))))
    (loop while (and (sb-ext:process-alive-p proc)
                     (< (get-internal-real-time) deadline))
          do (sleep 0.01))
    (unless (sb-ext:process-alive-p proc)
      (ignore-errors (sb-ext:process-wait proc))
      t)))

(defun %terminate-pipeline-processes (procs)
  (dolist (proc procs)
    (when (and proc (sb-ext:process-alive-p proc))
      (ignore-errors (sb-ext:process-kill proc 15))))
  (dolist (proc procs)
    (when (and proc (not (%wait-process-exit-with-timeout proc 0.5)))
      (when (sb-ext:process-alive-p proc)
        (ignore-errors (sb-ext:process-kill proc 9)))
      (ignore-errors (sb-ext:process-wait proc)))))

(defun spawn-pipeline (commands &key redirects)
  "Execute COMMANDS connected by OS-level pipes and return the last exit code."
  (let* ((count (length commands))
         (redirects (or redirects (make-list count :initial-element nil)))
         (pipes (loop repeat (max 0 (1- count))
                      collect (multiple-value-list (sb-posix:pipe))))
         (procs nil)
         (pgid nil)
         (redirect-streams nil)
         (spawn-error-code nil))
    (unwind-protect
         (progn
           (loop for index from 0 below count
                 for cmd-node in commands
                 for stage-redirects = (nth index redirects)
                 for prev-pipe = (and (plusp index) (nth (1- index) pipes))
                 for next-pipe = (and (< index (1- count)) (nth index pipes))
                 while (null spawn-error-code)
                 do (handler-case
                        (multiple-value-bind (proc updated-streams)
                            (%spawn-pipeline-stage cmd-node
                                                   stage-redirects
                                                   prev-pipe
                                                   next-pipe
                                                   redirect-streams)
                          (setf redirect-streams updated-streams)
                          (let ((pid (and proc (sb-ext:process-pid proc))))
                            (when (and (integerp pid) (plusp pid))
                              (unless pgid
                                (setf pgid pid))
                              (%assign-process-group pid pgid)))
                          (push proc procs))
                      (error (err)
                        (setf spawn-error-code 127)
                        (format *error-output* "nshell: ~a: ~a~%"
                                (nshell.domain.parsing:command-node-command cmd-node)
                                err))))
           (if spawn-error-code
               (progn
                 (%close-pipeline-fds pipes)
                 (%terminate-pipeline-processes procs)
                 spawn-error-code)
               (flet ((finish-pipeline ()
                        (%drain-process-output (first procs))
                        (%wait-pipeline-processes procs)))
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
         (procs nil)
         (pgid nil)
         (redirect-streams nil)
         (spawn-error nil))
    (unwind-protect
         (progn
           (loop for index from 0 below count
                 for cmd-node in commands
                 for stage-redirects = (nth index redirects)
                 for prev-pipe = (and (plusp index) (nth (1- index) pipes))
                 for next-pipe = (and (< index (1- count)) (nth index pipes))
                 while (null spawn-error)
                 do (handler-case
                        (multiple-value-bind (proc updated-streams)
                            (%spawn-pipeline-stage cmd-node
                                                   stage-redirects
                                                   prev-pipe
                                                   next-pipe
                                                   redirect-streams
                                                   :default-output t)
                          (setf redirect-streams updated-streams)
                          (when proc
                            (let ((pid (sb-ext:process-pid proc)))
                              (when (plusp pid)
                                (unless pgid
                                  (setf pgid pid))
                                (handler-case (set-process-group pid pgid)
                                  (error ()))))
                            (push proc procs)))
                       (error (err)
                         (setf spawn-error t)
                         (format *error-output* "nshell: ~a: ~a~%"
                                 (nshell.domain.parsing:command-node-command cmd-node)
                                 err))))
           (if spawn-error
               (progn
                 (%close-pipeline-fds pipes)
                 (%terminate-pipeline-processes procs)
                 nil)
               (nreverse procs)))
      (dolist (stream redirect-streams)
        (ignore-errors (close stream)))
      (%close-pipeline-fds pipes))))
