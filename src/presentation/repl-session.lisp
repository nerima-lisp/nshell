;;; REPL terminal lifecycle
(in-package #:nshell.presentation)

;;; Entering raw mode is a precondition for editing; restoration is cleanup.
;;; The former reports failure to its caller, while the latter reports and
;;; continues so one failed cleanup cannot strand the terminal in raw mode.

(defun report-terminal-failure (what condition)
  "Report a terminal-lifecycle failure on stderr and return NIL."
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
  "Restore raw-mode settings on FD, reporting failures without signaling."
  (handler-case
      (nshell.infrastructure.terminal:restore-terminal-mode fd)
    (error (condition)
      (report-terminal-failure "cannot restore the terminal mode" condition))))

(defun install-interactive-terminal ()
  "Prepare terminal and job control for an interactive session."
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
  "Undo INSTALL-INTERACTIVE-TERMINAL as far as it got. Never signals."
  (ignore-errors
      (progn
        (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
        (nshell.infrastructure.terminal:ansi-disable-bracketed-paste)
        (finish-output)))
  (leave-raw-mode-reporting-failures))
