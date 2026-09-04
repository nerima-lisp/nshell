(in-package #:nshell.infrastructure.acl)

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

(defun %validate-pty-spawn-input (program args rows cols)
  (check-type program string)
  (check-type args list)
  (unless (every #'stringp args)
    (error "PTY arguments must all be strings: ~S" args))
  (unless (and (integerp rows) (plusp rows)
               (integerp cols) (plusp cols))
    (error "PTY dimensions must be positive integers: ~S x ~S" rows cols))
  t)

(defun pty-spawn (program args &key (rows 24) (cols 80))
  "Spawn PROGRAM with ARGS attached to a newly opened PTY."
  (%validate-pty-spawn-input program args rows cols)
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
