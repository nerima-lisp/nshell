;;; Foundational, dependency-free string helpers shared across every layer.
(in-package #:nshell.util)

(defun string-prefix-p (prefix string)
  "True when STRING begins with PREFIX, compared case-sensitively."
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))
