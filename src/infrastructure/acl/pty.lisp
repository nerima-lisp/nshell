(in-package #:nshell.infrastructure.acl)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(sb-alien:define-alien-routine ("openpty" %openpty) sb-alien:int
  (amaster (* sb-alien:int))
  (aslave (* sb-alien:int))
  (name (* sb-alien:char))
  (termp sb-sys:system-area-pointer)
  (winp sb-sys:system-area-pointer))

(sb-alien:define-alien-routine ("grantpt" %grantpt) sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("unlockpt" %unlockpt) sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("ptsname" %ptsname) sb-alien:c-string
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("posix_openpt" %posix-openpt) sb-alien:int
  (flags sb-alien:int))

(sb-alien:define-alien-routine ("execve" %execve) sb-alien:int
  (path sb-alien:c-string)
  (argv (* sb-alien:c-string))
  (envp (* sb-alien:c-string)))

(defun %check-errno (result operation)
  (when (minusp result)
    (error "~a failed with errno ~d" operation (sb-unix::get-errno)))
  result)

(defun %pty-open-flags ()
  (logior sb-posix:o-rdwr sb-posix:o-noctty))

(defun %open-slave (slave-name)
  (sb-posix:open slave-name (%pty-open-flags)))

(defun open-pty-darwin ()
  "Open a pseudo-terminal pair on Darwin using openpty(3)."
  (sb-alien:with-alien ((master sb-alien:int)
                        (slave sb-alien:int)
                        (name (array sb-alien:char 1024)))
    (%check-errno (%openpty (sb-alien:addr master)
                            (sb-alien:addr slave)
                            (sb-alien:cast name (* sb-alien:char))
                            (sb-sys:int-sap 0)
                            (sb-sys:int-sap 0))
                  "openpty")
    (values master slave (sb-alien:cast name sb-alien:c-string))))

(defun open-pty-linux ()
  "Open a pseudo-terminal pair on Linux using posix_openpt(3)."
  (let* ((master (let ((fd (ignore-errors (%posix-openpt (%pty-open-flags)))))
                   (if (and fd (not (minusp fd)))
                       fd
                       (sb-posix:open "/dev/ptmx" (%pty-open-flags)))))
         (slave-name nil))
    (handler-case
        (progn
          (%check-errno (%grantpt master) "grantpt")
          (%check-errno (%unlockpt master) "unlockpt")
          (setf slave-name (%ptsname master))
          (unless slave-name
            (error "ptsname failed with errno ~d" (sb-unix::get-errno)))
          (values master (%open-slave slave-name) slave-name))
      (error (condition)
        (ignore-errors (sb-posix:close master))
        (error condition)))))

(defun open-pty ()
  "Open a pseudo-terminal pair. Returns (values master-fd slave-fd slave-name)."
  #+darwin
  (open-pty-darwin)
  #+linux
  (open-pty-linux)
  #-(or darwin linux)
  (error "PTY not supported on this platform"))

(defun pty-read (fd buffer length)
  "Read up to LENGTH bytes from FD into BUFFER. Returns the byte count."
  (sb-sys:with-pinned-objects (buffer)
    (multiple-value-bind (count errno)
        (sb-unix:unix-read fd (sb-sys:vector-sap buffer) length)
      (unless count
        (error "read failed with errno ~d" errno))
      count)))

(defun %string-octets (string)
  (let ((octets (make-array (length string) :element-type '(unsigned-byte 8))))
    (loop for i below (length string)
          do (setf (aref octets i) (char-code (char string i))))
    octets))

(defun pty-write (fd data)
  "Write DATA to FD. DATA may be a string or octet vector. Returns bytes written."
  (let ((buffer (if (stringp data) (%string-octets data) data)))
    (multiple-value-bind (count errno)
        (sb-unix:unix-write fd buffer 0 (length buffer))
      (unless count
        (error "write failed with errno ~d" errno))
      count)))

(defun pty-close (master-fd slave-fd)
  "Close both sides of a pseudo-terminal pair. Ignores already-closed descriptors."
  (when master-fd
    (ignore-errors (sb-posix:close master-fd)))
  (when (and slave-fd (not (eql master-fd slave-fd)))
    (ignore-errors (sb-posix:close slave-fd)))
  t)

(defun make-pty-stream (fd)
  "Create an unbuffered character stream for FD."
  (sb-sys:make-fd-stream fd :input t :output t :buffering :none))

(defstruct pty-process
  pid
  pgid
  master-fd
  stream)

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
      (multiple-value-bind (count errno)
          (sb-unix:unix-read fd (sb-sys:vector-sap buffer) 1)
        (cond
          ((null count)
           (error "PTY child readiness read failed with errno ~d" errno))
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
  (let ((argv nil)
        (envp nil)
        (ready-read nil)
        (ready-write nil))
    (unwind-protect
         (progn
           (setf argv (%make-c-string-vector (cons program args))
                 envp (%make-c-string-vector (%get-environment)))
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
             pid))
      (%pty-close-fd ready-read)
      (%pty-close-fd ready-write)
      (%free-c-string-vector argv)
      (%free-c-string-vector envp))))

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
        (slave-fd (gensym "SLAVE-FD")))
    `(multiple-value-bind (,master-fd ,slave-fd ,slave-name) (open-pty)
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
