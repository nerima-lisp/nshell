(in-package #:nshell.infrastructure.acl)

(defun %pipeline-output-mode (kind)
  (if (nshell.domain.parsing:redirect-append-kind-p kind)
      :append
      :supersede))

(defun %open-pipeline-output-redirect (kind target redirect-streams)
  (let ((stream (open target
                      :direction :output
                      :if-exists (%pipeline-output-mode kind)
                      :if-does-not-exist :create)))
    (values stream (cons stream redirect-streams))))

(defun %pipeline-output-streams (stage-redirects next-pipe redirect-streams
                                 &key default-output)
  (let ((output nil)
        (output-materialized-p nil)
        (output-pipe-stream nil)
        (output-redirected-p nil)
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
               output)
             (current-error-output ()
               (cond
                 ((eq error-output :output)
                  (current-output))
                 ((eq error-output t)
                  *error-output*)
                 (t error-output))))
      (nshell.domain.parsing:map-redirect-entries
       (lambda (kind target)
         (case kind
           ((:> :>>)
            (multiple-value-bind (stream streams)
                (%open-pipeline-output-redirect kind target redirect-streams)
              (setf output stream
                    output-materialized-p t
                    output-redirected-p t
                    redirect-streams streams)))
           ((:2> :2>>)
            (multiple-value-bind (stream streams)
                (%open-pipeline-output-redirect kind target redirect-streams)
              (setf error-output stream
                    redirect-streams streams)))
           ((:&> :&>>)
            (multiple-value-bind (stream streams)
                (%open-pipeline-output-redirect kind target redirect-streams)
              (setf output stream
                    output-materialized-p t
                    output-redirected-p t
                    error-output :output
                    redirect-streams streams)))
           (:2>&1
            (setf error-output
                  (if output-redirected-p
                      :output
                      (current-output))))
           (:fd-dup
            (unless (nshell.domain.parsing:redirect-fd-dup-target-p target)
              (error "Missing file-descriptor duplication target"))
            (let ((source
                    (nshell.domain.parsing:redirect-fd-dup-target-source target))
                  (destination
                    (nshell.domain.parsing:redirect-fd-dup-target-target target)))
              (cond
                ((and (= source 1) (= destination 2))
                 (let ((resolved-error-output (current-error-output)))
                   (setf output resolved-error-output
                         error-output resolved-error-output
                         output-materialized-p t
                         output-redirected-p t)))
                ((and (= source 2) (= destination 1))
                 (setf error-output
                       (if output-redirected-p
                           :output
                           (current-output))))
                (t
                 (error "Unsupported file-descriptor duplication ~d>&~d"
                        source
                        destination)))))))
       stage-redirects)
      (values (current-output)
              error-output
              output-pipe-stream
              redirect-streams))))

(defun %pipeline-stage-streams (stage-redirects prev-pipe next-pipe redirect-streams
                                &key (default-input t) (default-output :stream))
  (let ((input-pipe-stream nil)
        (output-pipe-stream nil))
    (multiple-value-bind (input-kind input-target)
        (nshell.domain.parsing:redirect-input-spec stage-redirects)
      (let ((input (cond
                     ((eq input-kind :<)
                      (let ((stream (open input-target
                                          :direction :input
                                          :if-does-not-exist :error)))
                        (push stream redirect-streams)
                        stream))
                     ((eq input-kind :<<<)
                      (let ((stream (%here-string-stream input-target)))
                        (push stream redirect-streams)
                        stream))
                     ((member input-kind '(:<< :<<-) :test #'eq)
                      (let ((stream (%here-document-stream input-target)))
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
                     (t default-input))))
        (multiple-value-bind (output error-output resolved-output-pipe-stream redirect-streams)
            (%pipeline-output-streams stage-redirects next-pipe redirect-streams
                                      :default-output default-output)
          (setf output-pipe-stream resolved-output-pipe-stream)
          (values input
                  output
                  error-output
                  input-pipe-stream
                  output-pipe-stream
                  redirect-streams))))))

(defun %close-new-redirect-streams (redirect-streams previous-redirect-streams)
  (loop for streams on redirect-streams
        until (eq streams previous-redirect-streams)
        do (ignore-errors (close (car streams)))))

(defun %close-unused-next-pipe-writer (next-pipe output-pipe-stream)
  (when (and next-pipe (null output-pipe-stream) (integerp (second next-pipe)))
    (ignore-errors (sb-posix:close (second next-pipe)))
    (setf (second next-pipe) nil)))

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
                    (if effective-cmd
                        (sb-ext:run-program effective-cmd effective-args
                          :input input
                          :output output
                          :error error-output
                          :wait nil
                          :search nil
                          :preserve-fds preserve-fds
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
  (let* ((count (length commands))
         (redirects (or redirects (make-list count :initial-element nil)))
         (pipes (loop repeat (max 0 (1- count))
                      collect (multiple-value-list (sb-posix:pipe))))
         (redirect-streams nil))
    (unwind-protect
         (multiple-value-bind (procs pgid updated-streams spawn-error-code)
             (%pipeline-spawn-loop commands pipes redirects redirect-streams
                                   :default-input default-input
                                   :default-output default-output
                                   :preserve-fds preserve-fds
                                   :after-spawn after-spawn
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
               (let ((timeout-seconds (%foreground-external-command-timeout)))
  (flet ((finish-pipeline ()
           (%wait-pipeline-with-output
            procs
            timeout-seconds
            (lambda ()
              (format *error-output*
                      "nshell: pipeline timed out after ~a seconds~%"
                      timeout-seconds)
              124)
            pipefail-p)))
    (%close-pipeline-fds pipes)
    (if pgid
        (%with-foreground-process-group pgid (function finish-pipeline))
        (finish-pipeline))))))
      (dolist (stream redirect-streams)
        (ignore-errors (close stream)))
      (%close-pipeline-fds pipes))))

(defun spawn-pipeline-async (commands &key redirects
                                        (default-input t)
                                        (default-output t)
                                        preserve-fds
                                        after-spawn)
  "Execute COMMANDS connected by OS-level pipes asynchronously."
  (let* ((count (length commands))
         (redirects (or redirects (make-list count :initial-element nil)))
         (pipes (loop repeat (max 0 (1- count))
                      collect (multiple-value-list (sb-posix:pipe))))
         (redirect-streams nil))
    (unwind-protect
         (multiple-value-bind (procs pgid updated-streams spawn-error)
             (%pipeline-spawn-loop commands pipes redirects redirect-streams
                                   :default-input default-input
                                   :default-output default-output
                                   :preserve-fds preserve-fds
                                   :after-spawn after-spawn
                                   :error-sentinel t
                                   :pgid-assign-fn
                                   (lambda (proc pgid)
                                     (when proc
                                       (let ((pid (sb-ext:process-pid proc)))
                                         (when (plusp pid)
                                           (unless pgid
                                             (setf pgid pid))
                                           (ignore-errors (set-process-group pid pgid)))))
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

(defstruct (process-substitution-resource
             (:constructor %make-process-substitution-resource
                 (path fd processes)))
  path
  fd
  processes)

(defun %process-substitution-fd-directory ()
  (cond
    ((probe-file "/dev/fd/") "/dev/fd/")
    ((probe-file "/proc/self/fd/") "/proc/self/fd/")
    (t
     (error "process substitution requires /dev/fd or /proc/self/fd"))))

(defun %duplicate-process-substitution-fd (fd)
  (multiple-value-bind (duplicate errno)
      (sb-unix:unix-dup fd)
    (if (integerp duplicate)
        duplicate
        (error "could not duplicate process substitution fd ~D (errno ~D)"
               fd errno))))

(defun %process-substitution-stream (fd direction)
  (if (eq direction :input)
      (sb-sys:make-fd-stream fd
                             :output t
                             :buffering :line
                             :auto-close t)
      (sb-sys:make-fd-stream fd
                             :input t
                             :buffering :line
                             :auto-close t)))

(defun spawn-process-substitution (direction commands &key redirects)
  "Spawn COMMANDS behind an anonymous pipe and return its visible fd path.

DIRECTION :INPUT makes COMMANDS write to the returned path.  DIRECTION
:OUTPUT makes COMMANDS read from the returned path.  The returned resource
owns the parent-side fd and the child processes until it is closed."
  (unless (member direction '(:input :output))
    (error "invalid process substitution direction ~S" direction))
  (let ((directory (%process-substitution-fd-directory))
        (read-fd nil)
        (write-fd nil)
        (outer-fd nil)
        (child-fd nil)
        (child-stream nil)
        (processes nil)
        (success-p nil))
    (unwind-protect
         (progn
           (multiple-value-setq (read-fd write-fd) (sb-posix:pipe))
           (if (eq direction :input)
               (setf outer-fd (%duplicate-process-substitution-fd read-fd)
                     child-fd (%duplicate-process-substitution-fd write-fd))
               (setf outer-fd (%duplicate-process-substitution-fd write-fd)
                     child-fd (%duplicate-process-substitution-fd read-fd)))
           (setf child-stream (%process-substitution-stream child-fd direction))
           (setf processes
                 (spawn-pipeline-async
                  commands
                  :redirects redirects
                  :default-input (if (eq direction :output) child-stream t)
                  :default-output (if (eq direction :input) child-stream t)
                  :preserve-fds (list child-fd)
                  :after-spawn
                  (lambda ()
                    (when child-stream
                      (ignore-errors (close child-stream))
                      (setf child-stream nil
                            child-fd nil)))))
           (unless processes
             (error "process substitution command could not be started"))
           (let ((resource
                   (%make-process-substitution-resource
                    (format nil "~A~D" directory outer-fd)
                    outer-fd
                    processes)))
             (setf success-p t
                   outer-fd nil)
             resource))
      (unless success-p
        (when processes
          (ignore-errors (%terminate-pipeline-processes processes))))
      (when child-stream
        (ignore-errors (close child-stream))
        (setf child-stream nil
              child-fd nil))
      (when (integerp child-fd)
        (ignore-errors (sb-posix:close child-fd)))
      (when (integerp outer-fd)
        (ignore-errors (sb-posix:close outer-fd)))
      (when (integerp read-fd)
        (ignore-errors (sb-posix:close read-fd)))
      (when (integerp write-fd)
        (ignore-errors (sb-posix:close write-fd))))))

(defun release-process-substitution-fd (resource)
  "Close the parent-side fd while retaining RESOURCE's child processes."
  (let ((fd (process-substitution-resource-fd resource)))
    (setf (process-substitution-resource-fd resource) nil)
    (when (integerp fd)
      (ignore-errors (sb-posix:close fd))))
  resource)

(defun wait-process-substitution (resource)
  "Wait for RESOURCE's process substitution child processes."
  (let ((processes (process-substitution-resource-processes resource)))
    (unwind-protect
         (if processes
             (%wait-pipeline-processes processes)
             0)
      (setf (process-substitution-resource-processes resource) nil))))

(defun close-process-substitution (resource)
  "Release RESOURCE's fd and terminate/wait any remaining child processes."
  (release-process-substitution-fd resource)
  (let ((processes (process-substitution-resource-processes resource)))
    (when processes
      (unwind-protect
           (%terminate-pipeline-processes processes)
        (setf (process-substitution-resource-processes resource) nil))))
  resource)
