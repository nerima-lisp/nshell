;;; Command-line is a vertical feature: each DDD layer lives beside the others
;;; under this feature root instead of being spread across a global layer tree.
(in-package #:cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.feature.command-line
    (:documentation
     "The command-line feature's public boundary.
The src/main.lisp composition root delegates here and retains compatibility
with nshell's existing internal entry-point functions.")
    (:use #:cl)
    (:export #:flag-argument-p
             #:usage-synopsis
             #:build-cli-app
             #:print-usage
             #:print-version)))
