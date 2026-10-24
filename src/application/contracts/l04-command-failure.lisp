(in-package #:nshell.application)

(define-condition command-failed (error)
  ((command :initarg :command :reader command-failed-command)
   (status :initarg :status :reader command-failed-status)
   (stage-statuses :initarg :stage-statuses :reader command-failed-stage-statuses)
   (signal :initarg :signal :reader command-failed-signal)))

(defvar *interactive-top-level-p* nil)

(defvar *command-test-position-p* nil)

(defvar *errexit-p* nil)
