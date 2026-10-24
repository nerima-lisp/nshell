;;; The evaluation package must exist before the production reader loads.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.user
    (:documentation
     "Persistent user evaluation package. Common Lisp names are available, and
user modules are loaded by the application layer.")
    (:use #:cl)))
