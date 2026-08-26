(in-package #:nshell.infrastructure.acl)


(defparameter *external-command-timeout* nil
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
                     (round (* timeout-seconds internal-time-units-per-second))))
        (sleep-seconds 0.0001))
    (loop while (and (sb-ext:process-alive-p proc)
                     (< (get-internal-real-time) deadline))
          for remaining-seconds = (/ (- deadline (get-internal-real-time))
                                     (float internal-time-units-per-second))
          do (sleep (min sleep-seconds (max 0 remaining-seconds)))
             (setf sleep-seconds (min 0.01 (* 2 sleep-seconds))))
    (unless (sb-ext:process-alive-p proc)
      (ignore-errors (sb-ext:process-wait proc))
      t)))

(defun %terminate-process (proc)
  (when proc
    (let* ((pid (sb-ext:process-pid proc))
           ;; SETPGID can lose a race with a child that has already execed. Never
           ;; signal a process group until its identity is verified: otherwise a
           ;; negative PID can target nshells own group and terminate its host.
           (actual-pgid (and (integerp pid)
                             (plusp pid)
                             (ignore-errors (sb-posix:getpgid pid))))
           (owns-process-group-p (and (integerp actual-pgid)
                                      (plusp actual-pgid)
                                      (= pid actual-pgid))))
      (flet ((terminate (signal)
               (if owns-process-group-p
                   (ignore-errors (%send-process-group-signal pid signal))
                   (when (sb-ext:process-alive-p proc)
                     (ignore-errors (sb-ext:process-kill proc signal))))))
        (terminate sb-unix:sigterm)
        (%wait-process-exit-with-timeout proc 0.5)
        (terminate sb-unix:sigkill)
        (ignore-errors (sb-ext:process-wait proc))))))

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

(defun %wait-process-with-copiers-or-stop (proc copiers success-fn stop-fn)
  "Like %WAIT-PROCESS-WITH-COPIERS with no timeout, except a stopped PROC
\(e.g. SIGTSTP from Ctrl-Z on a foregrounded process group) does not block
forever: SB-EXT:PROCESS-WAIT's second argument, passed T, returns on a stop
as well as on termination, where the plain call this function's sibling
relies on would wait indefinitely against a process that is alive but merely
suspended.

On a stop, COPIERS are left running -- PROC may resume and write more output
-- and STOP-FN decides what happens: returning :CONTINUE-WAIT resumes
waiting (the caller has continued the process), any other value becomes this
function's result. The wait between stop checks is throttled so a process
that stays stopped despite STOP-FN does not busy-loop."
  (loop
    (sb-ext:process-wait proc t)
    (if (eq (sb-ext:process-status proc) :stopped)
        (let ((decision (funcall stop-fn)))
          (unless (eq decision :continue-wait)
            (return decision))
          (sleep 0.05))
        (return
          (unwind-protect
               (progn
                 (%join-process-output-copiers copiers)
                 (funcall success-fn))
            (%join-process-output-copiers copiers))))))

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

(defun executable-file-p (path)
  (ignore-errors
   (not (zerop (logand (sb-posix:stat-mode (sb-posix:stat path))
                       #o111)))))

(defun %resolve-external-command (command &optional (environment (%get-environment)))
  (nshell.domain.completion::%first-command-path-candidate
   command
   (or (%environment-value "PATH" environment)
       "/bin:/usr/bin")
   #'executable-file-p
   :empty-directory "."))

(defun %prepare-external-command (command &optional (environment (%get-environment)))
  (values (%resolve-external-command command environment)
          environment))

(defun %report-external-command-not-found (command)
  (format *error-output* "~a" (%external-command-not-found-message command)))

(defun %spawn-external-command (resolved-cmd args environment &key input output (error nil error-supplied-p)) (sb-ext:run-program resolved-cmd args :input input :output output :error (if error-supplied-p error (if *redirected-stderr* *error-output* :output)) :wait nil :search nil :environment environment))

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
        ((:<< :<<-) (track (%here-document-stream target)))
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

(defun %spawn-in-own-process-group (resolved-cmd args environment input output &key (error nil error-supplied-p))
  "Spawn RESOLVED-CMD wired to INPUT/OUTPUT and isolate it in its own process group. Returns the process, or NIL when the spawn fails."
  (let ((proc (if error-supplied-p
                  (%spawn-external-command resolved-cmd args environment
                                           :input input :output output :error error)
                  (%spawn-external-command resolved-cmd args environment
                                           :input input :output output))))
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

(defun run-external-exec (cmd args)
  "Execute CMD with ARGS for the exec builtin.

Standard streams pass through directly and noninteractive execution uses the
normal foreground timeout policy."
  (handler-case
      (multiple-value-bind (resolved-cmd environment)
          (%prepare-external-command cmd)
        (unless resolved-cmd
          (%report-external-command-not-found cmd)
          (return-from run-external-exec 127))
        (let ((proc (%spawn-in-own-process-group
                     resolved-cmd args environment
                     *standard-input* *standard-output*
                     :error *error-output*)))
          (if proc
              (let* ((pid (sb-ext:process-pid proc))
                     (pgid (and (integerp pid) (plusp pid) pid))
                     (timeout (%foreground-external-command-timeout)))
                (flet ((finish-process ()
                         (if (or (null timeout)
                                 (%wait-process-exit-with-timeout proc timeout))
                             (progn
                               (sb-ext:process-wait proc)
                               (process-exit-status-code proc))
                             (progn
                               (%terminate-process proc)
                               (format *error-output* "~a"
                                       (%external-command-timeout-message cmd timeout))
                               124))))
                  (if pgid
                      (%with-foreground-process-group pgid (function finish-process))
                      (finish-process))))
              1)))
    (error (err)
      (format *error-output* "exec: ~a: ~a~%" cmd err)
      1)))

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
                          proc *standard-output* timeout
                          (lambda ()
                            (format *error-output* "~a"
                                    (%external-command-timeout-message cmd timeout))
                            124))))
                  (if pgid
                      (%with-foreground-process-group pgid (function finish-process))
                      (finish-process))))
              1)))
    (error (err)
      (format *error-output* "nshell: ~a: ~a~%" cmd err)
      1)))

(defun run-external-capture (cmd args)
  "Execute CMD with ARGS synchronously, capturing stdout for command
substitution. Returns the captured output and a shell exit code.

Launches through cl-process-kit's SPAWN + COMMUNICATE (see the inline comment
for why the one-shot RUN is not enough), which captures output, enforces
*EXTERNAL-COMMAND-TIMEOUT* by escalating SIGTERM to SIGKILL across the child's
whole process group, and reports a timeout instead of signalling. Command
resolution and the shell's stderr/exit conventions stay here: stderr merges
into the captured value unless a redirection is active, in which case it is
replayed to *ERROR-OUTPUT*.

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
               (input (and forward-stdin-p *standard-input*)))
          ;; SPAWN + COMMUNICATE rather than the one-shot RUN so the child's
          ;; pid is known while it executes: the shell keeps terminal ownership
          ;; on this path, so Ctrl-C reaches the child only through
          ;; SHELL-SIGINT-HANDLER's *FOREGROUND-PGID* forwarding, which needs
          ;; the pgid registered before the wait begins. SPAWN puts the child
          ;; in its own process group, so pid doubles as pgid. Deliberately no
          ;; TCSETPGRP handoff and no SIGTSTP forwarding here: COMMUNICATE
          ;; treats a stopped child as still running, so a forwarded Ctrl-Z
          ;; would wedge this wait forever (*FOREGROUND-STOP-CAPABLE-P* stays
          ;; NIL).
          (process-kit:with-process
              (process (process-kit:spawn
                        resolved-cmd args
                        :input (and input :stream)
                        :output :stream
                        :error (if separate-stderr-p :stream :output)
                        :environment (or environment
                                         (copy-list (sb-ext:posix-environ)))))
            (let ((pid (process-kit:process-id process)))
              (unwind-protect
                   (progn
                     (when (and (integerp pid) (plusp pid))
                       (setf *foreground-pgid* pid))
                     (let ((result (process-kit:communicate
                                    process
                                    :input input
                                    :timeout *external-command-timeout*
                                    :on-timeout :return)))
                       (when separate-stderr-p
                         (write-string (process-kit:process-result-stderr result)
                                       *error-output*))
                       (if (process-kit:process-result-timed-out-p result)
                           (values (%external-command-timeout-message
                                    cmd *external-command-timeout*)
                                   124)
                           (values (process-kit:process-result-stdout result)
                                   (%process-result-shell-exit result)))))
                (setf *foreground-pgid* 0))))))
    (error (err)
      (values (format nil "nshell: ~a: ~a~%" cmd err) 1))))
