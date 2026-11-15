(in-package #:nshell.application)

(define-condition wp-interface-not-implemented
    (error nshell.domain.error-codes:nshell-error-code-mixin)
  ((owner-wp :initarg :owner-wp :reader wp-interface-not-implemented-owner-wp)
   (interface :initarg :interface :reader wp-interface-not-implemented-interface))
  (:default-initargs :error-code "E_NOT_IMPLEMENTED")
  (:report (lambda (condition stream)
             (format stream "~A owns the unimplemented interface ~A."
                     (wp-interface-not-implemented-owner-wp condition)
                     (wp-interface-not-implemented-interface condition)))))

(defun %signal-unimplemented-wp-interface (owner-wp interface)
  (error 'wp-interface-not-implemented
         :owner-wp owner-wp
         :interface interface))
