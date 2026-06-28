;;; REPL terminal lifecycle
(in-package #:nshell.presentation)

(defun install-interactive-terminal ()
  (handler-case
      (progn
        (setf nshell.application:*shell-pgid* (sb-posix:getpid))
        (nshell.infrastructure.acl:set-process-group 0 0))
    (error ()))
  (handler-case
      (nshell.infrastructure.acl:install-signal-handlers)
    (error (condition)
      (format t "Warning: signal handlers: ~a~%" condition)))
  (handler-case
      (nshell.infrastructure.acl:set-foreground-pgroup
       nshell.application:*shell-pgid*)
    (error ()))
  (handler-case
      (nshell.infrastructure.terminal:enable-raw-mode)
    (error ()))
  (handler-case
      (progn
        (nshell.infrastructure.terminal:ansi-enable-bracketed-paste)
        (nshell.infrastructure.terminal:ansi-enable-sgr-mouse)
        (finish-output))
    (error ())))

(defun restore-interactive-terminal ()
  (handler-case
      (progn
        (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
        (nshell.infrastructure.terminal:ansi-disable-bracketed-paste)
        (finish-output))
    (error ()))
  (nshell.infrastructure.terminal:restore-terminal-mode))
