;;; nshell package definitions
;;; DDD architecture: domain/ must not import from application/, infrastructure/, or presentation/
;;;
;;; Split by layer across package.lisp (this file: the entry point plus the
;;; layer-free utility package), package-domain.lisp, package-application.lisp,
;;; package-infrastructure.lisp, and package-presentation.lisp, loaded in that
;;; order (nshell.asd's :serial t component list). Each file wraps its own
;;; DEFPACKAGE forms in EVAL-WHEN, exactly as this file did before the split;
;;; the load order matches every cross-package :IMPORT-FROM in the tree, all of
;;; which point earlier in this list, never later.

(eval-when (:compile-toplevel :load-toplevel :execute)
;; -- Main package ------------------------------------------
(defpackage #:nshell
  (:documentation
   "Entry point: parses argv and hands control to the presentation layer's REPL.
Holds no shell logic of its own; it only chooses between interactive, -c, and
script startup.")
  (:use #:cl)
  (:export #:main))

;; -- Foundational, dependency-free utility package -----------
;; No layer restrictions apply: every layer may use this package's macros.
(defpackage #:nshell.util
  (:documentation
   "Layer-free primitives shared by every layer: the DEFINE-VALUE-STRUCT macro
that gives the domain its immutable value types, plus small string predicates.
Depends on nothing but CL, which is why no layer rule applies to it.")
  (:use #:cl)
  (:export #:define-value-struct #:string-prefix-p))
)
