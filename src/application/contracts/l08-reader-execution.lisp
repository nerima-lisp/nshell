(in-package #:nshell.application)

(define-condition command-execution-plan-error (error)
  ((source-span :initarg :source-span
                :reader command-execution-plan-error-source-span)
   (operation :initarg :operation
              :reader command-execution-plan-error-operation)
   (cause :initarg :cause :reader command-execution-plan-error-cause)))

(declaim (ftype (function (t t function) (values t integer pipeline-execution-result)) execute-reader-ast-in-context))
(defun execute-reader-ast-in-context (context ast stage-evaluator)
  (declare (ignore context ast stage-evaluator))
  (%signal-unimplemented-wp-interface "L08" 'execute-reader-ast-in-context))
