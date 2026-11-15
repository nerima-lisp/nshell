(in-package #:nshell.domain.error-codes)

;;; A plain CONDITION superclass, not ERROR, so mixing it into a condition
;;; changes no HANDLER-CASE clause that selects on ERROR or its subtypes.
(define-condition nshell-error-code-mixin ()
  ((error-code :initarg :error-code :initform "E_INTERNAL"
               :reader condition-error-code)))

(defun find-error-code (name)
  (find name +error-codes+ :key #'error-code-name :test #'string=))
