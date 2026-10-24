(in-package #:nshell.infrastructure.acl)

(progn
  (defclass %bounded-capture-stream
      (sb-gray:fundamental-character-output-stream)
    ((buffer :initarg :buffer :reader %bounded-capture-stream-buffer)
     (maximum :initarg :maximum :reader %bounded-capture-stream-maximum)
     (truncated-p :initform nil :accessor %bounded-capture-stream-truncated-p)))

  (defmethod sb-gray:stream-write-char
      ((stream %bounded-capture-stream) character)
    (let ((buffer (%bounded-capture-stream-buffer stream)))
      (if (< (fill-pointer buffer)
             (%bounded-capture-stream-maximum stream))
          (vector-push character buffer)
          (setf (%bounded-capture-stream-truncated-p stream) t)))
    character)

  (defmethod sb-gray:stream-write-string
      ((stream %bounded-capture-stream) string &optional (start 0) end)
    (let* ((end (or end (length string)))
           (requested (- end start))
           (buffer (%bounded-capture-stream-buffer stream))
           (buffer-start (fill-pointer buffer))
           (copy-length
             (min requested
                  (- (%bounded-capture-stream-maximum stream)
                     buffer-start))))
      (loop for offset from 0 below copy-length
            do (setf (aref buffer (+ buffer-start offset))
                     (char string (+ start offset))))
      (setf (fill-pointer buffer) (+ buffer-start copy-length))
      (when (< copy-length requested)
        (setf (%bounded-capture-stream-truncated-p stream) t))
      string))

  (defun %make-bounded-capture-stream (maximum)
    (make-instance
     (quote %bounded-capture-stream)
     :buffer (make-array maximum
                         :element-type (quote character)
                         :fill-pointer 0)
     :maximum maximum))

  (defun %external-capture-output (stream)
    (if (typep stream (quote %bounded-capture-stream))
        (coerce
         (subseq (%bounded-capture-stream-buffer stream)
                 0
                 (fill-pointer (%bounded-capture-stream-buffer stream)))
         (quote string))
        (get-output-stream-string stream)))

  (defun run-external-capture (cmd args &key max-output-chars)
    "Execute CMD with ARGS synchronously, capturing stdout for command
substitution. Returns captured output and shell exit code; when
MAX-OUTPUT-CHARS is supplied, also returns whether the output was truncated.
Stderr is forwarded separately when the current command has redirected stderr;
stdin is forwarded only when command substitution explicitly permits it. The
shared process layer drains streams and applies the configured timeout. When
MAX-OUTPUT-CHARS is supplied, excess stdout is drained and discarded."
    (handler-case
          (progn
            (when (and max-output-chars
                       (or (not (integerp max-output-chars))
                           (minusp max-output-chars)))
              (error "MAX-OUTPUT-CHARS must be a non-negative integer."))
            (multiple-value-bind (resolved-cmd environment)
                (%prepare-external-command cmd)
              (unless resolved-cmd
                (return-from run-external-capture
                  (if max-output-chars
                      (values (%external-command-not-found-message cmd) 127 nil)
                      (values (%external-command-not-found-message cmd) 127))))
              (let* ((separate-stderr-p (and *redirected-stderr* t))
                     (input (and *redirected-stdin* *standard-input*))
                     (timeout (ensure-timeout-seconds
                               *external-command-timeout*
                               "external command timeout"))
                     (output (if max-output-chars
                                 (%make-bounded-capture-stream max-output-chars)
                                 (make-string-output-stream)))
                     (process (%spawn-in-own-process-group
                               resolved-cmd args environment input :stream
                               :error (if separate-stderr-p :stream :output)))
                     (pid (process-pid process)))
                (unwind-protect
                     (progn
                       (when (and (integerp pid) (plusp pid))
                         (setf *foreground-pgid* pid))
                       (multiple-value-bind (exit timed-out-p)
                           (%wait-process-with-output
                            process output timeout
                            (lambda ()
                              (format *error-output* "~a"
                                      (%external-command-timeout-message cmd timeout))
                              124)
                            *error-output*)
                         (let ((truncated-p
                                 (and max-output-chars
                                      (%bounded-capture-stream-truncated-p output))))
                           (if timed-out-p
                               (if max-output-chars
                                   (values (%external-command-timeout-message cmd timeout)
                                           exit truncated-p)
                                   (values (%external-command-timeout-message cmd timeout)
                                           exit))
                               (if max-output-chars
                                   (values (%external-capture-output output)
                                           exit truncated-p)
                                   (values (%external-capture-output output)
                                           exit))))))
                  (setf *foreground-pgid* 0))))) (error (err)
          (if max-output-chars
              (values (format nil "nshell: ~a: ~a~%" cmd err) 1 nil)
              (values (format nil "nshell: ~a: ~a~%" cmd err) 1))))))
