(in-package #:nshell.infrastructure.acl)

(sb-alien:define-alien-routine ("execve" %execve) sb-alien:int
  (path sb-alien:c-string)
  (argv (* sb-alien:c-string))
  (envp (* sb-alien:c-string)))

(defconstant +pty-child-ready-ok+ 0)
(defconstant +pty-child-ready-error+ 1)
(defconstant +fd-cloexec+ 1)

(defun %pty-close-fd (fd)
  (when fd
    (ignore-errors (sb-posix:close fd))))

(defun %pty-set-close-on-exec (fd)
  (let ((flags (sb-posix:fcntl fd sb-posix:f-getfd)))
    (sb-posix:fcntl fd sb-posix:f-setfd
                    (logior flags +fd-cloexec+))))

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

(defmacro %with-pty-exec-vectors ((argv envp program args &optional environment)
                                  &body body)
  (let ((environment-form (or environment '(%get-environment))))
    `(let ((,argv (%make-c-string-vector (cons ,program ,args)))
           (,envp (%make-c-string-vector ,environment-form)))
       (unwind-protect
            (progn ,@body)
         (%free-c-string-vector ,argv)
         (%free-c-string-vector ,envp)))))

(defun %pty-child-fail ()
  (sb-posix:_exit 127))

(defun %pty-write-ready-byte (fd byte)
  (let ((buffer (make-array 1 :element-type '(unsigned-byte 8)
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
          ((null count) (error "PTY child readiness read failed with errno ~d"
                               (sb-unix::get-errno)))
          ((zerop count) :eof)
          (t (aref buffer 0)))))))

(defun %signal-pty-child-ready (fd byte)
  (when fd
    (ignore-errors (%pty-write-ready-byte fd byte))
    (%pty-close-fd fd)))

(defun %wait-for-pty-child-ready (fd pid)
  (let ((byte (%pty-read-ready-byte fd)))
    (cond
      ((eq byte :eof))
      ((= byte +pty-child-ready-ok+))
      (t
       (ignore-errors (sb-posix:waitpid pid 0))
       (error "PTY child setup failed"))))
  t)

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

(defun %pty-child-exec (program argv envp master-fd slave-name ready-fd rows cols
                        new-session-p)
  (handler-case
      (progn
        (%pty-close-fd master-fd)
        (if new-session-p
            (sb-posix:setsid)
            (sb-posix:setpgid 0 0))
        (let ((slave-fd (sb-posix:open slave-name (%pty-child-open-flags))))
          (unwind-protect
               (progn
                 (%pty-set-close-on-exec ready-fd)
                 (%set-pty-window-size slave-fd rows cols)
                 (when new-session-p
                   (%claim-controlling-terminal slave-fd (sb-posix:getpid)))
                 (%redirect-pty-slave slave-fd)
                 (when (> slave-fd 2)
                   (sb-posix:close slave-fd)
                   (setf slave-fd nil))
                 (progn
                   (sb-sys:enable-interrupt sb-unix:sigpipe :default)
                   (%execve program argv envp))
                 (%signal-pty-child-ready ready-fd +pty-child-ready-error+)
                 (setf ready-fd nil)
                 (%pty-child-fail))
            (when slave-fd (%pty-close-fd slave-fd)))))
    (error ()
      (%signal-pty-child-ready ready-fd +pty-child-ready-error+)
      (%pty-child-fail))))
#+darwin
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
                 (let ((offset 0)
                       (eof-p nil)
                       (pointer (sb-alien:alien-sap
                                 (sb-alien:addr error-number))))
                   (loop until (or eof-p (= offset 4))
                         do (multiple-value-bind (count errno)
                                (sb-unix:unix-read
                                 fd
                                 (sb-sys:sap+ pointer offset)
                                 (- 4 offset))
                              (cond
                                ((null count)
                                 (unless (= errno sb-posix:eintr)
                                   (error "PTY bootstrap error pipe read failed (errno ~d)"
                                          errno)))
                                ((zerop count)
                                 (if (zerop offset)
                                     (setf eof-p t)
                                     (error "PTY bootstrap error pipe record was truncated")))
                                (t
                                 (incf offset count)))))
                   (unless eof-p
                     error-number))))
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
