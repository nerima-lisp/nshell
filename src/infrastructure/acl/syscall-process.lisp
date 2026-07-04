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
          do (write-string buffer output :end count)
             (force-output output))))

(defun %start-process-output-copier (proc output)
  (let ((input (and proc (sb-ext:process-output proc))))
    (when input
      (sb-thread:make-thread
       (lambda ()
         (ignore-errors
          (%copy-process-output input output)))
       :name "nshell process output copier"))))

(defun %join-process-output-copier (thread)
  (when thread
    (ignore-errors
     (sb-thread:join-thread thread))))

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

(defun %wait-process-with-output (proc output timeout-seconds timeout-fn)
  (let ((copier (%start-process-output-copier proc output)))
    (unwind-protect
         (if (or (null timeout-seconds)
                 (%wait-process-exit-with-timeout proc timeout-seconds))
             (progn
               (sb-ext:process-wait proc)
               (%join-process-output-copier copier)
               (values (process-exit-status-code proc) nil))
             (progn
               (%terminate-process proc)
               (%join-process-output-copier copier)
               (values (funcall timeout-fn) t)))
      (unless (sb-ext:process-alive-p proc)
        (%join-process-output-copier copier)))))

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

(defun %command-contains-slash-p (command)
  (find #\/ command :test #'char=))

(defun %executable-file-p (path)
  (and (probe-file path)
       (ignore-errors
        (not (zerop (logand (sb-posix:stat-mode (sb-posix:stat path))
                            #o111))))))

(defun %join-directory-command (directory command)
  (let ((dir (if (string= directory "") "." directory)))
    (if (and (plusp (length dir))
             (char= (char dir (1- (length dir))) #\/))
        (concatenate 'string dir command)
        (concatenate 'string dir "/" command))))

(defun %split-search-path (path)
  (loop with start = 0
        for position = (position #\: path :start start)
        collect (subseq path start position)
        while position
        do (setf start (1+ position))))

(defun %resolve-external-command (command &optional (environment (%get-environment)))
  (cond
    ((%command-contains-slash-p command)
     (and (%executable-file-p command) command))
    (t
     (loop for directory in (%split-search-path
                             (or (%environment-value "PATH" environment)
                                 "/bin:/usr/bin"))
           for candidate = (%join-directory-command directory command)
           when (%executable-file-p candidate)
             return candidate))))

(defun spawn-async (cmd args &key redirects)
  "Spawn CMD with ARGS asynchronously. Returns the SBCL process object, or NIL on error."
  (let ((redirect-streams nil))
    (unwind-protect
         (handler-case
             (let* ((input-redirect (%input-redirect-spec redirects))
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
                             (t *standard-input*)))
                    (output
                      (multiple-value-bind (output-target output-mode)
                          (%redirect-output-spec redirects)
                        (if output-target
                            (let ((stream (open output-target
                                                :direction :output
                                                :if-exists output-mode
                                                :if-does-not-exist :create)))
                              (push stream redirect-streams)
                              stream)
                            t)))
                    (environment (%get-environment))
                    (resolved-cmd (%resolve-external-command cmd environment)))
               (unless resolved-cmd
                 (format *error-output* "~a" (%external-command-not-found-message cmd))
                 (return-from spawn-async nil))
               (let ((proc (sb-ext:run-program resolved-cmd args
                            :input input
                            :output output
                            :error (if *redirected-stderr* *error-output* :output)
                            :wait nil
                            :search nil
                            :environment environment)))
                 (when proc
                   (let ((pid (sb-ext:process-pid proc)))
                     (when (plusp pid)
                       (handler-case (set-process-group pid pid)
                         (error ()))))
                   proc)))
           (error (err)
             (format *error-output* "nshell: ~a: ~a~%" cmd err)
             nil))
      (dolist (stream redirect-streams)
        (ignore-errors (close stream))))))

(defun run-external (cmd args)
  "Execute CMD with ARGS synchronously, printing output. Returns exit code."
  (handler-case
      (let* ((environment (%get-environment))
             (resolved-cmd (%resolve-external-command cmd environment)))
        (unless resolved-cmd
          (format *error-output* "~a" (%external-command-not-found-message cmd))
          (return-from run-external 127))
        (let ((proc (sb-ext:run-program resolved-cmd args
                      :input *standard-input*
                      :output :stream
                      :error (if *redirected-stderr* *error-output* :output)
                      :wait nil
                      :search nil
                      :environment environment)))
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
      (let* ((environment (%get-environment))
             (resolved-cmd (%resolve-external-command cmd environment)))
        (unless resolved-cmd
          (return-from run-external-capture
            (values (%external-command-not-found-message cmd) 127)))
        (let ((proc (sb-ext:run-program resolved-cmd args
                      :input *standard-input*
                      :output :stream
                      :error (if *redirected-stderr* *error-output* :output)
                      :wait nil
                      :search nil
                      :environment environment)))
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
