(in-package #:nshell.infrastructure.terminal)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

;;; ── Terminal raw mode ──────────────────────────────────────────────────────
;;;
;;; This is deliberately NOT delegated to cl-tty-kit:enable-raw-mode, unlike the
;;; ANSI vocabulary in ansi.lisp and the window-size query in the acl layer.
;;;
;;; cl-tty-kit clears a strict superset of the flags cleared here -- it is a
;;; full cfmakeraw-style mode -- and two of the extra bits are load-bearing for
;;; a shell:
;;;
;;;   ISIG   nshell leaves it SET so the kernel turns ^C/^Z into signals for
;;;          the foreground process group. Foreground commands receive cooked
;;;          settings; the editor must retain signal delivery when it resumes.
;;;   OPOST  nshell leaves it SET.  Both nshell's own output (every `~%' in the
;;;          presentation tier) and the inherited output of every child process
;;;          rely on the driver mapping LF to CR-LF; clearing it makes all
;;;          multi-line output stair-step down the screen.
;;;
;;; cl-tty-kit has no option to keep those bits, so the flag work stays here.
;;;
;;;   - the startup settings are saved per fd; RESTORE-TERMINAL-MODE retains
;;;     them across cooked-mode intervals only with PRESERVE-SNAPSHOT-P, and
;;;   - a failed tcgetattr/tcsetattr signals instead of being swallowed by
;;;     `ignore-errors', which used to leave the terminal in an unknown state
;;;     with no indication that anything had gone wrong.
;;;
;;; Callers decide how to handle TERMINAL-MODE-OPERATION-FAILED: entering raw
;;; mode reports the error and aborts the session, restoration reports and
;;; continues from UNWIND-PROTECT cleanup, and signal handlers swallow it in
;;; asynchronous context.
;;;
;;; The snapshot is presence-guarded rather than depth-counted. Foreground
;;; commands restore cooked mode, and shell-sigcont-handler can re-enable raw
;;; mode without a matching restore. A depth count would keep increasing across
;;; resumes, so ENABLE-RAW-MODE saves settings only when *SAVED-TERMIOS* has no
;;; entry for FD.

(define-condition terminal-mode-operation-failed (error)
  ((operation :initarg :operation
              :reader terminal-mode-operation-failed-operation)
   (fd :initarg :fd :reader terminal-mode-operation-failed-fd)
   (reason :initarg :reason :reader terminal-mode-operation-failed-reason))
  (:report
   (lambda (condition stream)
     (format stream "Terminal ~(~a~) failed on fd ~d: ~a"
             (terminal-mode-operation-failed-operation condition)
             (terminal-mode-operation-failed-fd condition)
             (terminal-mode-operation-failed-reason condition)))))

(defvar *saved-termios* nil
  "Alist of (FD . TERMIOS) holding settings saved before each FD's first raw-mode
enable. RESTORE-TERMINAL-MODE removes an entry unless PRESERVE-SNAPSHOT-P is true.")

(defun %saved-termios (fd)
  (cdr (assoc fd *saved-termios* :test #'eql)))

(defun %save-termios (fd termios)
  (push (cons fd termios) *saved-termios*)
  termios)

(defun %forget-termios (fd)
  (setf *saved-termios* (delete fd *saved-termios* :key #'car :test #'eql)))

;; SB-POSIX's Lisp conversion omits native fields, including Darwin's speeds.
;; Linux libc can also normalize CIBAUD during tcgetattr/tcsetattr. Use the
;; kernel's termios2 ABI there so restoring a snapshot preserves those bits.
(sb-alien:define-alien-type native-termios
  #+linux kernel-termios2
  #-linux sb-posix::alien-termios)

#+linux
(sb-alien:define-alien-routine ("ioctl" %termios-ioctl) sb-alien:int
  (fd sb-alien:int)
  (request sb-alien:unsigned-long)
  (termios sb-sys:system-area-pointer))

#-linux
(sb-alien:define-alien-routine ("tcgetattr" %tcgetattr) sb-alien:int
  (fd sb-alien:int)
  (termios sb-sys:system-area-pointer))

#-linux
(sb-alien:define-alien-routine ("tcsetattr" %tcsetattr) sb-alien:int
  (fd sb-alien:int)
  (action sb-alien:int)
  (termios sb-sys:system-area-pointer))

(defun %read-termios (fd)
  (let ((termios (make-array (sb-alien:alien-size native-termios :bytes)
                            :element-type '(unsigned-byte 8)
                            :initial-element 0)))
    (sb-sys:with-pinned-objects (termios)
      (when (minusp
             #+linux
             (%termios-ioctl fd
                             (ldb (byte (sb-alien:alien-size sb-alien:unsigned-long) 0)
                                  +kernel-tcgets2+)
                             (sb-sys:vector-sap termios))
             #-linux
             (%tcgetattr fd (sb-sys:vector-sap termios)))
        (let ((errno (sb-unix::get-errno)))
          (error "Terminal query failed on fd ~d (errno=~d)" fd errno))))
    termios))

(defun %apply-termios (fd termios)
  (sb-sys:with-pinned-objects (termios)
    (when (minusp
           #+linux
           (%termios-ioctl fd
                           (ldb (byte (sb-alien:alien-size sb-alien:unsigned-long) 0)
                                +kernel-tcsets2+)
                           (sb-sys:vector-sap termios))
           #-linux
           (%tcsetattr fd sb-posix:tcsanow (sb-sys:vector-sap termios)))
      (let ((errno (sb-unix::get-errno)))
        (error "Terminal update failed on fd ~d (errno=~d)" fd errno)))))

(defun %raw-termios (termios)
  "Clear the input and local flags nshell's line editor needs off TERMIOS.
ICANON and ECHO give the editor character-at-a-time input and full control of
what is displayed; IXON and IXOFF stop ^S/^Q from being eaten as flow control.
Everything else -- notably ISIG and OPOST -- is left as the terminal had it; see
the commentary at the top of this file. On Darwin, VDSUSP is disabled so ^Y
reaches the editor."
  (sb-sys:with-pinned-objects (termios)
    (let ((native (sb-alien:sap-alien (sb-sys:vector-sap termios)
                                    (* native-termios))))
      (setf (sb-alien:slot (sb-alien:deref native)
                          #+linux 'input-flags #-linux 'sb-posix::iflag)
            (logand (sb-alien:slot (sb-alien:deref native)
                                  #+linux 'input-flags #-linux 'sb-posix::iflag)
                    (lognot (logior sb-posix:ixon sb-posix:ixoff))))
      (setf (sb-alien:slot (sb-alien:deref native)
                          #+linux 'local-flags #-linux 'sb-posix::lflag)
            (logand (sb-alien:slot (sb-alien:deref native)
                                  #+linux 'local-flags #-linux 'sb-posix::lflag)
                    (lognot (logior sb-posix:icanon sb-posix:echo))))
      #+darwin
      ;; VDSUSP is c_cc[11] on Darwin; disable this control character alone.
      (setf (sb-alien:deref
             (sb-alien:slot (sb-alien:deref native) 'sb-posix::cc)
             11)
            sb-posix:vdisable)))
  termios)

(defun enable-raw-mode (&optional (fd 0))
  "Switch FD to nshell's raw mode for character-by-character input.
Remembers the settings FD had before its first raw-mode enable so
RESTORE-TERMINAL-MODE can put them back. Calling this again while FD is already
raw re-applies the mode without disturbing the remembered settings. Signals
TERMINAL-MODE-OPERATION-FAILED if the terminal cannot be queried or reconfigured."
  (handler-case
      (let ((raw (%raw-termios (%read-termios fd))))
        ;; The drain is deliberately OUTSIDE the guard below, and has to stay
        ;; there. It waits for the terminal's output queue to empty, which is
        ;; not a bounded wait: a terminal stopped by ^S (IXON is still set at
        ;; this point -- nshell only clears it in the settings it is about to
        ;; install) does not drain until ^Q. SBCL installs its handlers with
        ;; SA_RESTART, so no EINTR surfaces to end the wait, and with interrupts
        ;; deferred there is no Lisp-level way out either, so ^C could not
        ;; unwind it. Measured on Darwin, a guarded drain is worse than merely
        ;; uninterruptible: an interrupt arriving during it leaves the restarted
        ;; TIOCDRAIN never completing, even once the queue empties.
        ;;
        ;; Ordering is unchanged by moving it out. TCSADRAIN means "drain, then
        ;; apply"; an explicit TCDRAIN followed by TCSANOW is those same two
        ;; steps in that same order, and nothing in between queues output. A
        ;; failed TCDRAIN is left to propagate rather than being swallowed,
        ;; because that is also what TCSADRAIN did: the drain was part of the
        ;; TCSETATTR, so failing it failed the whole call and left the settings
        ;; untouched.
        (sb-posix:tcdrain fd)
        ;; *SAVED-TERMIOS* and the terminal it describes are one piece of state:
        ;; the entry means "fd is raw and here is what it was". Both of nshell's
        ;; asynchronous handlers reach in here -- shell-sigcont-handler calls
        ;; ENABLE-RAW-MODE, shell-sigtstp-handler calls RESTORE-TERMINAL-MODE --
        ;; so a handler landing between the snapshot and the tcsetattr would see
        ;; the pairing half-applied, and the PUSH in %SAVE-TERMIOS is itself a
        ;; read-modify-write that a handler's own push can be lost across.
        ;;
        ;; Guarded, therefore: the presence check, the snapshot's TCGETATTR and
        ;; PUSH, and the TCSETATTR that makes the entry true. Nothing else, and
        ;; nothing that blocks. Reading the settings to derive RAW is hoisted
        ;; above because it only reads and conses; a handler switching the mode
        ;; underneath it is harmless, since %RAW-TERMIOS only clears bits and so
        ;; derives the same settings from an already-raw terminal as from a
        ;; cooked one. The snapshot's own TCGETATTR is not hoisted: it has to
        ;; read the terminal on the near side of the presence check it is paired
        ;; with, or a handler restoring cooked mode in between would leave us
        ;; saving raw settings as the way back.
        (sb-sys:without-interrupts
          (unless (%saved-termios fd)
            (%save-termios fd (%read-termios fd)))
          (%apply-termios fd raw)
          t))
    (error (condition)
      (error 'terminal-mode-operation-failed
             :operation :enable :fd fd :reason condition))))

(defun restore-terminal-mode (&optional (fd 0) &key preserve-snapshot-p)
  "Restore the settings ENABLE-RAW-MODE saved for FD.
When PRESERVE-SNAPSHOT-P is true, keep that snapshot across a cooked interval so
later raw-mode enables cannot replace it with settings left by a child. Without
it, remove the snapshot after restoring. Returns NIL when FD has no snapshot.
Signals TERMINAL-MODE-OPERATION-FAILED if restore fails."
  (let ((saved (%saved-termios fd)))
    (when saved
      (handler-case
          (progn
            ;; Outside the guard, then TCSANOW inside it, for the reason spelled
            ;; out in ENABLE-RAW-MODE: this path runs from shell-sigtstp-handler,
            ;; and a ^S-stopped terminal would otherwise block here with no way
            ;; out. Same drain-then-apply order as the TCSADRAIN it replaces.
            (sb-posix:tcdrain fd)
            ;; Atomic for the reason given in ENABLE-RAW-MODE, and here the
            ;; unguarded version is not merely untidy: a SIGCONT arriving after
            ;; the tcsetattr but before %FORGET-TERMIOS runs
            ;; shell-sigcont-handler, which sees the entry still present, skips
            ;; the snapshot and puts the terminal back into raw mode -- and then
            ;; this %FORGET-TERMIOS discards the cooked settings that were the
            ;; only way back. The terminal is stranded raw for good.
            (sb-sys:without-interrupts
              (%apply-termios fd saved)
              (unless preserve-snapshot-p
                (%forget-termios fd))
              t))
        (error (condition)
          (error 'terminal-mode-operation-failed
                 :operation :restore :fd fd :reason condition))))))
