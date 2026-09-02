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

(defun %syscall-failed-p (result)
  (or (null result)
      (and (integerp result) (minusp result))))

(defmacro %check-errno (result operation)
  `(with-checked-syscall (,operation ,result)))

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
                   (if (and fd (not (%syscall-failed-p fd)))
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

(defun pty-write (fd data)
  "Write DATA to FD. DATA may be a string or octet vector. Returns bytes written."
  (let ((buffer (if (stringp data) (nshell.util:utf-8-octets data) data)))
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
