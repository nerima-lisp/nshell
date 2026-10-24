(in-package #:nshell.application)

(define-condition byte-stream-execution-error (error)
  ((operation :initarg :operation :reader byte-stream-execution-error-operation)
   (cause :initarg :cause :reader byte-stream-execution-error-cause)))

(defvar *pipeline-stage-io* nil)

(define-value-struct pipeline-execution-result
    ((status 0 :type integer)
     (stage-statuses nil :type list :copy :list)
     (stage-signals nil :type list :copy :list))
  :keyword-constructor t)

(defun make-pipeline-execution-result (status stage-statuses stage-signals)
  (%make-pipeline-execution-result
   :status status
   :stage-statuses stage-statuses
   :stage-signals stage-signals))

(define-value-struct pipeline-stage-io
    ((descriptor-map nil :type list :copy :list)
     (transient-descriptors nil :type list :copy :list))
  :keyword-constructor t)

(defun make-pipeline-stage-io (descriptor-map transient-descriptors)
  (%make-pipeline-stage-io
   :descriptor-map descriptor-map
   :transient-descriptors transient-descriptors))

(defstruct (pipeline-execution-handle
             (:constructor %make-pipeline-execution-handle (token)))
  (token nil :read-only t))

(defun spawn-byte-stream-node-in-context
    (context evaluated-stages stage-io internal-stage-dispatcher)
  (declare (ignore context evaluated-stages stage-io internal-stage-dispatcher))
  (%signal-unimplemented-wp-interface "L05" 'spawn-byte-stream-node-in-context))

(defun wait-byte-stream-execution (handle)
  (declare (ignore handle))
  (%signal-unimplemented-wp-interface "L05" 'wait-byte-stream-execution))

(defun command-node-external-p (context command-node)
  (declare (ignore context command-node))
  (%signal-unimplemented-wp-interface "L05" 'command-node-external-p))

(defun pipeline-stage-stream (descriptor &optional (stage-io *pipeline-stage-io*))
  (declare (ignore descriptor stage-io))
  (%signal-unimplemented-wp-interface "L05" 'pipeline-stage-stream))
