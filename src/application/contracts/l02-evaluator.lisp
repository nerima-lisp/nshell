(in-package #:nshell.application)

(define-condition command-macro-syntax-error (error)
  ((source-span :initarg :source-span
                :reader command-macro-syntax-error-source-span)
   (source-path :initarg :source-path
                :reader command-macro-syntax-error-source-path)
   (cause :initarg :cause :reader command-macro-syntax-error-cause)))
(define-condition sexp-evaluation-syntax-error (error)
  ((source-span :initarg :source-span
                :reader sexp-evaluation-syntax-error-source-span)
   (source-path :initarg :source-path
                :reader sexp-evaluation-syntax-error-source-path)
   (cause :initarg :cause :reader sexp-evaluation-syntax-error-cause)))

(define-value-struct evaluated-command-stage
    ((command-node nil)
     (dispatch-kind :external
                    :type (member :external :builtin :shell-function
                                  :source-function))
     (binding nil)
     (arguments nil :type list :copy :list)
     (redirect-target-values nil :type list :copy :list)
     (environment-assignments nil :type list :copy :list))
  :keyword-constructor t)

(defun make-evaluated-command-stage
    (command-node dispatch-kind binding arguments redirect-target-values
     &optional environment-assignments)
  (%make-evaluated-command-stage
   :command-node command-node
   :dispatch-kind dispatch-kind
   :binding binding
   :arguments arguments
   :redirect-target-values redirect-target-values
   :environment-assignments environment-assignments))
