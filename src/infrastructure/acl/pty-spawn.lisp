(in-package #:nshell.infrastructure.acl)

(defun %pty-terminal-dimensions ()
  (handler-case
      (get-terminal-size)
    (error () (values 24 80))))

(defun %pty-posix-spawn (program args environment slave-name new-session-p)
  (let ((actions (sb-alien:make-alien sb-alien:unsigned-long
                                      +spawn-opaque-storage-words+))
        (attributes (sb-alien:make-alien sb-alien:unsigned-long
                                          +spawn-opaque-storage-words+))
        (argv nil)
        (envp nil)
        (pid-storage nil)
        (actions-initialized-p nil)
        (attributes-initialized-p nil))
    (unwind-protect
         (progn
           (setf argv (%spawn-c-string-vector (cons program args))
                 envp (%spawn-c-string-vector environment)
                 pid-storage (sb-alien:make-alien sb-alien:int))
           (%spawn-check-result
            "posix_spawn_file_actions_init"
            (%posix-spawn-file-actions-init (sb-alien:alien-sap actions)))
           (setf actions-initialized-p t)
           (%spawn-check-result
            "posix_spawnattr_init"
            (%posix-spawnattr-init (sb-alien:alien-sap attributes)))
           (setf attributes-initialized-p t)
           (%spawn-check-result
            "posix_spawn_file_actions_addopen"
            (%posix-spawn-file-actions-addopen
             (sb-alien:alien-sap actions)
             0
             slave-name
             (logior sb-posix:o-rdwr
                     (if new-session-p 0 sb-posix:o-noctty))
             0))
           (%spawn-add-file-actions
            (sb-alien:alien-sap actions)
            '((0 1) (0 2))
            nil)
           (%spawn-configure-attributes
            (sb-alien:alien-sap attributes)
            (if new-session-p nil :new)
            new-session-p)
           (%spawn-check-result
            "posix_spawn"
            (%posix-spawn
             (sb-alien:alien-sap pid-storage)
             program
             (sb-alien:alien-sap actions)
             (sb-alien:alien-sap attributes)
             (sb-alien:alien-sap argv)
             (sb-alien:alien-sap envp)))
           (sb-alien:deref pid-storage))
      (when attributes-initialized-p
        (%posix-spawnattr-destroy (sb-alien:alien-sap attributes)))
      (when actions-initialized-p
        (%posix-spawn-file-actions-destroy (sb-alien:alien-sap actions)))
      (sb-alien:free-alien attributes)
      (sb-alien:free-alien actions)
      (when pid-storage
        (sb-alien:free-alien pid-storage))
      (%spawn-free-c-string-vector argv)
      (%spawn-free-c-string-vector envp)))
)

#+darwin
;; Keep posix_spawn's signal and CLOEXEC setup; the helper claims the slave after setsid.
(defun %pty-darwin-bootstrap-spawn (program args environment slave-name)
  (let ((bootstrap-path (current-environment-value "NSHELL_PTY_BOOTSTRAP"))
        (read-fd nil)
        (write-fd nil)
        (actions nil)
        (attributes nil)
        (argv nil)
        (envp nil)
        (pid-storage nil)
        (actions-initialized-p nil)
        (attributes-initialized-p nil)
        (child-pid nil)
        (handoff-complete-p nil))
    (labels ((read-bootstrap-error (fd)
               (sb-alien:with-alien ((error-number sb-alien:int))
                 (loop
                   (multiple-value-bind (count errno)
                       (sb-unix:unix-read
                        fd
                        (sb-alien:alien-sap (sb-alien:addr error-number))
                        4)
                     (cond
                       ((null count)
                        (unless (= errno sb-posix:eintr)
                          (error "PTY bootstrap error pipe read failed (errno ~d)"
                                 errno)))
                       ((zerop count)
                        (return nil))
                       ((= count 4)
                        (return error-number))
                       (t
                        (error "PTY bootstrap error pipe record was truncated")))))))
             (wait-bootstrap-child (pid)
               (loop
                 (handler-case
                     (return
                       (sb-thread:with-mutex (*native-process-waitpid-lock*)
                         (sb-posix:waitpid pid 0)))
                   (sb-posix:syscall-error (condition)
                     (let ((errno (sb-posix:syscall-errno condition)))
                       (cond
                         ((= errno sb-posix:eintr))
                         ((= errno sb-posix:echild)
                          (return nil))
                         (t
                          (error condition)))))))))
      (unless (and bootstrap-path (plusp (length bootstrap-path)))
        (error "NSHELL_PTY_BOOTSTRAP must name the Darwin PTY exec helper"))
      (unwind-protect
           (progn
             (multiple-value-setq (read-fd write-fd) (%spawn-pipe))
             (setf argv
                   (%spawn-c-string-vector
                    (append (list bootstrap-path
                                  slave-name
                                  (format nil "~d" write-fd)
                                  program)
                            args))
                   envp (%spawn-c-string-vector environment)
                   actions
                   (sb-alien:make-alien sb-alien:unsigned-long
                                        +spawn-opaque-storage-words+)
                   attributes
                   (sb-alien:make-alien sb-alien:unsigned-long
                                        +spawn-opaque-storage-words+)
                   pid-storage (sb-alien:make-alien sb-alien:int))
             (%spawn-check-result
              "posix_spawn_file_actions_init"
              (%posix-spawn-file-actions-init (sb-alien:alien-sap actions)))
             (setf actions-initialized-p t)
             (%spawn-check-result
              "posix_spawnattr_init"
              (%posix-spawnattr-init (sb-alien:alien-sap attributes)))
             (setf attributes-initialized-p t)
             (%spawn-add-file-actions
              (sb-alien:alien-sap actions)
              nil
              (list write-fd))
             (%spawn-configure-attributes
              (sb-alien:alien-sap attributes)
              nil
              nil)
             (%spawn-check-result
              "posix_spawn"
              (%posix-spawn
               (sb-alien:alien-sap pid-storage)
               bootstrap-path
               (sb-alien:alien-sap actions)
               (sb-alien:alien-sap attributes)
               (sb-alien:alien-sap argv)
               (sb-alien:alien-sap envp)))
             (setf child-pid (sb-alien:deref pid-storage))
             (sb-posix:close write-fd)
             (setf write-fd nil)
             (let ((error-number (read-bootstrap-error read-fd)))
               (when error-number
                 (wait-bootstrap-child child-pid)
                 (setf handoff-complete-p t)
                 (error "PTY bootstrap failed (errno ~d)" error-number))
               (setf handoff-complete-p t)
               child-pid))
        (when (and child-pid (not handoff-complete-p))
          (ignore-errors (sb-posix:kill child-pid sb-unix:sigkill))
          (ignore-errors (wait-bootstrap-child child-pid)))
        (when read-fd
          (%pty-close-fd read-fd))
        (when write-fd
          (%pty-close-fd write-fd))
        (when attributes-initialized-p
          (%posix-spawnattr-destroy (sb-alien:alien-sap attributes)))
        (when actions-initialized-p
          (%posix-spawn-file-actions-destroy (sb-alien:alien-sap actions)))
        (when pid-storage
          (sb-alien:free-alien pid-storage))
        (%spawn-free-c-string-vector argv)
        (%spawn-free-c-string-vector envp)
        (when attributes
          (sb-alien:free-alien attributes))
        (when actions
          (sb-alien:free-alien actions))))))

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

(defun pty-spawn (program args &key (rows 24) (cols 80)
                              (environment (%get-environment))
                              (new-session-p t))
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
            (%set-pty-window-size slave-fd rows cols)
            (let* ((pid #+darwin
                         (if new-session-p
                             (%pty-darwin-bootstrap-spawn
                              program args environment slave-name)
                             (%pty-posix-spawn
                              program args environment slave-name nil))
                       #+linux
                         (%pty-posix-spawn
                          program args environment slave-name new-session-p))
                   (pgid pid))
              (%pty-close-fd slave-fd)
              (setf slave-fd nil
                    master-stream (make-pty-stream master-fd))
              (make-pty-process :pid pid
                                :pgid pgid
                                :master-fd master-fd
                                :stream master-stream
                                :output-ring (make-pty-ring-buffer))))
        (error (condition)
          (when master-stream
            (ignore-errors (close master-stream)))
          (pty-close master-fd slave-fd)
          (error condition))))))

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

(defun %pty-input-forwarder (process)
  (let ((input (pty-process-input-stream process)))
    (unwind-protect
         (loop
           for state = (pty-process-state process)
           while (eq state :running)
           do (when (listen input)
                (let ((character (read-char input nil nil)))
                  (if character
                      (ignore-errors
                        (pty-write (pty-process-master-fd process)
                                   (string character)))
                      (return))))
              (sleep 0.001))
      (setf (pty-process-input-thread process) nil))))

(defun %pty-resize-forwarder (process)
  (unwind-protect
       (loop
         while (member (pty-process-state process) '(:running :stopped))
         do (when (consume-terminal-resize-p)
              (multiple-value-bind (rows cols) (%pty-terminal-dimensions)
                (ignore-errors
                  (%set-pty-window-size
                   (pty-process-master-fd process) rows cols))))
            (sleep 0.01))
    (setf (pty-process-resize-thread process) nil)))

(defun %start-pty-input-forwarder (process)
  (setf (pty-process-input-thread process)
        (sb-thread:make-thread
         (lambda () (%pty-input-forwarder process))
         :name "nshell PTY input forwarder")))

(defun %start-pty-tee (process input output)
  (setf (pty-process-output-thread process)
        (sb-thread:make-thread
         (lambda () (%pty-output-tee process output))
         :name "nshell PTY output tee")
        (pty-process-input-stream process)
        input)
  (%start-pty-input-forwarder process)
  (setf (pty-process-resize-thread process)
        (sb-thread:make-thread
         (lambda () (%pty-resize-forwarder process))
         :name "nshell PTY resize forwarder"))
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
  (when (member (pty-process-state process) '(:running :stopped))
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
    (%join-pty-thread (pty-process-resize-thread process))
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
  (%join-pty-thread (pty-process-input-thread process))
  (setf (pty-process-input-thread process) nil)
  (kill-process (- (pty-process-pgid process)) :sigcont)
  (setf (pty-process-state process) :running)
  (when (pty-process-input-stream process)
    (%start-pty-input-forwarder process))
  process)

(defun %spawn-pty-terminal-command (command args)
  (multiple-value-bind (resolved environment)
      (%prepare-external-command command)
    (when resolved
      (multiple-value-bind (rows cols) (%pty-terminal-dimensions)
        (%start-pty-tee
         (pty-spawn resolved args :rows rows :cols cols :environment environment
                    :new-session-p t)
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
