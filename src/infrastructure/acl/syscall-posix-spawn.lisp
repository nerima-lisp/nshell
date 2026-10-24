(in-package #:nshell.infrastructure.acl)

(sb-alien:define-alien-routine ("posix_spawn" %posix-spawn) sb-alien:int
  (pid (* sb-alien:int))
  (path sb-alien:c-string)
  (file-actions sb-sys:system-area-pointer)
  (attributes sb-sys:system-area-pointer)
  (argv (* sb-alien:c-string))
  (environment (* sb-alien:c-string)))

(sb-alien:define-alien-routine ("posix_spawn_file_actions_init"
                                %posix-spawn-file-actions-init) sb-alien:int
  (actions sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("posix_spawn_file_actions_destroy"
                                %posix-spawn-file-actions-destroy) sb-alien:int
  (actions sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("posix_spawn_file_actions_adddup2"
                                %posix-spawn-file-actions-adddup2) sb-alien:int
  (actions sb-sys:system-area-pointer)
  (source sb-alien:int)
  (target sb-alien:int))
(sb-alien:define-alien-routine ("posix_spawn_file_actions_addclose"
                                %posix-spawn-file-actions-addclose) sb-alien:int
  (actions sb-sys:system-area-pointer)
  (fd sb-alien:int))
#+darwin
(sb-alien:define-alien-routine ("posix_spawn_file_actions_addinherit_np"
                                %posix-spawn-file-actions-addinherit) sb-alien:int
  (actions sb-sys:system-area-pointer)
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("posix_spawnattr_init"
                                %posix-spawnattr-init) sb-alien:int
  (attributes sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("posix_spawnattr_destroy"
                                %posix-spawnattr-destroy) sb-alien:int
  (attributes sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("posix_spawnattr_setflags"
                                %posix-spawnattr-setflags) sb-alien:int
  (attributes sb-sys:system-area-pointer)
  (flags sb-alien:short))
(sb-alien:define-alien-routine ("posix_spawnattr_setpgroup"
                                %posix-spawnattr-setpgroup) sb-alien:int
  (attributes sb-sys:system-area-pointer)
  (pgid sb-alien:int))
(sb-alien:define-alien-routine ("posix_spawnattr_setsigdefault"
                                %posix-spawnattr-setsigdefault) sb-alien:int
  (attributes sb-sys:system-area-pointer)
  (signals sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("posix_spawnattr_setsigmask"
                                %posix-spawnattr-setsigmask) sb-alien:int
  (attributes sb-sys:system-area-pointer)
  (signals sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("sigemptyset" %posix-sigemptyset) sb-alien:int
  (signals sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("sigaddset" %posix-sigaddset) sb-alien:int
  (signals sb-sys:system-area-pointer)
  (signal sb-alien:int))

(sb-alien:define-alien-routine ("pipe" %posix-pipe) sb-alien:int
  (fds sb-sys:system-area-pointer))
#+linux
(sb-alien:define-alien-routine ("pipe2" %posix-pipe2) sb-alien:int
  (fds sb-sys:system-area-pointer)
  (flags sb-alien:int))

(defconstant +spawn-fd-cloexec+ 1)
(defconstant +spawn-f-getfd+ 1)
(defconstant +spawn-f-setfd+ 2)
(defconstant +spawn-f-dupfd+ 0)
(defconstant +spawn-posix-spawn-setpgroup+ #x02)
(defconstant +spawn-posix-spawn-setsigdef+ #x04)
(defconstant +spawn-posix-spawn-setsigmask+ #x08)
(defconstant +spawn-posix-spawn-cloexec-default+ #x4000)
(defconstant +spawn-opaque-storage-words+ 64)
(defconstant +spawn-linux-o-cloexec+ #o2000000)
(defconstant +spawn-darwin-o-cloexec+ #x01000000)

(defstruct (%native-spawn-channel
            (:constructor %make-native-spawn-channel
                (child-fd parent-fd process-stream copy-source copy-destination
                 direction)))
  child-fd
  parent-fd
  process-stream
  copy-source
  copy-destination
  direction)

(defstruct (native-process
            (:constructor %make-native-process (pid pgid)))
  pid
  pgid
  (%status :running)
  (%exit-code nil)
  input
  output
  error
  (input-copier-threads nil)
  (output-copier-threads nil)
  (status-lock (sb-thread:make-mutex :name "native process status")))

(defun native-process-status (process)
  (%refresh-native-process-status process)
  (sb-thread:with-mutex ((native-process-status-lock process))
    (native-process-%status process)))

(defun (setf native-process-status) (status process)
  (sb-thread:with-mutex ((native-process-status-lock process))
    (setf (native-process-%status process) status)))

(defun native-process-exit-code (process)
  (%refresh-native-process-status process)
  (sb-thread:with-mutex ((native-process-status-lock process))
    (native-process-%exit-code process)))

(defun (setf native-process-exit-code) (exit-code process)
  (sb-thread:with-mutex ((native-process-status-lock process))
    (setf (native-process-%exit-code process) exit-code)))

(defvar *native-process-registry* (make-hash-table))
(defvar *native-process-registry-lock*
  (sb-thread:make-mutex :name "native process registry"))
(defvar *native-process-waitpid-lock*
  (sb-thread:make-mutex :name "native process waitpid"))

(defun %register-native-process (process)
  (sb-thread:with-mutex (*native-process-registry-lock*)
    (setf (gethash (native-process-pid process) *native-process-registry*)
          process))
  process)

(defun %unregister-native-process (process)
  (sb-thread:with-mutex (*native-process-registry-lock*)
    (when (eq (gethash (native-process-pid process) *native-process-registry*)
              process)
      (remhash (native-process-pid process) *native-process-registry*)))
  process)

(defun %native-process-terminal-status-p (status)
  (member status '(:exited :signaled) :test #'eq))

(defun %record-native-wait-status (process wait-status)
  (multiple-value-bind (pid status detail)
      (%decode-wait-status (native-process-pid process) wait-status)
    (declare (ignore pid))
    (sb-thread:with-mutex ((native-process-status-lock process))
      (case status
        (:stopped
         (setf (native-process-%status process) :stopped
               (native-process-%exit-code process) nil))
        (:continued
         (setf (native-process-%status process) :running
               (native-process-%exit-code process) nil))
        (:exited
         (setf (native-process-%status process) :exited
               (native-process-%exit-code process) detail))
        (:signaled
         (setf (native-process-%status process) :signaled
               (native-process-%exit-code process) detail))))
    (when (%native-process-terminal-status-p status)
      (%unregister-native-process process))
    status))

(defun %refresh-native-process-from-wait-status (pid wait-status)
  (let ((process
          (sb-thread:with-mutex (*native-process-registry-lock*)
            (gethash pid *native-process-registry*))))
    (when process
      (%record-native-wait-status process wait-status))))

(defun %native-process-wait-flags ()
  (let ((flags (logior sb-posix:wnohang sb-posix:wuntraced)))
    (let ((continued (find-symbol "WCONTINUED" "SB-POSIX")))
      (when (and continued (boundp continued))
        (setf flags (logior flags (symbol-value continued)))))
    flags))

(defun %refresh-native-process-status (process)
  (let ((wait-status nil)
        (terminal-p nil))
    (sb-thread:with-mutex (*native-process-waitpid-lock*)
      (sb-thread:with-mutex ((native-process-status-lock process))
        (unless (%native-process-terminal-status-p
                 (native-process-%status process))
          (handler-case
              (multiple-value-bind (pid status)
                  (sb-posix:waitpid (native-process-pid process)
                                    (%native-process-wait-flags))
                (when (plusp pid)
                  (setf wait-status status)))
            (sb-posix:syscall-error (condition)
              (let ((errno (sb-posix:syscall-errno condition)))
                (cond
                  ((= errno sb-posix:eintr))
                  ((= errno sb-posix:echild)
                   (setf (native-process-%status process) :exited
                         (native-process-%exit-code process) nil
                         terminal-p t))
                  (t (error condition)))))))
        (when (%native-process-terminal-status-p
               (native-process-%status process))
          (setf terminal-p t)))
      (when wait-status
        (%refresh-native-process-from-wait-status
         (native-process-pid process) wait-status))
      (when terminal-p
        (%unregister-native-process process)))
  process))

(defun %wait-native-process (process &optional check-for-stopped)
  (loop for status = (native-process-status process)
        when (or (%native-process-terminal-status-p status)
                 (and check-for-stopped (eq status :stopped)))
          do (when (%native-process-terminal-status-p status)
               (%finish-native-process-copiers process))
             (return status)
        do (sb-sys:serve-all-events 0.01)))

(defun %native-process-alive-p (process)
  (member (native-process-status process) '(:running :stopped) :test #'eq))

(defun %native-process-exit-status-code (process)
  (let ((status (native-process-status process)))
    (unless (%native-process-terminal-status-p status)
      (%wait-native-process process)
      (setf status (native-process-status process)))
    (let ((code (native-process-exit-code process)))
      (if (eq status :signaled)
          (+ 128 (or code 0))
          (or code 0)))))

(defun %native-process-kill (process signal)
  (handler-case
      (progn
        (sb-posix:kill (native-process-pid process) signal)
        (values t 0))
    (sb-posix:syscall-error (condition)
      (values nil (sb-posix:syscall-errno condition)))))

(defun %native-process-close (process)
  (let ((threads (append (native-process-input-copier-threads process)
                         (native-process-output-copier-threads process))))
    (dolist (thread threads)
      (when (sb-thread:thread-alive-p thread)
        (ignore-errors (sb-thread:terminate-thread thread))))
    (dolist (thread threads)
      (ignore-errors (sb-thread:join-thread thread)))
    (setf (native-process-input-copier-threads process) nil
          (native-process-output-copier-threads process) nil))
  (dolist (stream (remove-duplicates
                   (list (native-process-input process)
                         (native-process-output process)
                         (native-process-error process))
                   :test #'eq))
    (when stream (ignore-errors (close stream))))
  process)

(defun process-input (process)
  (cond
    ((native-process-p process) (native-process-input process))
    ((pty-process-p process) (pty-process-stream process))
    (t (sb-ext:process-input process))))

(defun process-output (process)
  (cond
    ((native-process-p process) (native-process-output process))
    ((pty-process-p process) (pty-process-stream process))
    (t (sb-ext:process-output process))))

(defun process-error (process)
  (cond
    ((native-process-p process) (native-process-error process))
    ((pty-process-p process) nil)
    (t (sb-ext:process-error process))))

(defun process-close (process)
  (cond
    ((native-process-p process) (%native-process-close process))
    ((pty-process-p process)
     (error "Generic process-close does not support PTY processes"))
    (t (sb-ext:process-close process))))

(defun %mark-native-process-running (process)
  (sb-thread:with-mutex ((native-process-status-lock process))
    (setf (native-process-%status process) :running
          (native-process-%exit-code process) nil))
  process)

(defun %finish-native-process-copiers (process)
  (dolist (thread (native-process-input-copier-threads process))
    (when (sb-thread:thread-alive-p thread)
      (ignore-errors (sb-thread:terminate-thread thread)))
    (ignore-errors (sb-thread:join-thread thread)))
  (dolist (thread (native-process-output-copier-threads process))
    (ignore-errors (sb-thread:join-thread thread)))
  (setf (native-process-input-copier-threads process) nil
        (native-process-output-copier-threads process) nil)
  process)

(defun %spawn-check-result (operation result)
  (unless (zerop result)
    (error "~a failed (errno ~d)" operation result))
  result)

(defun %spawn-set-close-on-exec (fd)
  (let ((flags (sb-posix:fcntl fd +spawn-f-getfd+)))
    (sb-posix:fcntl fd +spawn-f-setfd+
                    (logior flags +spawn-fd-cloexec+)))
  fd)

(defun %spawn-ensure-fd-above-stdio (fd)
  (if (>= fd 3)
      fd
      (let ((new-fd (sb-posix:fcntl fd +spawn-f-dupfd+ 3)))
        (handler-case
            (progn
              (%spawn-set-close-on-exec new-fd)
              (sb-posix:close fd))
          (error (condition)
            (ignore-errors (sb-posix:close new-fd))
            (error condition)))
        new-fd)))

(defun %spawn-pipe ()
  (let ((fds (sb-alien:make-alien sb-alien:int 2))
        (read-fd nil)
        (write-fd nil)
        (complete nil))
    (unwind-protect
         (progn
           (%spawn-check-result
            "pipe"
            #+linux (%posix-pipe2 (sb-alien:alien-sap fds)
                                  +spawn-linux-o-cloexec+)
            #+darwin (%posix-pipe (sb-alien:alien-sap fds)))
           (setf read-fd (sb-alien:deref fds 0)
                 write-fd (sb-alien:deref fds 1)
                 read-fd (%spawn-ensure-fd-above-stdio read-fd)
                 write-fd (%spawn-ensure-fd-above-stdio write-fd)
                 complete t)
           (values read-fd write-fd))
      (sb-alien:free-alien fds)
      (unless complete
        (when read-fd (ignore-errors (sb-posix:close read-fd)))
        (when write-fd (ignore-errors (sb-posix:close write-fd)))))))

(defun %spawn-open-null (direction)
  (let* ((flags (logior (if (eq direction :input)
                            sb-posix:o-rdonly
                            sb-posix:o-wronly)
                        #+linux +spawn-linux-o-cloexec+
                        #+darwin +spawn-darwin-o-cloexec+))
         (fd (sb-posix:open "/dev/null" flags))
         (complete nil))
    (unwind-protect
         (prog1 (setf fd (%spawn-ensure-fd-above-stdio fd))
           (setf complete t))
      (unless complete
        (ignore-errors (sb-posix:close fd))))))

(defun %spawn-open-path (path direction)
  (let* ((path (if (pathnamep path) (namestring path) path))
         (flags (if (eq direction :input)
                    sb-posix:o-rdonly
                    (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-trunc)))
         (flags (logior flags
                        #+linux +spawn-linux-o-cloexec+
                        #+darwin +spawn-darwin-o-cloexec+))
         (fd (sb-posix:open path flags #o666))
         (complete nil))
    (unwind-protect
         (prog1 (setf fd (%spawn-ensure-fd-above-stdio fd))
           (setf complete t))
      (unless complete
        (ignore-errors (sb-posix:close fd))))))

(defun %spawn-fd-open-p (fd)
  (and (integerp fd)
       (not (minusp fd))
       (ignore-errors (sb-posix:fcntl fd +spawn-f-getfd+))
       t))

(defun %spawn-stream-fd (stream direction)
  (typecase stream
    (sb-impl::fd-stream
     (let ((fd (sb-impl::fd-stream-fd stream)))
       (when (and (%spawn-fd-open-p fd)
                  (if (eq direction :input)
                      (input-stream-p stream)
                      (output-stream-p stream)))
         fd)))
    (synonym-stream
     (let ((symbol (synonym-stream-symbol stream)))
       (when (boundp symbol)
         (%spawn-stream-fd (symbol-value symbol) direction))))
    (two-way-stream
     (%spawn-stream-fd (if (eq direction :input)
                           (two-way-stream-input-stream stream)
                           (two-way-stream-output-stream stream))
                       direction))))

(defun %spawn-copy-element-type (stream)
  (let ((type (stream-element-type stream)))
    (cond
      ((nth-value 0 (subtypep type 'character)) 'character)
      ((nth-value 0 (subtypep type '(unsigned-byte 8))) '(unsigned-byte 8))
      (t (error "Cannot copy subprocess data through stream element type ~s"
                type)))))

(defun %spawn-stream-copy-buffer (stream)
  (make-array 4096 :element-type (%spawn-copy-element-type stream)))

(defun %spawn-copy-input (source child-stream &optional close-source-p)
  (unwind-protect
       (let ((buffer (%spawn-stream-copy-buffer source)))
         (loop for count = (read-sequence buffer source)
               while (plusp count)
               do (write-sequence buffer child-stream :end count))
         (finish-output child-stream))
    (unwind-protect
         (close child-stream)
      (when close-source-p
        (close source)))))

(defun %spawn-copy-output (child-stream destination)
  (unwind-protect
       (let ((buffer (%spawn-stream-copy-buffer destination)))
         (loop for count = (read-sequence buffer child-stream)
               while (plusp count)
               do (write-sequence buffer destination :end count))
         (finish-output destination))
    (close child-stream)))

(defun %spawn-make-channel (spec direction target)
  (cond
    ((eq spec :stream)
     (multiple-value-bind (read-fd write-fd) (%spawn-pipe)
       (if (eq direction :input)
           (values (%make-native-spawn-channel
                    read-fd write-fd :stream nil nil direction)
                   (list read-fd write-fd))
           (values (%make-native-spawn-channel
                    write-fd read-fd :stream nil nil direction)
                   (list read-fd write-fd)))))
    ((eq spec t)
     (values (%make-native-spawn-channel
              (and (%spawn-fd-open-p target) target)
              nil nil nil nil direction)
             nil))
    ((null spec)
     (let ((fd (%spawn-open-null direction)))
       (values (%make-native-spawn-channel fd nil nil nil nil direction)
               (list fd))))
    ((and (eq direction :error) (eq spec :output))
     (error "The :OUTPUT error stream must reuse the stdout channel"))
    ((integerp spec)
     (unless (%spawn-fd-open-p spec)
       (error "Invalid subprocess file descriptor: ~s" spec))
     (values (%make-native-spawn-channel spec nil nil nil nil direction) nil))
    ((or (pathnamep spec) (stringp spec))
     (let ((fd (%spawn-open-path spec direction)))
       (values (%make-native-spawn-channel fd nil nil nil nil direction)
               (list fd))))
    ((streamp spec)
     (let ((fd (%spawn-stream-fd spec direction)))
       (if fd
           (values (%make-native-spawn-channel fd nil nil nil nil direction)
                   nil)
           (multiple-value-bind (read-fd write-fd) (%spawn-pipe)
             (if (eq direction :input)
                 (values (%make-native-spawn-channel
                          read-fd write-fd nil spec nil direction)
                         (list read-fd write-fd))
                 (values (%make-native-spawn-channel
                          write-fd read-fd nil nil spec direction)
                         (list read-fd write-fd)))))))
    (t
     (error "Unsupported subprocess ~a designator: ~s" direction spec))))

(defun %spawn-stabilize-stdio-mappings (mappings owned-fds)
  (let ((destinations (mapcar #'second mappings))
        (stable nil))
    (dolist (mapping mappings)
      (destructuring-bind (source target) mapping
        (if (and (/= source target)
                 (< source 3)
                 (member source destinations))
            (let ((duplicate (sb-posix:fcntl source +spawn-f-dupfd+ 3)))
              (handler-case
                  (%spawn-set-close-on-exec duplicate)
                (error (condition)
                  (ignore-errors (sb-posix:close duplicate))
                  (error condition)))
              (pushnew duplicate owned-fds)
              (push (list duplicate target) stable))
            (push mapping stable))))
    (values (nreverse stable) owned-fds)))

(defun %spawn-open-fds ()
  #+linux
  (progn
    (unless (probe-file #p"/proc/self/fd/")
      (error "Cannot enumerate open file descriptors through /proc/self/fd"))
    (loop for path in (directory #p"/proc/self/fd/*")
          for fd = (ignore-errors
                     (parse-integer (file-namestring path) :junk-allowed t))
          when (and fd (integerp fd) (%spawn-fd-open-p fd))
            collect fd))
  #+darwin
  nil)

(defun %spawn-add-file-actions (actions mappings preserve-fds)
  (dolist (mapping mappings)
    (%spawn-check-result
     "posix_spawn_file_actions_adddup2"
     (%posix-spawn-file-actions-adddup2 actions (first mapping)
                                        (second mapping))))
  #+darwin
  (dolist (fd preserve-fds)
    (%spawn-check-result
     "posix_spawn_file_actions_addinherit_np"
     (%posix-spawn-file-actions-addinherit actions fd)))
  (dolist (fd (%spawn-open-fds))
    (when (and (>= fd 3)
               (not (member fd preserve-fds)))
      (%spawn-check-result
       "posix_spawn_file_actions_addclose"
       (%posix-spawn-file-actions-addclose actions fd))))
  actions)

(defun %spawn-default-signal-numbers ()
  (loop for name in '("SIGINT" "SIGQUIT" "SIGTERM" "SIGPIPE" "SIGALRM"
                      "SIGUSR1" "SIGUSR2" "SIGCHLD" "SIGCONT" "SIGTSTP"
                      "SIGTTIN" "SIGTTOU" "SIGWINCH")
        for symbol = (find-symbol name "SB-UNIX")
        when (and symbol (boundp symbol))
          collect (symbol-value symbol)))

(defun %spawn-configure-attributes (attributes process-group)
  (let ((flags 0)
        (signals (sb-alien:make-alien sb-alien:unsigned-long 16)))
    (unwind-protect
         (progn
           (when (and process-group (not (eq process-group :inherit)))
             (%spawn-check-result
              "posix_spawnattr_setpgroup"
              (%posix-spawnattr-setpgroup
               attributes (if (eq process-group :new) 0 process-group)))
             (setf flags (logior flags +spawn-posix-spawn-setpgroup+)))
           (%spawn-check-result "sigemptyset"
                                (%posix-sigemptyset (sb-alien:alien-sap signals)))
           (dolist (signal (%spawn-default-signal-numbers))
             (unless (member signal (list sb-unix:sigkill sb-unix:sigstop))
               (%spawn-check-result
                "sigaddset"
                (%posix-sigaddset (sb-alien:alien-sap signals) signal))))
           (%spawn-check-result
            "posix_spawnattr_setsigdefault"
            (%posix-spawnattr-setsigdefault attributes
                                             (sb-alien:alien-sap signals)))
           (setf flags (logior flags +spawn-posix-spawn-setsigdef+))
           (%spawn-check-result "sigemptyset"
                                (%posix-sigemptyset (sb-alien:alien-sap signals)))
           (%spawn-check-result
            "posix_spawnattr_setsigmask"
            (%posix-spawnattr-setsigmask attributes
                                          (sb-alien:alien-sap signals)))
           (setf flags (logior flags +spawn-posix-spawn-setsigmask+))
           #+darwin
           (setf flags (logior flags +spawn-posix-spawn-cloexec-default+))
           (%spawn-check-result
            "posix_spawnattr_setflags"
            (%posix-spawnattr-setflags attributes flags)))
      (sb-alien:free-alien signals))))

(defun %spawn-c-string-vector (strings)
  (let* ((count (length strings))
         (vector (sb-alien:make-alien sb-alien:c-string (1+ count))))
    (loop for string in strings
          for index from 0
          do (when (find #\Null string)
               (error "Subprocess argument contains NUL"))
             (setf (sb-alien:deref vector index) string))
    (setf (sb-alien:deref vector count) nil)
    vector))

(defun %spawn-free-c-string-vector (vector)
  (when vector
    (ignore-errors (sb-alien:free-alien vector))))

(defun %spawn-validate-inputs (program args environment preserve-fds process-group)
  (check-type program string)
  (check-type args list)
  (check-type environment list)
  (unless (every #'stringp args)
    (error "Subprocess arguments must all be strings"))
  (unless (every #'stringp environment)
    (error "Subprocess environment entries must all be strings"))
  (unless (and (listp preserve-fds) (every (lambda (fd)
                                            (and (integerp fd) (>= fd 0)))
                                          preserve-fds))
    (error "Preserved descriptors must be nonnegative integers"))
  (unless (or (null process-group)
              (member process-group '(:new :inherit) :test #'eq)
              (and (integerp process-group) (plusp process-group)))
    (error "Invalid subprocess process group: ~s" process-group))
  (when (find #\Null program)
    (error "Subprocess program contains NUL"))
  (when (some (lambda (string) (find #\Null string))
              (append args environment))
    (error "Subprocess argument or environment contains NUL"))
  t)

(defun %spawn-parent-stream (channel owned-fds &optional close-copy-source-p)
  (let ((fd (%native-spawn-channel-parent-fd channel)))
    (cond
      ((null fd)
       (values (%native-spawn-channel-process-stream channel) nil owned-fds))
      ((eq (%native-spawn-channel-process-stream channel) :stream)
       (let ((stream nil))
         (handler-case
             (progn
               (setf stream
                     (if (eq (%native-spawn-channel-direction channel) :input)
                         (sb-sys:make-fd-stream fd :output t :element-type :default
                                                :external-format :default
                                                :buffering :line :auto-close t)
                         (sb-sys:make-fd-stream fd :input t :element-type :default
                                                :external-format :default
                                                :buffering :line :auto-close t)))
               (values stream nil (remove fd owned-fds :test #'eql)))
           (error (condition)
             (when stream (ignore-errors (close stream)))
             (error condition)))))
      ((%native-spawn-channel-copy-source channel)
       (let ((stream nil)
             (thread nil))
         (handler-case
             (progn
               (setf stream
                     (sb-sys:make-fd-stream
                      fd :output t
                      :element-type (%spawn-copy-element-type
                                     (%native-spawn-channel-copy-source channel))
                      :external-format :default :auto-close t)
                     owned-fds (remove fd owned-fds :test #'eql)
                     thread
                     (sb-thread:make-thread
                      (lambda ()
                        (%spawn-copy-input
                         (%native-spawn-channel-copy-source channel) stream
                         close-copy-source-p))
                      :name "native process input copier"))
               (values nil thread owned-fds))
           (error (condition)
             (when stream (ignore-errors (close stream)))
             (error condition)))))
      ((%native-spawn-channel-copy-destination channel)
       (let ((stream nil)
             (thread nil))
         (handler-case
             (progn
               (setf stream
                     (sb-sys:make-fd-stream
                      fd :input t
                      :element-type (%spawn-copy-element-type
                                     (%native-spawn-channel-copy-destination channel))
                      :external-format :default :auto-close t)
                     owned-fds (remove fd owned-fds :test #'eql)
                     thread
                     (sb-thread:make-thread
                      (lambda ()
                        (%spawn-copy-output
                         stream
                         (%native-spawn-channel-copy-destination channel)))
                      :name "native process output copier"))
               (values nil thread owned-fds))
           (error (condition)
             (when stream (ignore-errors (close stream)))
             (error condition)))))
      (t
       (values nil nil owned-fds)))))

(defun %spawn-posix-process
    (program args environment &key input output (error nil error-supplied-p)
                               process-group preserve-fds input-source-owned-p)
  (%spawn-validate-inputs program args environment preserve-fds process-group)
  #-(or darwin linux)
  (error "posix_spawn backend is unsupported on this platform")
  #+(or darwin linux)
  (let ((owned-fds nil)
        (process nil)
        (pid nil)
        (complete nil)
        (input-source-transferred-p nil))
    (unwind-protect
         (let* ((input-channel nil)
                (output-channel nil)
                (error-channel nil)
                (effective-error (if error-supplied-p error :output))
                (actions (sb-alien:make-alien sb-alien:unsigned-long
                                              +spawn-opaque-storage-words+))
                (attributes (sb-alien:make-alien sb-alien:unsigned-long
                                                  +spawn-opaque-storage-words+))
                (actions-initialized nil)
                (attributes-initialized nil))
           (unwind-protect
                (progn
                  (multiple-value-bind (channel channel-fds)
                      (%spawn-make-channel input :input 0)
                    (setf input-channel channel
                          owned-fds (nconc owned-fds channel-fds)))
                  (multiple-value-bind (channel channel-fds)
                      (%spawn-make-channel output :output 1)
                    (setf output-channel channel
                          owned-fds (nconc owned-fds channel-fds)))
                  (if (eq effective-error :output)
                      (setf error-channel output-channel)
                      (multiple-value-bind (channel channel-fds)
                          (%spawn-make-channel effective-error :error 2)
                        (setf error-channel channel
                              owned-fds (nconc owned-fds channel-fds))))
                  (%spawn-check-result
                   "posix_spawn_file_actions_init"
                   (%posix-spawn-file-actions-init (sb-alien:alien-sap actions)))
                  (setf actions-initialized t)
                  (%spawn-check-result
                   "posix_spawnattr_init"
                   (%posix-spawnattr-init (sb-alien:alien-sap attributes)))
                  (setf attributes-initialized t)
                  (multiple-value-bind (mappings updated-owned-fds)
                      (%spawn-stabilize-stdio-mappings
                       (loop for channel in (list input-channel output-channel
                                               error-channel)
                             for target from 0
                             for fd = (%native-spawn-channel-child-fd channel)
                             when fd collect (list fd target))
                       owned-fds)
                    (setf owned-fds updated-owned-fds)
                    (dolist (fd preserve-fds)
                      (unless (%spawn-fd-open-p fd)
                        (error "Preserved descriptor is not open: ~d" fd)))
                    (%spawn-add-file-actions
                     (sb-alien:alien-sap actions) mappings preserve-fds)
                    (%spawn-configure-attributes
                     (sb-alien:alien-sap attributes)
                     (or process-group :inherit))
                    (let ((argv (%spawn-c-string-vector (cons program args)))
                          (envp (%spawn-c-string-vector environment))
                          (pid-storage (sb-alien:make-alien sb-alien:int)))
                      (unwind-protect
                           (progn
                             (%spawn-check-result
                              "posix_spawn"
                              (%posix-spawn
                               (sb-alien:alien-sap pid-storage) program
                               (sb-alien:alien-sap actions)
                               (sb-alien:alien-sap attributes)
                               (sb-alien:alien-sap argv)
                               (sb-alien:alien-sap envp)))
                             (setf pid (sb-alien:deref pid-storage)
                                   process
                                   (%make-native-process
                                    pid
                                    (cond
                                      ((eq process-group :new) pid)
                                      ((integerp process-group) process-group)
                                      (t (ignore-errors
                                           (sb-posix:getpgid pid))))))
                             (%register-native-process process)
                             (let ((input-copier-threads nil)
                                   (output-copier-threads nil))
                               (multiple-value-bind (stream thread remaining-fds)
                                   (%spawn-parent-stream input-channel owned-fds input-source-owned-p)
                                 (setf (native-process-input process) stream
                                       owned-fds remaining-fds)
                                 (when thread
                                   (push thread input-copier-threads)
                                   (when input-source-owned-p
                                     (setf input-source-transferred-p t))))
                               (multiple-value-bind (stream thread remaining-fds)
                                   (%spawn-parent-stream output-channel owned-fds)
                                 (setf (native-process-output process) stream
                                       owned-fds remaining-fds)
                                 (when thread
                                   (push thread output-copier-threads)))
                               (if (eq error-channel output-channel)
                                   (setf (native-process-error process)
                                         (native-process-output process))
                                   (multiple-value-bind (stream thread remaining-fds)
                                       (%spawn-parent-stream error-channel owned-fds)
                                     (setf (native-process-error process) stream
                                           owned-fds remaining-fds)
                                     (when thread
                                       (push thread output-copier-threads))))
                               (setf (native-process-input-copier-threads process)
                                     (nreverse input-copier-threads)
                                     (native-process-output-copier-threads process)
                                     (nreverse output-copier-threads)))
                             (dolist (fd owned-fds)
                               (sb-posix:close fd))
                             (setf owned-fds nil
                                   complete t)
                             (return-from %spawn-posix-process
                               (values process input-source-transferred-p)))
                        (sb-alien:free-alien pid-storage)
                        (%spawn-free-c-string-vector argv)
                        (%spawn-free-c-string-vector envp))))
             (when attributes-initialized
               (%posix-spawnattr-destroy (sb-alien:alien-sap attributes)))
             (when actions-initialized
               (%posix-spawn-file-actions-destroy
                (sb-alien:alien-sap actions)))
             (sb-alien:free-alien attributes)
             (sb-alien:free-alien actions)))
      (unless complete
        (when process
          (%unregister-native-process process)
          (ignore-errors (%native-process-kill process sb-unix:sigkill))
          (ignore-errors (sb-posix:waitpid (native-process-pid process) 0))
          (%native-process-close process))
        (dolist (fd owned-fds)
          (ignore-errors (sb-posix:close fd)))))))
)
