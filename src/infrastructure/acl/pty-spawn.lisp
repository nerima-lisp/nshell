(in-package #:nshell.infrastructure.acl)

(sb-alien:define-alien-routine ("execve" %execve) sb-alien:int
  (path sb-alien:c-string)
  (argv (* sb-alien:c-string))
  (envp (* sb-alien:c-string)))

(defconstant +pty-child-ready-ok+ 0)

(defconstant +pty-child-ready-error+ 1)

(defun %pty-close-fd (fd)
  (when fd
    (ignore-errors (sb-posix:close fd))))

(defun %pty-child-open-flags ()
  sb-posix:o-rdwr)

(defun %claim-controlling-terminal (slave-fd pgid)
  (ignore-errors
    (%ioctl slave-fd +tiocsctty+ (sb-sys:int-sap 0)))
  (%check-errno (%tcsetpgrp slave-fd pgid) "tcsetpgrp"))

(defun %redirect-pty-slave (slave-fd)
  (dotimes (fd 3)
    (unless (= slave-fd fd)
      (sb-posix:dup2 slave-fd fd))))

(defun %make-c-string-vector (strings)
  (let* ((count (length strings))
         (vector (sb-alien:make-alien sb-alien:c-string (1+ count))))
    (loop for string in strings
          for index from 0
          do (setf (sb-alien:deref vector index) string))
    (setf (sb-alien:deref vector count) nil)
    vector))

(defun %free-c-string-vector (vector)
  (when vector
    (ignore-errors (sb-alien:free-alien vector))))

(defmacro %with-pty-exec-vectors ((argv envp program args) &body body)
  `(let ((,argv (%make-c-string-vector (cons ,program ,args)))
         (,envp (%make-c-string-vector (%get-environment))))
     (unwind-protect
          (progn ,@body)
       (%free-c-string-vector ,argv)
       (%free-c-string-vector ,envp))))

(defun %pty-child-fail ()
  (sb-posix:_exit 127))

(defun %pty-write-ready-byte (fd byte)
  (let ((buffer (make-array 1
                            :element-type '(unsigned-byte 8)
                            :initial-element byte)))
    (multiple-value-bind (count errno)
        (sb-unix:unix-write fd buffer 0 1)
      (declare (ignore errno))
      (and count (= count 1)))))

(defun %pty-read-ready-byte (fd)
  (let ((buffer (make-array 1 :element-type '(unsigned-byte 8))))
    (sb-sys:with-pinned-objects (buffer)
          (multiple-value-bind (count)
              (sb-unix:unix-read fd (sb-sys:vector-sap buffer) 1)
        (cond
          ((null count)
           (error "PTY child readiness read failed with errno ~d"
                  (sb-unix::get-errno)))
          ((zerop count)
           (error "PTY child closed readiness pipe before setup completed"))
          (t
           (aref buffer 0)))))))

(defun %signal-pty-child-ready (fd byte)
  (when fd
    (ignore-errors (%pty-write-ready-byte fd byte))
    (%pty-close-fd fd)))

(defun %wait-for-pty-child-ready (fd pid)
  (let ((byte (%pty-read-ready-byte fd)))
    (unless (= byte +pty-child-ready-ok+)
      (ignore-errors (sb-posix:waitpid pid 0))
      (error "PTY child setup failed")))
  t)

(defun %pty-child-exec (program argv envp master-fd slave-name ready-fd rows cols)
  (handler-case
      (progn
        (%pty-close-fd master-fd)
        (sb-posix:setsid)
        (let ((slave-fd (sb-posix:open slave-name (%pty-child-open-flags))))
          (unwind-protect
               (progn
                 (%set-pty-window-size slave-fd rows cols)
                 (%claim-controlling-terminal slave-fd (sb-posix:getpid))
                 (%redirect-pty-slave slave-fd)
                 (%signal-pty-child-ready ready-fd +pty-child-ready-ok+)
                 (setf ready-fd nil)
                 (when (> slave-fd 2)
                   (sb-posix:close slave-fd)
                   (setf slave-fd nil))
                 (%execve program argv envp)
                 (%pty-child-fail))
            (when slave-fd
              (%pty-close-fd slave-fd)))))
    (error ()
      (%signal-pty-child-ready ready-fd +pty-child-ready-error+)
      (%pty-child-fail))))

(defun %pty-fork-exec (program args master-fd slave-name rows cols)
  (let ((ready-read nil)
        (ready-write nil)
        (child-pid nil))
    (%with-pty-exec-vectors (argv envp program args)
      (unwind-protect
           (progn
             (multiple-value-setq (ready-read ready-write) (sb-posix:pipe))
             (let ((pid (sb-posix:fork)))
               (when (zerop pid)
                 (%pty-close-fd ready-read)
                 (%pty-child-exec program argv envp master-fd slave-name ready-write rows cols))
               (%pty-close-fd ready-write)
               (setf ready-write nil)
               (%wait-for-pty-child-ready ready-read pid)
               (%pty-close-fd ready-read)
               (setf ready-read nil)
               (setf child-pid pid)))
        (%pty-close-fd ready-read)
        (%pty-close-fd ready-write)))
    child-pid))

(defun %set-pty-window-size (slave-fd rows cols)
  (let ((winsize (sb-alien:make-alien sb-alien:unsigned-short 4)))
    (unwind-protect
         (progn
           (setf (sb-alien:deref winsize 0) rows
                 (sb-alien:deref winsize 1) cols
                 (sb-alien:deref winsize 2) 0
                 (sb-alien:deref winsize 3) 0)
           (%check-errno (%ioctl slave-fd +tiocswinsz+ (sb-alien:alien-sap winsize))
                         "ioctl(TIOCSWINSZ)"))
      (sb-alien:free-alien winsize))))

(defun pty-spawn (program args &key (rows 24) (cols 80))
  "Spawn PROGRAM with ARGS attached to a newly opened PTY."
  #-(or darwin linux)
  (declare (ignore program args rows cols))
  #-(or darwin linux)
  (error "PTY not supported on this platform")
  #+(or darwin linux)
  (multiple-value-bind (master-fd slave-fd slave-name) (open-pty)
    (let ((master-stream nil))
      (handler-case
          (progn
            (%pty-close-fd slave-fd)
            (setf slave-fd nil)
            (let* ((pid (%pty-fork-exec program args master-fd slave-name rows cols))
                   (pgid pid))
              (setf master-stream (make-pty-stream master-fd))
              (make-pty-process :pid pid
                                :pgid pgid
                                :master-fd master-fd
                                :stream master-stream)))
        (error (condition)
          (when master-stream
            (ignore-errors (close master-stream)))
          (pty-close master-fd slave-fd)
          (error condition))))))

(defmacro with-pty ((master-stream slave-stream &optional slave-name) &body body)
  "Open a PTY pair, bind MASTER-STREAM and SLAVE-STREAM, and ensure cleanup."
  (let ((master-fd (gensym "MASTER-FD"))
        (slave-fd (gensym "SLAVE-FD"))
        (ignored-slave-name (gensym "IGNORED-SLAVE-NAME")))
    `(multiple-value-bind (,master-fd ,slave-fd
                           ,(or slave-name ignored-slave-name))
         (open-pty)
       (let ((,master-stream nil)
             (,slave-stream nil))
         (unwind-protect
              (progn
                (setf ,master-stream (make-pty-stream ,master-fd)
                      ,slave-stream (make-pty-stream ,slave-fd))
                ,@body)
           (when ,master-stream (ignore-errors (close ,master-stream)))
           (when ,slave-stream (ignore-errors (close ,slave-stream)))
           (pty-close ,master-fd ,slave-fd))))))
