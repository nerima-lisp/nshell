;;; REPL terminal lifecycle
(in-package #:nshell.presentation)

(defun install-interactive-terminal ()
  (ignore-errors
      (progn
        (setf nshell.application:*shell-pgid* (sb-posix:getpid))
        (nshell.infrastructure.acl:set-process-group 0 0)))
  (handler-case
      (nshell.infrastructure.acl:install-signal-handlers)
    (error (condition)
      (format t "Warning: signal handlers: ~a~%" condition)))
  (ignore-errors
      (nshell.infrastructure.acl:set-foreground-pgroup
       nshell.application:*shell-pgid*))
  (ignore-errors
      (nshell.infrastructure.terminal:enable-raw-mode))
  (ignore-errors
      (progn
        (nshell.infrastructure.terminal:ansi-enable-bracketed-paste)
        (nshell.infrastructure.terminal:ansi-enable-sgr-mouse)
        (finish-output)))
  (setf *interactive-terminal-installed-p* t))

(defun restore-interactive-terminal ()
  (ignore-errors
      (progn
        (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
        (nshell.infrastructure.terminal:ansi-disable-bracketed-paste)
        (finish-output)))
  (nshell.infrastructure.terminal:restore-terminal-mode)
  (setf *interactive-terminal-installed-p* nil))
