(in-package #:nshell.application)

(defun %format-function-definition (name body-lines)
  (with-output-to-string (out)
    (format out "function ~a~%" name)
    (dolist (line body-lines)
      (format out "  ~a~%" line))
    (format out "end~%")))
