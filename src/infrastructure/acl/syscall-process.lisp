(in-package #:nshell.infrastructure.acl)

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
                    (proc (sb-ext:run-program cmd args
                            :input input
                            :output output
                            :error (if *redirected-stderr* *error-output* :output)
                            :wait nil
                            :search t
                            :environment (%get-environment))))
               (when proc
                 (let ((pid (sb-ext:process-pid proc)))
                   (when (plusp pid)
                     (handler-case (set-process-group pid pid)
                       (error ()))))
                 proc))
           (error (err)
             (format *error-output* "nshell: ~a: ~a~%" cmd err)
             nil))
      (dolist (stream redirect-streams)
        (ignore-errors (close stream))))))

(defun run-external (cmd args)
  "Execute CMD with ARGS synchronously, printing output. Returns exit code."
  (handler-case
      (let ((proc (sb-ext:run-program cmd args
                    :input *standard-input*
                    :output :stream
                    :error (if *redirected-stderr* *error-output* :output)
                    :wait nil
                    :search t
                    :environment (%get-environment))))
        (if proc
            (let* ((pid (sb-ext:process-pid proc))
                   (pgid (and (integerp pid) (plusp pid) pid)))
              (when pgid
                (%assign-process-group pid pgid))
              (flet ((finish-process ()
                       (let ((out (sb-ext:process-output proc)))
                         (when out
                           (%copy-process-output out *standard-output*)))
                       (sb-ext:process-wait proc)
                       (process-exit-status-code proc)))
                (if pgid
                    (%with-foreground-process-group pgid #'finish-process)
                    (finish-process))))
            1))
    (error (err)
      (format *error-output* "nshell: ~a: ~a~%" cmd err)
      1)))

(defun run-external-capture (cmd args)
  "Execute CMD with ARGS synchronously. Returns captured output and exit code."
  (handler-case
      (let ((proc (sb-ext:run-program cmd args
                    :input *standard-input*
                    :output :stream
                    :error (if *redirected-stderr* *error-output* :output)
                    :wait nil
                    :search t
                    :environment (%get-environment))))
        (if proc
            (let ((out (sb-ext:process-output proc)))
              (let ((output (if out
                                (with-output-to-string (buffer)
                                  (%copy-process-output out buffer))
                                "")))
                (sb-ext:process-wait proc)
                (values output (process-exit-status-code proc))))
            (values "" 1)))
    (error (err)
      (values (format nil "nshell: ~a: ~a~%" cmd err) 1))))
