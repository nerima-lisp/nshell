(in-package #:nshell.presentation)

(defun apply-sexp-structural-edit (state scan-result action) (declare (ignore state scan-result action)) (error 'nshell.application:wp-interface-not-implemented :owner-wp "E04" :interface 'apply-sexp-structural-edit))

(declaim (ftype function
           apply-sexp-structural-edit
           %reduce-sexp-structural-edit))
