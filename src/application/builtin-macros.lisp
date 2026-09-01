(in-package #:nshell.application)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro define-builtin (name lambda-list ignore-variables &body body)
    `(defun ,name ,lambda-list
       ,@(when ignore-variables
           `((declare (ignore ,@ignore-variables))))
       ,@body))

  (defmacro define-status-builtin (name status)
    `(define-builtin ,name (context args) (context args)
       (values nil ,status))))
