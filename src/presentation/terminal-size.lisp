(in-package #:nshell.presentation)


(defconstant +default-terminal-width+ 80
  "Fallback width used when terminal dimensions are unavailable.")

(defun terminal-width ()
  "Return the current terminal width, falling back outside a tty."
  (handler-case
      (multiple-value-bind (rows columns)
          (nshell.infrastructure.acl:get-terminal-size)
        (declare (ignore rows))
        (if (plusp columns) columns +default-terminal-width+))
    (error () +default-terminal-width+)))
