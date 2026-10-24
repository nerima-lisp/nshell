(in-package #:nshell.application)

(define-condition wp-interface-not-implemented (error)
  ((owner-wp :initarg :owner-wp :reader wp-interface-not-implemented-owner-wp)
   (interface :initarg :interface :reader wp-interface-not-implemented-interface))
  (:report (lambda (condition stream)
             (format stream "~A owns the unimplemented interface ~A."
                     (wp-interface-not-implemented-owner-wp condition)
                     (wp-interface-not-implemented-interface condition)))))

(defun %signal-unimplemented-wp-interface (owner-wp interface)
  (error 'wp-interface-not-implemented
         :owner-wp owner-wp
         :interface interface))

(define-condition command-failed (error)
  ((command :initarg :command :reader command-failed-command)
   (status :initarg :status :reader command-failed-status)
   (stage-statuses :initarg :stage-statuses :reader command-failed-stage-statuses)
   (signal :initarg :signal :reader command-failed-signal)))

(define-condition command-execution-plan-error (error)
  ((source-span :initarg :source-span
                :reader command-execution-plan-error-source-span)
   (operation :initarg :operation
              :reader command-execution-plan-error-operation)
   (cause :initarg :cause :reader command-execution-plan-error-cause)))

(define-condition byte-stream-execution-error (error)
  ((operation :initarg :operation :reader byte-stream-execution-error-operation)
   (cause :initarg :cause :reader byte-stream-execution-error-cause)))

(define-condition command-argument-type-error (error)
  ((value :initarg :value :reader command-argument-type-error-value)
   (source-span :initarg :source-span
                :reader command-argument-type-error-source-span)))

(define-condition command-macro-syntax-error (error)
  ((source-span :initarg :source-span
                :reader command-macro-syntax-error-source-span)
   (source-path :initarg :source-path
                :reader command-macro-syntax-error-source-path)
   (cause :initarg :cause :reader command-macro-syntax-error-cause)))

(defvar *interactive-top-level-p* nil)
(defvar *command-test-position-p* nil)
(defvar *errexit-p* nil)
(defvar *pipeline-stage-io* nil)
(defvar *builtin-binding-registry* (make-hash-table :test #'equal))

(define-value-struct builtin-binding
    ((handler nil :type function)
     (argument-mode :argv :type (member :argv :value)))
  :keyword-constructor t)

(defun make-builtin-binding (handler argument-mode)
  (%make-builtin-binding :handler handler :argument-mode argument-mode))

(define-value-struct evaluated-command-stage
    ((command-node nil)
     (dispatch-kind :external :type (member :external :builtin :shell-function))
     (binding nil)
     (arguments nil :type list :copy :list)
     (redirect-target-values nil :type list :copy :list))
  :keyword-constructor t)

(defun make-evaluated-command-stage
    (command-node dispatch-kind binding arguments redirect-target-values)
  (%make-evaluated-command-stage
   :command-node command-node
   :dispatch-kind dispatch-kind
   :binding binding
   :arguments arguments
   :redirect-target-values redirect-target-values))

(define-value-struct shell-function-binding
    ((callable nil :type function)
     (lambda-list nil :type list :copy :list)
     (display-name "" :type string)
     (source-path nil :type (or null pathname string))
     (source-span nil :type (or null list)))
  :keyword-constructor t)

(defun make-shell-function-binding
    (callable lambda-list display-name source-path source-span)
  (%make-shell-function-binding
   :callable callable
   :lambda-list lambda-list
   :display-name display-name
   :source-path source-path
   :source-span source-span))

(define-value-struct shell-function-registry
    ((global-table (make-hash-table :test #'equal) :type hash-table)
     (lookup-miss-hook nil :type (or null function)))
  :keyword-constructor t)

(defun make-shell-function-registry
    (&optional (global-table (make-hash-table :test #'equal)) lookup-miss-hook)
  (%make-shell-function-registry
   :global-table global-table
   :lookup-miss-hook lookup-miss-hook))

(define-value-struct shell-function-scope
    ((table (make-hash-table :test #'equal) :type hash-table)
     (parent nil))
  :keyword-constructor t)

(defun make-shell-function-scope
    (&optional (table (make-hash-table :test #'equal)) parent)
  (%make-shell-function-scope :table table :parent parent))

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

(defun register-builtin (name binding)
  (declare (ignore name binding))
  (%signal-unimplemented-wp-interface "L03" 'register-builtin))

(defun lookup-builtin-binding (name)
  (declare (ignore name))
  (%signal-unimplemented-wp-interface "L03" 'lookup-builtin-binding))

(defun dispatch-builtin (context binding evaluated-command-args &key argv-strings)
  (declare (ignore context binding evaluated-command-args argv-strings))
  (%signal-unimplemented-wp-interface "L03" 'dispatch-builtin))

(defun command-argv-strings (context evaluated-command-args)
  (declare (ignore context evaluated-command-args))
  (%signal-unimplemented-wp-interface "L03" 'command-argv-strings))

(defun classify-sexp-head (context head-source)
  (declare (ignore context head-source))
  (%signal-unimplemented-wp-interface "L02" 'classify-sexp-head))

(defun evaluate-reader-result-in-context (context reader-result)
  (declare (ignore context reader-result))
  (%signal-unimplemented-wp-interface "L02" 'evaluate-reader-result-in-context))

(defun evaluate-command-stage-in-context (context command-node)
  (declare (ignore context command-node))
  (%signal-unimplemented-wp-interface "L02" 'evaluate-command-stage-in-context))

(defun register-shell-function (registry name binding &key escaped-p)
  (declare (ignore registry name binding escaped-p))
  (%signal-unimplemented-wp-interface "L07" 'register-shell-function))

(defun peek-shell-function (registry name &key scope escaped-p)
  (declare (ignore registry name scope escaped-p))
  (%signal-unimplemented-wp-interface "L07" 'peek-shell-function))

(defun lookup-shell-function (registry name &key scope escaped-p)
  (declare (ignore registry name scope escaped-p))
  (%signal-unimplemented-wp-interface "L07" 'lookup-shell-function))

(defun execute-reader-ast-in-context (context ast stage-evaluator)
  (declare (ignore context ast stage-evaluator))
  (%signal-unimplemented-wp-interface "L08" 'execute-reader-ast-in-context))

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

(defun argv-scalar-string (value &key source-span)
  (declare (ignore value source-span))
  (%signal-unimplemented-wp-interface "L06" 'argv-scalar-string))
