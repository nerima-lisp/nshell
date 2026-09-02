(in-package #:nshell.domain.parsing)

(define-value-struct %command-list-components
    ((commands nil :type list)
     (separators nil :type list)
     (separator-tokens nil :type list)))

(define-value-struct %reduced-command-stream
    ((commands nil :type list)
     (separators nil :type list)
     (separator-tokens nil :type list)
     (ast nil)))

(define-value-struct %structural-diagnostics
    ((incomplete-p nil :type boolean)
     (diagnostics nil :type list)))

(define-value-struct %structural-diagnostics-accumulator
    ((incomplete-p nil :type boolean)
     (diagnostics nil :type list :copy :list))
  :constructor %make-structural-diagnostics-accumulator
  :predicate nil)

(define-value-struct %structural-diagnostics-input
    ((commands nil :type list)
     (last-separator nil)
     (last-separator-token nil)
     (input-length 0 :type integer)))
