(in-package #:nshell.application)

(define-condition command-argument-type-error (error)
  ((value :initarg :value :reader command-argument-type-error-value)
   (source-span :initarg :source-span
                :reader command-argument-type-error-source-span)))

(defun argv-scalar-string (value &key source-span)
  (declare (ignore value source-span))
  (%signal-unimplemented-wp-interface "L06" 'argv-scalar-string))
