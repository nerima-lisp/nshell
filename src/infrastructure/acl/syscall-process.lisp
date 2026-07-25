(in-package #:nshell.infrastructure.acl)


(defparameter *external-command-timeout* 30
  "Maximum seconds for synchronous external commands. NIL disables the timeout.")

(defun process-exit-status-code (proc)
  "Return shell-compatible exit status for an SBCL process."
  (let ((code (sb-ext:process-exit-code proc)))
    (if (and code (eq (sb-ext:process-status proc) :signaled))
        (+ 128 code)
        (or code 0))))

(defun %process-result-shell-exit (result)
  "Map a cl-process-kit PROCESS-RESULT to a shell exit status: the process's own
exit code, or 128+signal when it was terminated by a signal."
  (let ((code (process-kit:process-result-exit-code result))
        (signal (process-kit:process-result-signal result)))
    (cond (code code)
          (signal (+ 128 signal))
          (t 0))))

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

(defun %resolve-input-redirect (redirects register)
  "Return the standard-input stream REDIRECTS ask for, calling REGISTER on any
stream opened here so the caller can close it afterwards. With no input
redirection the process inherits *STANDARD-INPUT*."
  (multiple-value-bind (kind target)
      (nshell.domain.parsing:redirect-input-spec redirects)
    (flet ((track (stream) (funcall register stream) stream))
      (case kind
        (:<   (track (open target :direction :input :if-does-not-exist :error)))
        (:<<< (track (%here-string-stream target)))
        (:<<  (track (%here-document-stream target)))
        (t    *standard-input*)))))

(defun %resolve-output-redirect (redirects register)
  "Return the standard-output stream REDIRECTS ask for, or T to inherit this
process's own stdout, calling REGISTER on any stream opened here."
  (multiple-value-bind (target mode)
      (nshell.domain.parsing:redirect-output-spec redirects)
    (if target
        (let ((stream (open target :direction :output
                                   :if-exists mode :if-does-not-exist :create)))
          (funcall register stream)
          stream)
        t)))

(defun %spawn-in-own-process-group (resolved-cmd args environment input output)
  "Spawn RESOLVED-CMD wired to INPUT/OUTPUT and isolate it in its own process
group. Returns the process, or NIL when the spawn fails."
  (let ((proc (%spawn-external-command resolved-cmd args environment
                                       :input input :output output)))
    (when proc
      (let ((pid (sb-ext:process-pid proc)))
        (when (plusp pid)
          (ignore-errors (set-process-group pid pid))))
      proc)))

(defun spawn-async (cmd args &key redirects)
  "Spawn CMD with ARGS asynchronously. Returns the SBCL process object, or NIL on error."
  (let ((redirect-streams nil))
    (flet ((register (stream) (push stream redirect-streams)))
      (unwind-protect
           (handler-case
               (let ((input (%resolve-input-redirect redirects #'register))
                     (output (%resolve-output-redirect redirects #'register)))
                 (multiple-value-bind (resolved-cmd environment)
                     (%prepare-external-command cmd)
                   (when resolved-cmd
                     (%spawn-in-own-process-group resolved-cmd args environment
                                                  input output))))
             (error (err)
               (format *error-output* "nshell: ~a: ~a~%" cmd err)
               nil))
        (dolist (stream redirect-streams)
          (ignore-errors (close stream)))))))

(defun %foreground-external-command-timeout ()
  "Return the timeout to apply to a foreground external command's wait: NIL
when *STANDARD-OUTPUT* is connected to a real interactive terminal right now
-- the user is present and can Ctrl-C a runaway command, so nshell must not
kill a long-lived foreground program like an editor or SSH session -- and
*EXTERNAL-COMMAND-TIMEOUT* otherwise, i.e. whenever this command's output is
redirected to a file/pipe or nshell itself is non-interactive. Per-command
redirects already rebind *STANDARD-OUTPUT*, so this naturally covers `cmd >
file` typed at an interactive prompt too."
  (and (not (interactive-stream-p *standard-output*))
       *external-command-timeout*))

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
                     (pgid (and (integerp pid) (plusp pid) pid))
                     (timeout (%foreground-external-command-timeout)))
                (when pgid
                  (%assign-process-group pid pgid))
                (flet ((finish-process ()
                         (%wait-process-with-output
                          proc
                          *standard-output*
                          timeout
                          (lambda ()
                            (format *error-output*
                                    "~a"
                                    (%external-command-timeout-message
                                     cmd timeout))
                            124))))
                  (if pgid
                      (%with-foreground-process-group pgid #'finish-process)
                      (finish-process))))
              1)))
    (error (err)
      (format *error-output* "nshell: ~a: ~a~%" cmd err)
      1)))

(defun run-external-capture (cmd args)
  "Execute CMD with ARGS synchronously, capturing stdout for command
substitution. Returns the captured output and a shell exit code.

Delegates the timeout-guarded launch to cl-process-kit's RUN, which captures
output, enforces *EXTERNAL-COMMAND-TIMEOUT* by escalating SIGTERM to SIGKILL
across the child's whole process group, and reports a timeout instead of
signalling. Command resolution and the shell's stderr/exit conventions stay
here: stderr merges into the captured value unless a redirection is active, in
which case it is replayed to *ERROR-OUTPUT*.

Standard input is forwarded to the child only while *REDIRECTED-STDIN* is bound,
i.e. when the current stdin is a finite, EOF-bearing stream (a here-doc,
here-string, or `< file`). An unredirected *STANDARD-INPUT* is the interactive
terminal, which never yields EOF; feeding it would leave RUN's stdin pump
blocked forever, so the child is given an empty stdin instead -- matching a real
shell, where `$(echo hi)` does not consume the terminal."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (return-from run-external-capture
            (values (%external-command-not-found-message cmd) 127)))
        (let* ((separate-stderr-p (and *redirected-stderr* t))
               (forward-stdin-p (and *redirected-stdin* t))
               (result (process-kit:run
                        resolved-cmd args
                        :input (and forward-stdin-p *standard-input*)
                        :environment environment
                        :error (if separate-stderr-p :capture :output)
                        :timeout *external-command-timeout*
                        :on-timeout :return)))
          (when separate-stderr-p
            (write-string (process-kit:process-result-stderr result) *error-output*))
          (if (process-kit:process-result-timed-out-p result)
              (values (%external-command-timeout-message
                       cmd *external-command-timeout*)
                      124)
              (values (process-kit:process-result-stdout result)
                      (%process-result-shell-exit result)))))
    (error (err)
      (values (format nil "nshell: ~a: ~a~%" cmd err) 1))))
