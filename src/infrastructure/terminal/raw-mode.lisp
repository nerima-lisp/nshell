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
;;;   ISIG   nshell leaves it SET.  enable-raw-mode is called once per session
;;;          (repl-session.lisp) and stays in effect while a foreground child
;;;          runs; manage-job.lisp hands the terminal to the child's process
;;;          group but never returns the tty to cooked mode.  ISIG is what makes
;;;          the kernel turn ^C/^Z into SIGINT/SIGTSTP for that foreground
;;;          group, which is how `sleep 100` gets interrupted and how the
;;;          shell-sigtstp-handler / fg / bg job-control path is driven at all.
;;;          Clearing it would deliver a bare #\Etx byte to the reader instead
;;;          and leave foreground jobs uninterruptible.
;;;   OPOST  nshell leaves it SET.  Both nshell's own output (every `~%' in the
;;;          presentation tier) and the inherited output of every child process
;;;          rely on the driver mapping LF to CR-LF; clearing it makes all
;;;          multi-line output stair-step down the screen.
;;;
;;; cl-tty-kit has no option to keep those bits, so the flag work stays here.
;;; See the report accompanying this change for the requested kit API.
;;;
;;; What DID move here from the previous implementation is the part cl-tty-kit
;;; gets right and this file got wrong:
;;;
;;;   - the saved settings are keyed by fd rather than held in one global, and
;;;   - a failed tcgetattr/tcsetattr signals instead of being swallowed by
;;;     `ignore-errors', which used to leave the terminal in an unknown state
;;;     with no indication that anything had gone wrong.
;;;
;;; Signalling is only half of that second point.  It buys nothing if the
;;; callers put the `ignore-errors' back one layer up -- which is exactly where
;;; it ended up for a while.  What to DO with TERMINAL-MODE-OPERATION-FAILED is
;;; policy, and policy lives with the caller; the note at the top of
;;; presentation/repl-session.lisp states it.  In short: a failed enter is
;;; reported on stderr and aborts the interactive session, a failed restore is
;;; reported and swallowed because it runs from an UNWIND-PROTECT cleanup, and
;;; the two handlers in acl/signal-acl.lisp swallow silently because they run in
;;; asynchronous context.
;;;
;;; Note the saved state is guarded rather than depth-counted.  cl-tty-kit
;;; counts nesting depth because its callers pair enable/disable.  nshell's do
;;; not: shell-sigcont-handler re-enables raw mode with no matching disable, so
;;; a depth counter would only ever climb and the terminal would never be
;;; restored.  Making ENABLE-RAW-MODE idempotent -- snapshot only when no
;;; snapshot is held -- is the behaviour this caller actually needs, and it
;;; fixes the bug where a second enable overwrote the saved cooked settings
;;; with the raw ones and made restoration impossible.

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
  "Alist of (FD . TERMIOS) holding the settings in effect before ENABLE-RAW-MODE
first switched FD to raw mode. An fd is present exactly while nshell believes it
has put that fd into raw mode.")

(defun %saved-termios (fd)
  (cdr (assoc fd *saved-termios* :test #'eql)))

(defun %save-termios (fd termios)
  (push (cons fd termios) *saved-termios*)
  termios)

(defun %forget-termios (fd)
  (setf *saved-termios* (delete fd *saved-termios* :key #'car :test #'eql)))

(defun %raw-termios (termios)
  "Clear the input and local flags nshell's line editor needs off TERMIOS.
ICANON and ECHO give the editor character-at-a-time input and full control of
what is displayed; IXON and IXOFF stop ^S/^Q from being eaten as flow control.
Everything else -- notably ISIG and OPOST -- is left as the terminal had it; see
the commentary at the top of this file."
  (setf (sb-posix:termios-iflag termios)
        (logand (sb-posix:termios-iflag termios)
                (lognot (logior sb-posix:ixon sb-posix:ixoff))))
  (setf (sb-posix:termios-lflag termios)
        (logand (sb-posix:termios-lflag termios)
                (lognot (logior sb-posix:icanon sb-posix:echo))))
  termios)

(defun enable-raw-mode (&optional (fd 0))
  "Switch FD to nshell's raw mode for character-by-character input.
Remembers the settings FD had beforehand so RESTORE-TERMINAL-MODE can put them
back. Calling this again while FD is already raw re-applies the mode without
disturbing the remembered settings. Signals TERMINAL-MODE-OPERATION-FAILED if
the terminal cannot be queried or reconfigured."
  (handler-case
      (let ((raw (%raw-termios (sb-posix:tcgetattr fd))))
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
            (%save-termios fd (sb-posix:tcgetattr fd)))
          (sb-posix:tcsetattr fd sb-posix:tcsanow raw)
          t))
    (error (condition)
      (error 'terminal-mode-operation-failed
             :operation :enable :fd fd :reason condition))))

(defun restore-terminal-mode (&optional (fd 0))
  "Restore the settings ENABLE-RAW-MODE saved for FD.
Returns NIL when FD was never put into raw mode. Signals
TERMINAL-MODE-OPERATION-FAILED if the restore itself fails, rather than leaving
the terminal in an unknown state silently."
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
              (sb-posix:tcsetattr fd sb-posix:tcsanow saved)
              (%forget-termios fd)
              t))
        (error (condition)
          (error 'terminal-mode-operation-failed
                 :operation :restore :fd fd :reason condition))))))
