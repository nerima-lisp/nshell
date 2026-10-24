(in-package #:nshell.application)

(define-condition command-failed (error)
  ((command :initarg :command :reader command-failed-command)
   (status :initarg :status :reader command-failed-status)
   (stage-statuses :initarg :stage-statuses :reader command-failed-stage-statuses)
   (signal :initarg :signal :reader command-failed-signal)))

(defvar *interactive-top-level-p* nil)

(defvar *command-test-position-p* nil)

(defvar *errexit-p* nil)
(declaim (ftype (function (t function) (values t integer)) call-with-command-failure-policy))
(defun call-with-command-failure-policy (command-ast thunk)
  (declare (ignore command-ast thunk))
  (%signal-unimplemented-wp-interface "L04" 'call-with-command-failure-policy))
