(in-package #:nshell.application)

(define-condition command-macro-syntax-error (error)
  ((source-span :initarg :source-span
                :reader command-macro-syntax-error-source-span)
   (source-path :initarg :source-path
                :reader command-macro-syntax-error-source-path)
   (cause :initarg :cause :reader command-macro-syntax-error-cause)))

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

(defun classify-sexp-head (context head-source)
  (declare (ignore context head-source))
  (%signal-unimplemented-wp-interface "L02" 'classify-sexp-head))

(defun evaluate-reader-result-in-context (context reader-result)
  (declare (ignore context reader-result))
  (%signal-unimplemented-wp-interface "L02" 'evaluate-reader-result-in-context))

(defun evaluate-command-stage-in-context (context command-node)
  (declare (ignore context command-node))
  (%signal-unimplemented-wp-interface "L02" 'evaluate-command-stage-in-context))
