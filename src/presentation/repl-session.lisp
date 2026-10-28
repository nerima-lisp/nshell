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
  (setf *interactive-terminal-restore-pgid*
        (ignore-errors
          (nshell.infrastructure.acl:get-foreground-pgroup)))
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
  ;; The ANSI modes are for the line editor, so enable them only after raw mode.
  (let ((installed-p (enter-raw-mode-or-report)))
    (when installed-p
      (when (nshell.infrastructure.terminal:terminal-control-sequences-supported-p)
        (ignore-errors
          (progn
            (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
            (nshell.infrastructure.terminal:ansi-enable-bracketed-paste)
            (when *mouse-reporting-enabled-p*
              (nshell.infrastructure.terminal:ansi-enable-sgr-mouse))
            (finish-output))))
    installed-p)))

(defun restore-interactive-terminal ()
  "Undo INSTALL-INTERACTIVE-TERMINAL as far as it got. Never signals."
  (ignore-errors
      (progn
        (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
        (nshell.infrastructure.terminal:ansi-disable-bracketed-paste)
        (finish-output)))
  (leave-raw-mode-reporting-failures)
  (let ((pgid *interactive-terminal-restore-pgid*))
    (setf *interactive-terminal-restore-pgid* nil)
    (when (and (integerp pgid) (plusp pgid))
      (handler-case
          (nshell.infrastructure.acl:set-foreground-pgroup pgid)
        (error (condition)
          (report-terminal-failure "cannot restore the foreground process group"
                                   condition))))))
