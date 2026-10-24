(in-package #:nshell.presentation)

(defun call-with-command-failure-restarts (thunk)
  (declare (ignore thunk))
  (error 'nshell.application:wp-interface-not-implemented
         :owner-wp "L04"
         :interface 'call-with-command-failure-restarts))
