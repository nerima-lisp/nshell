(in-package #:nshell.infrastructure.acl)

(defparameter *pty-output-ring-bytes* 65536
  "Maximum number of output octets retained for one foreground PTY command.")

(defstruct (pty-ring-buffer
            (:constructor %make-pty-ring-buffer (capacity bytes start length)))
  capacity
  bytes
  start
  length)

(defun make-pty-ring-buffer (&optional (capacity *pty-output-ring-bytes*))
  (check-type capacity (integer 1 *))
  (%make-pty-ring-buffer capacity
                         (make-array capacity :element-type '(unsigned-byte 8))
                         0
                         0))

(defun %pty-ring-append (ring octets count)
  (let ((capacity (pty-ring-buffer-capacity ring))
        (start (pty-ring-buffer-start ring))
        (length (pty-ring-buffer-length ring)))
    (dotimes (index count)
      (let ((position (if (= length capacity)
                         (prog1 start
                           (setf start (mod (1+ start) capacity)))
                         (prog1 (mod (+ start length) capacity)
                           (incf length)))))
        (setf (aref (pty-ring-buffer-bytes ring) position)
              (aref octets index))))
    (setf (pty-ring-buffer-start ring) start
          (pty-ring-buffer-length ring) length)
    ring))

(defun %pty-ring-octets (ring)
  (let* ((length (pty-ring-buffer-length ring))
         (capacity (pty-ring-buffer-capacity ring))
         (octets (make-array length :element-type '(unsigned-byte 8))))
    (dotimes (index length octets)
      (setf (aref octets index)
            (aref (pty-ring-buffer-bytes ring)
                  (mod (+ (pty-ring-buffer-start ring) index) capacity))))))

(defstruct pty-process
  pid
  pgid
  master-fd
  stream
  (state :running)
  exit-status
  output-ring
  input-thread
  output-thread
  resize-thread
  (finished-p nil))

(defun pty-process-output (process)
  "Return the retained UTF-8 output of PROCESS, oldest retained byte first."
  (check-type process pty-process)
  (if (pty-process-output-ring process)
      (sb-ext:octets-to-string
       (%pty-ring-octets (pty-process-output-ring process)))
      ""))
