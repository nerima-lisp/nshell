;;; REPL terminal lifecycle
(in-package #:nshell.presentation)

;;; ── Terminal failure policy ────────────────────────────────────────────────
;;;
;;; The two directions are deliberately asymmetric, so neither `ignore-errors'
;;; below is a copy of the other.
;;;
;;; ENTERING raw mode is a precondition, not a nicety. The line editor reads one
;;; character at a time, echoes what it decides to echo, and does its own cursor
;;; arithmetic. Against a canonical terminal with ECHO still on, every one of
;;; those is wrong -- input comes back doubled and the cursor lands in the wrong
;;; column -- and nothing inside the editor can tell. So a failed enter is
;;; reported on stderr and ends the interactive session. Wrapping it in
;;; `ignore-errors', as this file used to, hides the failure from the only code
;;; that could have acted on it; the condition that infrastructure/terminal/
;;; raw-mode.lisp went to the trouble of defining then has no consumer at all.
;;;
;;; LEAVING raw mode is the opposite. It runs as RUN-REPL's UNWIND-PROTECT
;;; cleanup, where a condition escaping abandons the rest of the cleanup and
;;; takes the process down with the terminal still raw -- strictly worse than
;;; the failure being reported. So restoration reports and continues.
;;;
;;; The handlers in infrastructure/acl/signal-acl.lisp are a third case again:
;;; they run asynchronously, cannot report safely, and swallow. Their reasoning
;;; is written out at each call site there.

(defun report-terminal-failure (what condition)
  "Report a terminal-lifecycle failure on stderr and return NIL.
Uses nshell's `nshell: WHAT: WHY' stderr form -- the same one the external
command paths in infrastructure/acl use -- rather than a log call: this is the
shell's diagnostic output, which a caller may redirect and read. Returns NIL so
callers can use the call itself as their failure value."
  (format *error-output* "nshell: ~a: ~a~%" what condition)
  (ignore-errors (finish-output *error-output*))
  nil)

(defun enter-raw-mode-or-report (&optional (fd 0))
  "Put FD into raw mode and return T, or report the failure and return NIL.
A NIL return means the caller must NOT run the line editor; see the policy note
above."
  (handler-case
      (progn
        (nshell.infrastructure.terminal:enable-raw-mode fd)
        t)
    (nshell.infrastructure.terminal:terminal-mode-operation-failed (condition)
      (report-terminal-failure "cannot switch the terminal to raw mode"
                               condition))))

(defun leave-raw-mode-reporting-failures (&optional (fd 0))
  "Restore the settings raw mode replaced on FD. Reports failures, never signals.
Swallowing is correct HERE, and only here: this is reached from an
UNWIND-PROTECT cleanup, so letting the condition through would skip the rest of
the cleanup and kill the process with the terminal still in raw mode -- the very
state the call exists to undo. Reporting keeps the failure visible without
paying that price. Do not `simplify' this back into a bare call that signals."
  (handler-case
      (nshell.infrastructure.terminal:restore-terminal-mode fd)
    (error (condition)
      (report-terminal-failure "cannot restore the terminal mode" condition))))

(defun install-interactive-terminal ()
  "Prepare terminal and job control for an interactive session.
Returns T when raw mode is in effect, NIL when it is not; NIL means the caller
must not enter the line editor. A NIL return still leaves work undone -- the
process group and the signal handlers have already been changed by then -- so
RESTORE-INTERACTIVE-TERMINAL has to run either way, which is why RUN-REPL calls
this from inside its UNWIND-PROTECT rather than before it."
  (ignore-errors
      (progn
        (setf nshell.application:*shell-pgid*
              (nshell.infrastructure.acl:current-process-id))
        (nshell.infrastructure.acl:set-process-group 0 0)))
  (handler-case
      (nshell.infrastructure.acl:install-signal-handlers)
    (error (condition)
      (report-terminal-failure "signal handlers" condition)))
  (ignore-errors
      (nshell.infrastructure.acl:set-foreground-pgroup
       nshell.application:*shell-pgid*))
  ;; The ANSI modes are for the line editor, so they are only worth turning on
  ;; once raw mode is actually in effect.
  (when (enter-raw-mode-or-report)
    (ignore-errors
        (progn
          (nshell.infrastructure.terminal:ansi-enable-bracketed-paste)
          (nshell.infrastructure.terminal:ansi-enable-sgr-mouse)
          (finish-output)))
    t))

(defun restore-interactive-terminal ()
  "Undo INSTALL-INTERACTIVE-TERMINAL as far as it got. Never signals.
The ANSI disables run unconditionally: they cost nothing when the modes were
never enabled, and leaving SGR mouse reporting on would follow the user into
whatever shell comes next."
  (ignore-errors
      (progn
        (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
        (nshell.infrastructure.terminal:ansi-disable-bracketed-paste)
        (finish-output)))
  (leave-raw-mode-reporting-failures))
