(in-package #:nshell.infrastructure.acl)

(defun %pty-terminal-dimensions ()
  (handler-case
      (get-terminal-size)
    (error () (values 24 80))))

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
                                :stream master-stream
                                :output-ring (make-pty-ring-buffer)))
        (error (condition)
          (when master-stream
            (ignore-errors (close master-stream)))
          (pty-close master-fd slave-fd)
          (error condition)))))))

(defun %pty-output-tee (process output)
  (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8)))
        (fd (pty-process-master-fd process)))
    (unwind-protect
         (loop
           (handler-case
               (let ((count (pty-read fd buffer (length buffer))))
                 (when (zerop count)
                   (return))
                 (%pty-ring-append (pty-process-output-ring process)
                                   buffer
                                   count)
                 (write-string
                  (sb-ext:octets-to-string (subseq buffer 0 count))
                  output)
                 (finish-output output))
             (error ()
               (return))))
      (setf (pty-process-output-thread process) nil))))

(defun %pty-input-forwarder (process input)
  (unwind-protect
       (loop
         for state = (pty-process-state process)
         while (member state '(:running :stopped))
         do (if (eq state :running)
                (when (listen input)
                  (let ((character (read-char input nil nil)))
                    (if character
                        (ignore-errors
                          (pty-write (pty-process-master-fd process)
                                     (string character)))
                        (return))))
                (sleep 0.01))
            (sleep 0.001))
    (setf (pty-process-input-thread process) nil)))

(defun %start-pty-tee (process input output)
  (setf (pty-process-output-thread process)
        (sb-thread:make-thread
         (lambda () (%pty-output-tee process output))
         :name "nshell PTY output tee")
        (pty-process-input-thread process)
        (sb-thread:make-thread
         (lambda () (%pty-input-forwarder process input))
         :name "nshell PTY input forwarder"))
  process)

(defun %pty-record-wait-status (process state detail)
  (case state
    (:stopped
     (setf (pty-process-state process) :stopped))
    (:continued
     (setf (pty-process-state process) :running))
    (:exited
     (setf (pty-process-state process) :exited
           (pty-process-exit-status process) detail))
    (:signaled
     (setf (pty-process-state process) :signaled
           (pty-process-exit-status process) (+ 128 detail)))
    (:no-child
     (setf (pty-process-state process) :exited
           (pty-process-exit-status process) 0)))
  (pty-process-state process))

(defun pty-process-status (process)
  "Poll PROCESS and return :RUNNING, :STOPPED, :EXITED, or :SIGNALED."
  (check-type process pty-process)
  (when (eq (pty-process-state process) :running)
    (multiple-value-bind (pid state detail)
        (wait-job (pty-process-pid process) :nohang t :untraced t :continued t)
      (declare (ignore pid))
      (unless (eq state :running)
        (%pty-record-wait-status process state detail))))
  (pty-process-state process))

(defun %join-pty-thread (thread)
  (when thread
    (ignore-errors (sb-thread:join-thread thread))))

(defun %finish-pty-process (process)
  (unless (pty-process-finished-p process)
    (setf (pty-process-finished-p process) t)
    (%join-pty-thread (pty-process-output-thread process))
    (%join-pty-thread (pty-process-input-thread process))
    (when (pty-process-stream process)
      (ignore-errors (close (pty-process-stream process))))
    (pty-close (pty-process-master-fd process) nil))
  process)

(defun pty-process-wait (process)
  "Wait until PROCESS exits or stops, preserving a stop for `fg`."
  (check-type process pty-process)
  (loop
    for current = (pty-process-status process)
    when (member current '(:stopped :exited :signaled))
      do (when (member current '(:exited :signaled))
           (%finish-pty-process process))
         (return current)
    do (multiple-value-bind (pid state detail)
           (wait-job (pty-process-pid process) :untraced t :continued t)
         (declare (ignore pid))
         (%pty-record-wait-status process state detail))))

(defun pty-process-continue (process)
  "Continue a stopped PTY process group and resume input forwarding."
  (check-type process pty-process)
  (kill-process (- (pty-process-pgid process)) :sigcont)
  (setf (pty-process-state process) :running)
  process)

(defun %spawn-pty-terminal-command (command args)
  (multiple-value-bind (resolved environment)
      (%prepare-external-command command)
    (declare (ignore environment))
    (when resolved
      (multiple-value-bind (rows cols) (%pty-terminal-dimensions)
        (%start-pty-tee
         (pty-spawn resolved args :rows rows :cols cols)
         *standard-input*
         *standard-output*)))))

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
