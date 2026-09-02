;;; Data definitions for pure REPL input dispatch.

(in-package #:nshell.presentation)

(define-value-struct %input-dispatch-action
    ((kind :none :type symbol)
     (value nil :optional t)))

(define-value-struct %input-dispatch-transition
    ((state nil)
     (output :none :type symbol)))
