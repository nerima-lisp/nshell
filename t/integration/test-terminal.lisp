(in-package #:nshell/test)

;;; Raw mode and the window-size query. Both talk to a tty, so the flag
;;; assertions run against a real pty pair from nshell.infrastructure.acl rather
;;; than fd 0, which is not a terminal under the test runner.

(defmacro with-pty-slave ((slave) &body body)
  "Run BODY with SLAVE bound to the slave fd of a fresh pty pair."
  (let ((master (gensym "MASTER-"))
        (name (gensym "NAME-")))
    `(multiple-value-bind (,master ,slave ,name) (nshell.infrastructure.acl:open-pty)
       (declare (ignore ,name))
       (unwind-protect (progn ,@body)
         (nshell.infrastructure.acl:pty-close ,master ,slave)))))

(defmacro with-pty-pair ((master slave) &body body)
  "Run BODY with MASTER and SLAVE bound to the two ends of a fresh pty pair."
  (let ((name (gensym "NAME-")))
    `(multiple-value-bind (,master ,slave ,name) (nshell.infrastructure.acl:open-pty)
       (declare (ignore ,name))
       (unwind-protect (progn ,@body)
         (nshell.infrastructure.acl:pty-close ,master ,slave)))))

(defun %unblock (fd)
  "Put FD into non-blocking mode so that reading an empty queue cannot hang."
  (sb-posix:fcntl fd sb-posix:f-setfl
                  (logior (sb-posix:fcntl fd sb-posix:f-getfl) sb-posix:o-nonblock))
  fd)

(defun %read-available (fd)
  "Whatever is queued on FD right now, as a string, or \"\" if nothing is.
FD must have been through %UNBLOCK: nshell.infrastructure.acl:pty-read signals on
the EAGAIN an empty non-blocking queue answers with, and an empty queue is a
result these tests want to assert on rather than an error."
  (let ((buffer (make-array 64 :element-type '(unsigned-byte 8))))
    (sb-sys:with-pinned-objects (buffer)
      (let ((count (sb-unix:unix-read fd (sb-sys:vector-sap buffer) 64)))
        (sb-ext:octets-to-string (subseq buffer 0 (or count 0)))))))

(defun %lflag (fd) (sb-posix:termios-lflag (sb-posix:tcgetattr fd)))
(defun %iflag (fd) (sb-posix:termios-iflag (sb-posix:tcgetattr fd)))
(defun %oflag (fd) (sb-posix:termios-oflag (sb-posix:tcgetattr fd)))
(defun %flag-set-p (flags bit) (not (zerop (logand flags bit))))

(defun %transient-lflag-bits ()
  "The lflag bits the tty driver owns rather than the caller.

FLUSHO and PENDIN are driver status, not settings: the kernel sets PENDIN when a
terminal re-enters canonical mode with input still queued, so a raw-then-restore
round trip legitimately comes back with a bit set that no tcsetattr of nshell's
ever wrote -- on Darwin, reproducibly. Comparing whole lflag words without
masking them therefore fails for a reason that has nothing to do with the code
under test. sb-posix does not name either constant, hence the literals."
  #+darwin #x20800000                   ; FLUSHO #x00800000 | PENDIN #x20000000
  #+linux #x5000                        ; FLUSHO #x1000     | PENDIN #x4000
  #-(or darwin linux) 0)

(defun %settings-lflag (fd)
  "FD's lflag with the driver's own status bits masked out."
  (logandc2 (%lflag fd) (%transient-lflag-bits)))

(describe "terminal-raw-mode-tests"
  (it "raw-mode-clears-only-the-line-editor-flags"
    "Raw mode turns off ICANON/ECHO/IXON/IXOFF and leaves ISIG and OPOST set.

This is a regression guard, not an implementation detail. nshell enables raw
mode once per session and keeps it while a foreground child runs, so ISIG is
what still turns ^C/^Z into SIGINT/SIGTSTP for that child, and OPOST is what
still maps LF to CR-LF for nshell's own output and the child's. A full
cfmakeraw-style mode -- cl-tty-kit:enable-raw-mode, for instance -- clears both
and would break foreground job interruption and multi-line rendering."
    #-(or darwin linux)
    (skip "PTY-backed terminal tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (with-pty-slave (fd)
      (nshell.infrastructure.terminal:enable-raw-mode fd)
      (expect (%flag-set-p (%lflag fd) sb-posix:icanon) :to-be-falsy)
      (expect (%flag-set-p (%lflag fd) sb-posix:echo) :to-be-falsy)
      (expect (%flag-set-p (%iflag fd) sb-posix:ixon) :to-be-falsy)
      (expect (%flag-set-p (%iflag fd) sb-posix:ixoff) :to-be-falsy)
      (expect (%flag-set-p (%lflag fd) sb-posix:isig) :to-be-truthy)
      (expect (%flag-set-p (%oflag fd) sb-posix:opost) :to-be-truthy)
      (nshell.infrastructure.terminal:restore-terminal-mode fd)))

  (it "raw-mode-enable-is-idempotent"
    "A second enable does not overwrite the saved settings, so one restore
still returns the terminal to how it started. shell-sigcont-handler re-enables
raw mode with no matching restore, which is exactly this case."
    #-(or darwin linux)
    (skip "PTY-backed terminal tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (with-pty-slave (fd)
      (let ((original-lflag (%settings-lflag fd)))
        (nshell.infrastructure.terminal:enable-raw-mode fd)
        (nshell.infrastructure.terminal:enable-raw-mode fd)
        (expect (%flag-set-p (%lflag fd) sb-posix:icanon) :to-be-falsy)
        (nshell.infrastructure.terminal:restore-terminal-mode fd)
        (expect original-lflag :to-equal (%settings-lflag fd)))))

  (it "raw-mode-keeps-saved-settings-per-fd"
    "Two fds in raw mode at once each restore their own settings."
    #-(or darwin linux)
    (skip "PTY-backed terminal tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (with-pty-slave (first-fd)
      (with-pty-slave (second-fd)
        (let ((first-original (%settings-lflag first-fd))
              (second-original (%settings-lflag second-fd)))
          (nshell.infrastructure.terminal:enable-raw-mode first-fd)
          (nshell.infrastructure.terminal:enable-raw-mode second-fd)
          (nshell.infrastructure.terminal:restore-terminal-mode first-fd)
          (expect first-original :to-equal (%settings-lflag first-fd))
          (expect (%flag-set-p (%lflag second-fd) sb-posix:icanon) :to-be-falsy)
          (nshell.infrastructure.terminal:restore-terminal-mode second-fd)
          (expect second-original :to-equal (%settings-lflag second-fd))))))

  (it "the-mode-transitions-do-not-discard-queued-input"
    "Input already queued on the terminal survives both the switch to raw mode
and the switch back.

This pins the tcsetattr action. Both transitions drain the output queue
themselves and then apply with TCSANOW, where they used to apply with TCSADRAIN
and let tcsetattr do the draining. TCSAFLUSH is the neighbouring constant and
reads like an equally good replacement for TCSADRAIN, but it discards the input
queue: a keystroke typed just as nshell finishes starting up, or just as ^Z
hands the terminal back, would vanish. Nothing else in this file would notice.

The input is queued from the master, and the echo it provokes is drained off the
master before raw mode is entered. That drain is not tidiness. Leaving output
queued on a slave nobody is reading and then calling ENABLE-RAW-MODE deadlocks
this thread outright -- the drain waits for a reader, and the reader would have
to be this same thread -- which is the wait the guarded region in raw-mode.lisp
was narrowed to exclude."
    #-(or darwin linux)
    (skip "PTY-backed terminal tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (with-pty-pair (master slave)
      (%unblock master)
      (%unblock slave)
      (nshell.infrastructure.acl:pty-write master (format nil "hi~%"))
      (%read-available master)          ; the slave's ECHO of that input
      (nshell.infrastructure.terminal:enable-raw-mode slave)
      (nshell.infrastructure.terminal:restore-terminal-mode slave)
      (expect (format nil "hi~%") :to-equal (%read-available slave))))

  (it "raw-mode-failure-signals-instead-of-being-swallowed"
    "A terminal that cannot be configured signals TERMINAL-MODE-OPERATION-FAILED.
The previous implementation wrapped the whole body in IGNORE-ERRORS, so a failed
tcsetattr left the terminal in an unknown state with no indication at all."
    (expect (lambda () (nshell.infrastructure.terminal:enable-raw-mode 9999))
            :to-throw 'nshell.infrastructure.terminal:terminal-mode-operation-failed))

  (it "restore-without-enable-is-a-no-op"
    "Restoring an fd that was never put into raw mode returns NIL and does not
signal, so the shutdown path is safe on a non-interactive session."
    (expect (nshell.infrastructure.terminal:restore-terminal-mode 9999)
            :to-be-falsy))
    (it "read-key-event-converts-an-interrupt-to-ctrl-c"
    "An interrupt predicate takes precedence over queued terminal input."
    (let ((*standard-input* (make-string-input-stream "x"))
          (calls 0))
      (let ((event
              (nshell.infrastructure.terminal:read-key-event
               :interrupt-predicate
               (lambda ()
                 (incf calls)
                 t))))
        (expect 1 :to-equal calls)
        (expect :ctrl-c :to-be
                (nshell.domain.input:key-event-type event))))))

;;; The condition above is only worth defining if something consumes it. These
;;; cover the consuming half: what the REPL's session lifecycle does with a
;;; terminal it cannot configure, in each of the two directions.

(describe "terminal-lifecycle-policy-tests"
  (it "entering-raw-mode-reports-the-failure-rather-than-swallowing-it"
    "A terminal that cannot be switched to raw mode is reported on stderr and
answered with NIL, so the caller knows not to start the line editor.

Signalling from ENABLE-RAW-MODE achieves nothing on its own: every production
caller once wrapped it in IGNORE-ERRORS, which put nshell into its line editor
believing the tty was raw while it was still canonical with ECHO on -- doubled
input and wrong cursor arithmetic, with no diagnostic anywhere."
    (let* ((nshell.infrastructure.terminal::*saved-termios* nil)
           (stderr (make-string-output-stream))
           (entered (let ((*error-output* stderr))
                      (nshell.presentation::enter-raw-mode-or-report 9999)))
           (reported (get-output-stream-string stderr)))
      (expect entered :to-be-falsy)
      (expect (search "nshell: " reported) :to-be-truthy)
      (expect (search "raw mode" reported) :to-be-truthy)))

  (it "restoring-reports-its-failure-without-aborting-the-cleanup"
    "A failed restore is reported and swallowed, so the UNWIND-PROTECT cleanup
it runs from gets to finish.

This is the one place swallowing is correct. RESTORE-TERMINAL-MODE signals, and
RUN-REPL calls it from a cleanup form followed by more work; letting the
condition through would skip that work and kill the process unhandled with the
terminal still raw -- worse than the failure being reported."
    #-(or darwin linux)
    (skip "PTY-backed terminal tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (let ((nshell.infrastructure.terminal::*saved-termios* nil)
          (stderr (make-string-output-stream))
          (cleanup-finished nil))
      (multiple-value-bind (master slave name) (nshell.infrastructure.acl:open-pty)
        (declare (ignore name))
        (nshell.infrastructure.terminal:enable-raw-mode slave)
        ;; Take the fd away underneath nshell the way a hangup does: the saved
        ;; entry still says the fd is raw, but tcsetattr can no longer succeed.
        (nshell.infrastructure.acl:pty-close master slave)
        (unwind-protect
             :repl-body
          (let ((*error-output* stderr))
            (nshell.presentation::leave-raw-mode-reporting-failures slave))
          (setf cleanup-finished t)))
      (expect cleanup-finished :to-be-truthy)
      (expect (search "nshell: " (get-output-stream-string stderr))
              :to-be-truthy)))

  (it "a-failed-install-still-runs-the-restore-path"
    "When INSTALL-INTERACTIVE-TERMINAL reports failure, RUN-REPL skips the line
editor, still restores, and exits non-zero.

Installation has to sit INSIDE the UNWIND-PROTECT for this: by the time raw mode
is attempted the process group, the signal handlers and possibly the ANSI modes
have already been changed, so an install that fails on its last step and is
never undone leaves SGR mouse reporting on in the user's next shell."
    (let ((installed nil) (restored nil) (edited nil) (code nil))
      (with-temporary-functions
          (('nshell.presentation::initialize-repl-state
            (lambda (&rest ignored)
              (declare (ignore ignored))
              nil))
           ('nshell.presentation::install-interactive-terminal
            (lambda () (setf installed t) nil))
           ('nshell.presentation::restore-interactive-terminal
            (lambda () (setf restored t)))
           ('nshell.presentation:trampoline
            (lambda (thunk) (declare (ignore thunk)) (setf edited t))))
        (with-output-to-string (*standard-output*)
          (setf code (nshell.presentation:run-repl))))
      (expect installed :to-be-truthy)
      (expect restored :to-be-truthy)
      (expect edited :to-be-falsy)
      (expect 1 :to-equal code)))

  (it "a-successful-install-runs-the-editor-and-restores-afterwards"
    "The paired case: install succeeds, the editor runs, restoration still runs
on the way out, and the session reports success."
    (let ((restored nil) (edited nil) (code nil))
      (with-temporary-functions
          (('nshell.presentation::initialize-repl-state
            (lambda (&rest ignored)
              (declare (ignore ignored))
              nil))
           ('nshell.presentation::install-interactive-terminal (lambda () t))
           ('nshell.presentation::restore-interactive-terminal
            (lambda () (setf restored t)))
           ('nshell.presentation:trampoline
            (lambda (thunk) (declare (ignore thunk)) (setf edited t))))
        (with-output-to-string (*standard-output*)
          (setf code (nshell.presentation:run-repl))))
      (expect edited :to-be-truthy)
      (expect restored :to-be-truthy)
      (expect 0 :to-equal code))))
;;; The condition above is only worth defining if something consumes it. These
;;; cover the consuming half: what the REPL's session lifecycle does with a
;;; terminal it cannot configure, in each of the two directions.

(describe "terminal-lifecycle-seam-tests"
  (it "installs-and-restores-terminal-through-boundary-calls"
    (let ((calls nil)
          (nshell.application:*shell-pgid* nil))
      (with-temporary-functions
          (('nshell.infrastructure.acl:set-process-group
            (lambda (&rest args)
              (declare (ignore args))
              (push :set-process-group calls)))
           ('nshell.infrastructure.acl:install-signal-handlers
            (lambda (&rest args)
              (declare (ignore args))
              (push :install-signal-handlers calls)
              t))
           ('nshell.infrastructure.acl:set-foreground-pgroup
            (lambda (&rest args)
              (declare (ignore args))
              (push :set-foreground-pgroup calls)))
           ('nshell.infrastructure.terminal:enable-raw-mode
            (lambda (&rest args)
              (declare (ignore args))
              (push :enable-raw-mode calls)
              t))
           ('nshell.infrastructure.terminal:restore-terminal-mode
            (lambda (&rest args)
              (declare (ignore args))
              (push :restore-terminal-mode calls)
              t))
           ('nshell.infrastructure.terminal:ansi-enable-bracketed-paste
            (lambda (&rest args)
              (declare (ignore args))
              (push :ansi-enable-bracketed-paste calls)))
           ('nshell.infrastructure.terminal:ansi-enable-sgr-mouse
            (lambda (&rest args)
              (declare (ignore args))
              (push :ansi-enable-sgr-mouse calls)))
           ('nshell.infrastructure.terminal:ansi-disable-sgr-mouse
            (lambda (&rest args)
              (declare (ignore args))
              (push :ansi-disable-sgr-mouse calls)))
           ('nshell.infrastructure.terminal:ansi-disable-bracketed-paste
            (lambda (&rest args)
              (declare (ignore args))
              (push :ansi-disable-bracketed-paste calls))))
        (expect t :to-be
                (nshell.presentation::install-interactive-terminal))
        (nshell.presentation::restore-interactive-terminal))
      (dolist (call '(:set-process-group
                      :install-signal-handlers
                      :set-foreground-pgroup
                      :enable-raw-mode
                      :restore-terminal-mode
                      :ansi-enable-bracketed-paste
                      :ansi-enable-sgr-mouse
                      :ansi-disable-sgr-mouse
                      :ansi-disable-bracketed-paste))
        (expect (member call calls) :to-be-truthy)))))

(describe "terminal-size-tests"
  (it "terminal-width-preserves-a-positive-column-count"
    (with-temporary-function
        ('nshell.infrastructure.acl:get-terminal-size (lambda ()
                                                         (values 24 120)))
      (expect 120 :to-equal (nshell.presentation::terminal-width))))

  (it "terminal-width-falls-back-for-a-non-positive-column-count"
    (with-temporary-function
        ('nshell.infrastructure.acl:get-terminal-size (lambda ()
                                                         (values 24 0)))
      (expect 80 :to-equal (nshell.presentation::terminal-width))))

  (it "terminal-width-falls-back-when-size-query-fails"
    (with-temporary-function
        ('nshell.infrastructure.acl:get-terminal-size (lambda ()
                                                         (error "no tty")))
      (expect 80 :to-equal (nshell.presentation::terminal-width))))

  (it "terminal-size-reports-rows-then-columns"
    "GET-TERMINAL-SIZE keeps nshell's (VALUES ROWS COLUMNS) contract on top of
cl-tty-kit:terminal-size, which returns (VALUES COLUMNS ROWS)."
    (with-temporary-function
        ('cl-tty-kit:terminal-size (lambda (&optional (fd 0))
                                     (declare (ignore fd))
                                     (values 120 40)))
      (multiple-value-bind (rows columns) (nshell.infrastructure.acl:get-terminal-size)
        (expect 40 :to-equal rows)
        (expect 120 :to-equal columns))))

  (it "terminal-size-signals-when-unavailable"
    "cl-tty-kit reports an unknown size as (VALUES NIL NIL); GET-TERMINAL-SIZE
turns that into a condition rather than passing NIL on, because its callers wrap
it in HANDLER-CASE to supply the 80-column fallback and would otherwise let a
NIL width reach the layout arithmetic."
    (with-temporary-function
        ('cl-tty-kit:terminal-size (lambda (&optional (fd 0))
                                     (declare (ignore fd))
                                     (values nil nil)))
      (expect (lambda () (nshell.infrastructure.acl:get-terminal-size))
              :to-throw 'nshell.infrastructure.acl:terminal-size-unavailable)))

  (it "terminal-size-is-unavailable-on-a-sizeless-pty"
    "A pty opened without a window size reports no size rather than 0x0."
    #-(or darwin linux)
    (skip "PTY-backed terminal tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (with-pty-slave (fd)
      (expect (lambda () (nshell.infrastructure.acl:get-terminal-size fd))
              :to-throw 'nshell.infrastructure.acl:terminal-size-unavailable))))
