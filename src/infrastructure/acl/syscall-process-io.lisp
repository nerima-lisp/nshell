(in-package #:nshell.infrastructure.acl)

(defun %external-output-target (output)
  ;; SBCL's internal copier for non-FD streams has no drain deadline.
  (if (and (streamp output)
           (null (sb-impl::get-stream-fd-and-external-format output :output)))
      :stream
      output))

(defun %process-result-shell-exit (result)
  "Map a cl-process-kit PROCESS-RESULT to a shell exit status."
  (let ((code (process-kit:process-result-exit-code result))
        (signal (process-kit:process-result-signal result)))
    (cond (code code)
          (signal (+ 128 signal))
          (t 0))))

(defvar *process-output-clock* (function get-internal-real-time))
(defun %copy-process-output (input output read-function)
  (let ((buffer (make-string 4096)))
    (loop for count = (funcall read-function buffer input)
          while (plusp count)
          do (write-string buffer output :end count))
    (when (streamp output)
      (finish-output output))
    :eof))

(defun %start-stream-copier (input output name
                                   &optional
                                   (read-function (function read-sequence)))
  (when input
    (sb-thread:make-thread
     (lambda ()
       (ignore-errors
        (%copy-process-output input output read-function)))
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
