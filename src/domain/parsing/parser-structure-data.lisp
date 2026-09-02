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

(defstruct (%structural-diagnostics-accumulator
            (:constructor %make-structural-diagnostics-accumulator
                (&key (incomplete-p nil) (diagnostics nil)))
            (:copier nil))
  (incomplete-p nil :type boolean)
  (diagnostics nil :type list))

(define-value-struct %structural-diagnostics-input
    ((commands nil :type list)
     (last-separator nil)
     (last-separator-token nil)
     (input-length 0 :type integer)))
