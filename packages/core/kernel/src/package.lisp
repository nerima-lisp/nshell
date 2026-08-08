;;; Shared architectural primitives for nshell packages.
(in-package #:cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.architecture
    (:documentation
     "Small, dependency-free descriptors for nshell's package-by-feature layout.
The registry describes source topology; it does not load files or access the
filesystem.")
    (:use #:cl)
    (:export #:feature-descriptor
             #:feature-descriptor-p
             #:feature-descriptor-name
             #:feature-descriptor-root
             #:feature-descriptor-layers
             #:register-feature
             #:find-feature
             #:all-features
             #:feature-layer-path)))
