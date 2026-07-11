(in-package #:nshell.infrastructure.acl)


(defparameter *external-command-timeout* 30
  "Maximum seconds for synchronous external commands. NIL disables the timeout.")

(defun process-exit-status-code (proc)
  "Return shell-compatible exit status for an SBCL process."
  (let ((code (sb-ext:process-exit-code proc)))
    (if (and code (eq (sb-ext:process-status proc) :signaled))
        (+ 128 code)
        (or code 0))))

(defun %copy-process-output (input output)
  (let ((buffer (make-string 4096)))
    (loop for count = (read-sequence buffer input)
          while (plusp count)
          do (write-string buffer output :end count))
    (when (streamp output)
      (ignore-errors
       (finish-output output)))))

(defun %start-stream-copier (input output name)
  (when input
    (sb-thread:make-thread
     (lambda ()
       (ignore-errors
        (%copy-process-output input output)))
     :name name)))

(defun %start-process-output-copier (proc output)
  (%start-stream-copier (and proc (sb-ext:process-output proc))
                        output
                        "nshell process output copier"))

(defun %join-stream-copier (thread)
  (when thread
    (ignore-errors
     (sb-thread:join-thread thread))))

(defun %join-process-output-copiers (copiers)
  (dolist (copier copiers)
    (%join-stream-copier copier)))

(defun %wait-process-exit-with-timeout (proc timeout-seconds)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout-seconds internal-time-units-per-second)))))
    (loop while (and (sb-ext:process-alive-p proc)
                     (< (get-internal-real-time) deadline))
          do (sleep 0.01))
    (unless (sb-ext:process-alive-p proc)
      (ignore-errors (sb-ext:process-wait proc))
      t)))

(defun %terminate-process (proc)
  (when (and proc (sb-ext:process-alive-p proc))
    (ignore-errors (sb-ext:process-kill proc 15)))
  (when (and proc (not (%wait-process-exit-with-timeout proc 0.5)))
    (when (sb-ext:process-alive-p proc)
      (ignore-errors (sb-ext:process-kill proc 9)))
    (ignore-errors (sb-ext:process-wait proc))))

(defun %wait-process-with-copiers (proc copiers timeout-seconds success-fn timeout-fn)
  (unwind-protect
       (if (or (null timeout-seconds)
               (%wait-process-exit-with-timeout proc timeout-seconds))
           (progn
             (sb-ext:process-wait proc)
             (%join-process-output-copiers copiers)
             (funcall success-fn))
           (progn
             (%terminate-process proc)
             (%join-process-output-copiers copiers)
             (funcall timeout-fn)))
    (%join-process-output-copiers copiers)))

(defun %wait-process-with-output (proc output timeout-seconds timeout-fn)
  (let ((copier (%start-process-output-copier proc output)))
    (%wait-process-with-copiers
     proc
     (list copier)
     timeout-seconds
     (lambda ()
       (values (process-exit-status-code proc) nil))
     (lambda ()
       (values (funcall timeout-fn) t)))))

(defun %external-command-timeout-message (command timeout-seconds)
  (format nil "nshell: ~a: timed out after ~a seconds~%" command timeout-seconds))

(defun %external-command-not-found-message (command)
  (format nil "nshell: ~a: command not found~%" command))

(defun %environment-value (name environment)
  (let ((prefix (format nil "~a=" name)))
    (loop for entry in environment
          when (and (stringp entry)
                    (<= (length prefix) (length entry))
                    (string= prefix entry :end2 (length prefix)))
            return (subseq entry (length prefix)))))

(defun %executable-file-p (path)
  (and (probe-file path)
       (ignore-errors
        (not (zerop (logand (sb-posix:stat-mode (sb-posix:stat path))
                            #o111))))))

(defun %resolve-external-command (command &optional (environment (%get-environment)))
  (first
   (nshell.domain.completion:command-path-candidates
    command
    (or (%environment-value "PATH" environment)
        "/bin:/usr/bin")
    #'%executable-file-p
    :empty-directory ".")))

(defun %prepare-external-command (command &optional (environment (%get-environment)))
  (values (%resolve-external-command command environment)
          environment))

(defun %report-external-command-not-found (command)
  (format *error-output* "~a" (%external-command-not-found-message command)))

(defun %spawn-external-command (resolved-cmd args environment &key input output)
  (sb-ext:run-program resolved-cmd args
                      :input input
                      :output output
                      :error (if *redirected-stderr* *error-output* :output)
                      :wait nil
                      :search nil
                      :environment environment))

(defun spawn-async (cmd args &key redirects)
  "Spawn CMD with ARGS asynchronously. Returns the SBCL process object, or NIL on error."
  (let ((redirect-streams nil))
    (unwind-protect
         (handler-case
             (multiple-value-bind (input-kind input-target)
                 (nshell.domain.parsing:redirect-input-spec redirects)
               (let* ((input (cond
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
                               ((eq input-kind :<<)
                                (let ((stream (%here-document-stream input-target)))
                                  (push stream redirect-streams)
                                  stream))
                               (t *standard-input*)))
                      (output
                        (multiple-value-bind (output-target output-mode)
                            (nshell.domain.parsing:redirect-output-spec redirects)
                          (if output-target
                              (let ((stream (open output-target
                                                  :direction :output
                                                  :if-exists output-mode
                                                  :if-does-not-exist :create)))
                                (push stream redirect-streams)
                                stream)
                              t))))
                 (multiple-value-bind (resolved-cmd environment)
                     (%prepare-external-command cmd)
                   (when resolved-cmd
                     (let ((proc (%spawn-external-command
                                  resolved-cmd args environment
                                  :input input
                                  :output output)))
                       (when proc
                         (let ((pid (sb-ext:process-pid proc)))
                           (when (plusp pid)
                             (handler-case (set-process-group pid pid)
                               (error ()))))
                         proc))))))
           (error (err)
             (format *error-output* "nshell: ~a: ~a~%" cmd err)
             nil))
      (dolist (stream redirect-streams)
        (ignore-errors (close stream))))))

(defun run-external (cmd args)
  "Execute CMD with ARGS synchronously, printing output. Returns exit code."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (%report-external-command-not-found cmd)
          (return-from run-external 127))
        (let ((proc (%spawn-external-command resolved-cmd args environment
                                             :input *standard-input*
                                             :output :stream)))
          (if proc
              (let* ((pid (sb-ext:process-pid proc))
                     (pgid (and (integerp pid) (plusp pid) pid)))
                (when pgid
                  (%assign-process-group pid pgid))
                (flet ((finish-process ()
                         (%wait-process-with-output
                          proc
                          *standard-output*
                          *external-command-timeout*
                          (lambda ()
                            (format *error-output*
                                    "~a"
                                    (%external-command-timeout-message
                                     cmd *external-command-timeout*))
                            124))))
                  (if pgid
                      (%with-foreground-process-group pgid #'finish-process)
                      (finish-process))))
              1)))
    (error (err)
      (format *error-output* "nshell: ~a: ~a~%" cmd err)
      1)))

(defun run-external-capture (cmd args)
  "Execute CMD with ARGS synchronously. Returns captured output and exit code."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (return-from run-external-capture
            (values (%external-command-not-found-message cmd) 127)))
        (let ((proc (%spawn-external-command resolved-cmd args environment
                                             :input *standard-input*
                                             :output :stream)))
          (if proc
              (let ((buffer (make-string-output-stream)))
                (multiple-value-bind (exit timeout-p)
                    (%wait-process-with-output
                     proc
                     buffer
                     *external-command-timeout*
                     (lambda ()
                       124))
                  (values (if (= exit 124)
                              (if timeout-p
                                  (%external-command-timeout-message
                                   cmd *external-command-timeout*)
                                  (get-output-stream-string buffer))
                              (get-output-stream-string buffer))
                          exit)))
              (values "" 1))))
    (error (err)
      (values (format nil "nshell: ~a: ~a~%" cmd err) 1))))
