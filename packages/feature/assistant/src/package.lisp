;;; Assistant is a vertical feature: each DDD layer lives beside the others
;;; under this feature root instead of being spread across a global layer tree.
(in-package #:cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.feature.assistant
    (:documentation
     "The assistant feature's public boundary.
The initial vertical slice provides only layer markers; later components extend
this package with assistant use cases and boundaries.")
    (:use #:cl)))
