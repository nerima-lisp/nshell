(in-package #:nshell.infrastructure.acl)

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

(defun %spawn-external-command
    (resolved-cmd args environment &key input output (error nil error-supplied-p))
  (sb-ext:run-program
   resolved-cmd args
   :input input
   :output output
   :error (if error-supplied-p error
              (if *redirected-stderr* *error-output* :output))
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

(defun %spawn-in-own-process-group (resolved-cmd args environment input output
                                    &key (error nil error-supplied-p))
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
