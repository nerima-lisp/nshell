(in-package #:nshell.infrastructure.acl)

(defun %external-output-target (output)
  ;; SBCL's internal copier for non-FD streams has no drain deadline.
  (if (and (streamp output)
           (null (sb-impl::get-stream-fd-and-external-format output :output)))
      :stream
      output))

(defvar *process-output-clock* (function get-internal-real-time))

(defun %start-stream-copier (input output name
                                   &optional
                                   (read-function (function read-sequence)))
  (when input
    (%start-output-copier input output name :read-function read-function)))

(defun %start-process-output-copier (proc output)
  (%start-stream-copier (and proc (process-output proc))
                        output
                        "nshell process output copier"))

(defun %join-stream-copier (thread)
  (when thread
    (ignore-errors
     (sb-thread:join-thread thread))))

(defun %join-process-output-copiers (copiers)
  (dolist (copier copiers)
    (%join-stream-copier copier)))
