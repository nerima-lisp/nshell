(in-package #:nshell.infrastructure.acl)

(defun %external-output-target (output)
  ;; SBCL's internal copier for non-FD streams has no drain deadline.
  (if (and (streamp output)
           (null (sb-impl::get-stream-fd-and-external-format output :output)))
      :stream
      output))

(defvar *process-output-clock* (function get-internal-real-time))

(defvar *process-output-watch* nil
  "NIL, or a function of no arguments that %START-STREAM-COPIER calls, in the
thread starting the copier, for the function of (BUFFER END) the copier then
calls with each chunk it has copied, held in BUFFER below END.")

(defun %copy-process-output (input output read-function &optional watcher)
  (let ((buffer (make-string 4096)))
    (loop for count = (funcall read-function buffer input)
          while (plusp count)
          do (write-string buffer output :end count)
             (when watcher
               (funcall watcher buffer count)))
    (when (streamp output)
      (finish-output output))
    :eof))

(defun %read-available-characters (buffer input)
  "Fill BUFFER from INPUT with what it holds now, waiting only for the first
character, and return the count, 0 at end of file. A watcher sees output as
it comes; READ-SEQUENCE would wait for a full buffer."
  (let ((char (read-char input nil)))
    (if (null char)
        0
        (progn
          (setf (char buffer 0) char)
          (loop for count from 1
                for next = (and (< count (length buffer))
                                (read-char-no-hang input nil))
                while next
                do (setf (char buffer count) next)
                finally (return count))))))

(defun %start-stream-copier (input output name
                                   &optional
                                   (read-function (function read-sequence)))
  (when input
    (let ((watcher (and *process-output-watch* (funcall *process-output-watch*))))
      (sb-thread:make-thread
       (lambda ()
         (ignore-errors
          (%copy-process-output input output
                                (if watcher #'%read-available-characters read-function)
                                watcher)))
       :name name))))

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
