(in-package #:nshell.infrastructure.acl)

(defconstant +default-external-command-timeout+ 3600
  "Maximum seconds for a non-interactive external command.")

(defconstant +default-command-substitution-timeout+ 300
  "Maximum seconds for command substitution.")

(defun timeout-seconds-p (value)
  "Return true when VALUE is a finite, non-negative timeout in seconds."
  (and (realp value)
       (not (minusp value))))
