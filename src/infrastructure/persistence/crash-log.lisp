;;; Crash log capture and storage (task P0-4).
(in-package #:nshell.infrastructure.persistence)

(defparameter +crash-backtrace-frame-limit+ 256
  "Frame names kept for finding the innermost nshell frame. Deep recursion
fills the top of the stack with one user function, so the nshell frame that
called it can be far down.")

(defparameter +crash-argument-frame-limit+ 40
  "Frames whose arguments are printed, counted from the innermost.")

(defparameter +crash-argument-text-limit+ 300)

(defparameter +crash-log-name-attempts+ 100
  "Names tried before giving up when crash log names collide. Collisions need
several crashes in the same microsecond, so the limit only stops a loop.")

(nshell.util:define-value-struct crash-record
    ((condition nil)
     (frame-names nil :copy :list)
     (frame-arguments nil :copy :list))
  :keyword-constructor t
  :documentation
  "A crash captured before unwinding: the condition, the backtrace frame
names innermost first, and each frame's printed arguments (NIL entries when
they were not captured).")

(defun %crash-signal-frame-p (name)
  (eq name 'sb-kernel::%signal))

(defun %crash-drop-handler-frames (frames)
  "Drop the frames of the handler and the signalling machinery from the top of
FRAMES. ERROR sets the debugger's stack top hint so they are usually absent,
but a condition raised with SIGNAL leaves them in."
  (let ((signal-position
          (position-if #'%crash-signal-frame-p frames
                       :key #'first :end (min 16 (length frames)))))
    (if signal-position
        (nthcdr (1+ signal-position) frames)
        frames)))

(defun %crash-arguments-text (arguments)
  (handler-case
      (let* ((*print-readably* nil)
             (*print-pretty* nil)
             (*print-circle* nil)
             (*print-array* nil)
             (*print-length* 8)
             (*print-level* 3)
             (text (format nil "~{~s~^ ~}" arguments)))
        (if (> (length text) +crash-argument-text-limit+)
            (concatenate 'string
                         (subseq text 0 +crash-argument-text-limit+) "...")
            text))
    (serious-condition ()
      "#<arguments could not be printed>")))

(defun capture-crash (condition)
  "Capture CONDITION and its backtrace. Call it from a HANDLER-BIND handler,
before the stack unwinds, and do the rest of the work after unwinding.

Arguments are printed only for ordinary errors. A storage-condition may mean the
control stack or the heap is nearly exhausted, and printing runs arbitrary
PRINT-OBJECT methods, so only frame names are kept. If capturing itself fails,
the record has no frames; this function does not signal."
  (let* ((storage-p (typep condition 'storage-condition))
         (frames
           (handler-case
               (%crash-drop-handler-frames
                (sb-debug:list-backtrace
                 :count (+ +crash-backtrace-frame-limit+ 16)))
             (serious-condition () nil)))
         (frames (subseq frames 0 (min +crash-backtrace-frame-limit+
                                       (length frames)))))
    (%make-crash-record
     :condition condition
     :frame-names (mapcar #'first frames)
     :frame-arguments (if storage-p
                          nil
                          (loop for frame in frames
                                repeat +crash-argument-frame-limit+
                                collect (%crash-arguments-text (rest frame)))))))

(defun %crash-home-directory ()
  (let ((home (nshell.infrastructure.acl:current-environment-value "HOME")))
    (if (and home (plusp (length home)))
        home
        (namestring (user-homedir-pathname)))))

(defun crash-log-directory-path ()
  "Return the crash log directory for the current environment."
  (nshell.domain.crash:crash-log-directory
   (nshell.infrastructure.acl:current-environment-value "XDG_STATE_HOME")
   (%crash-home-directory)))

(defun %ensure-crash-log-directory (directory)
  "Create DIRECTORY and missing parents with mode 0700, then open DIRECTORY
without following a symlink and set its mode to 0700."
  (labels ((ensure (path)
             (let ((parent (uiop:pathname-parent-directory-pathname path)))
               (unless (or (equal parent path) (probe-file path))
                 (ensure parent)
                 (let ((native (string-right-trim
                                "/" (sb-ext:native-namestring path))))
                   (handler-case
                       (progn
                         (sb-posix:mkdir native #o700)
                         ;; The umask applies to mkdir; a directory this
                         ;; function made must still be traversable by us.
                         (sb-posix:chmod native #o700))
                     (sb-posix:syscall-error (condition)
                       (unless (= (sb-posix:syscall-errno condition)
                                  sb-posix:eexist)
                         (error condition)))))))))
    ;; Native parsing keeps * and [ in XDG_STATE_HOME from becoming wildcards.
    (ensure (sb-ext:parse-native-namestring directory nil
                                            *default-pathname-defaults*
                                            :as-directory t)))
  ;; O_DIRECTORY makes open fail with ENOTDIR on anything else. Without it, a
  ;; FIFO at this path would block the open until a writer appeared.
  (let ((fd (sb-posix:open (string-right-trim "/" directory)
                           (logior sb-posix:o-rdonly sb-posix:o-nofollow
                                   sb-posix:o-directory))))
    (unwind-protect
         (progn
           (unless (sb-posix:s-isdir (sb-posix:stat-mode (sb-posix:fstat fd)))
             (error "Crash log path ~a is not a directory." directory))
           (sb-posix:fchmod fd #o700))
      (sb-posix:close fd))))

(defun %open-new-crash-log (directory unix-seconds microseconds)
  "Create a crash log file that did not exist before; return its fd and path."
  (loop for attempt from 0 below +crash-log-name-attempts+
        for path = (concatenate 'string directory
                                (nshell.domain.crash:crash-log-file-name
                                 unix-seconds microseconds attempt))
        do (handler-case
               (return
                 (values (sb-posix:open path
                                        (logior sb-posix:o-wronly
                                                sb-posix:o-creat
                                                sb-posix:o-excl
                                                sb-posix:o-nofollow)
                                        #o600)
                         path))
             (sb-posix:syscall-error (condition)
               (unless (= (sb-posix:syscall-errno condition) sb-posix:eexist)
                 (error condition))))
        finally (error "No free crash log name in ~a." directory)))

(defun write-crash-report (crash)
  "Write CRASH as a new file in the crash log directory and return the path,
with HOME shown as ~. Signals an error when the log cannot be written."
  (multiple-value-bind (unix-seconds microseconds) (sb-ext:get-time-of-day)
    (let* ((home (%crash-home-directory))
           (condition (crash-record-condition crash))
           (directory (crash-log-directory-path))
           (text (nshell.domain.crash:render-crash-log
                  :time (nshell.domain.crash:crash-time-string
                         unix-seconds microseconds)
                  :condition-type (type-of condition)
                  :message (handler-case (princ-to-string condition)
                             (serious-condition ()
                               "#<condition report failed>"))
                  :frame-names (crash-record-frame-names crash)
                  :frame-arguments (crash-record-frame-arguments crash)
                  :home home
                  :lisp-version (format nil "~a ~a"
                                        (lisp-implementation-type)
                                        (lisp-implementation-version)))))
      (%ensure-crash-log-directory directory)
      (multiple-value-bind (fd path)
          (%open-new-crash-log directory unix-seconds microseconds)
        ;; The umask may have removed bits from #o600; set the mode exactly.
        (let ((stream (handler-case
                          (progn
                            (sb-posix:fchmod fd #o600)
                            (sb-sys:make-fd-stream fd
                                                   :output t
                                                   :element-type 'character
                                                   :external-format :utf-8
                                                   :auto-close t))
                        (error (condition)
                          (sb-posix:close fd)
                          (error condition)))))
          (unwind-protect
               (write-string text stream)
            (close stream)))
        (nshell.domain.crash:replace-home-directory path home)))))
