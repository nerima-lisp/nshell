(in-package #:nshell.presentation)


(defun terminal-width ()
  "Return the current terminal width, falling back to 80 columns outside a tty."
  (handler-case
      (multiple-value-bind (rows columns)
          (nshell.infrastructure.acl:get-terminal-size)
        (declare (ignore rows))
        (if (plusp columns) columns 80))
    (error () 80)))
