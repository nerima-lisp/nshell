(in-package #:nshell.feature.command-line)

(defun flag-argument-p (argument)
  "Return T when ARGUMENT looks like an option flag."
  (and (stringp argument)
       (plusp (length argument))
       (char= (char argument 0) #\-)))
