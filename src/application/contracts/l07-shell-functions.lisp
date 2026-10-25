(in-package #:nshell.application)

(define-value-struct shell-function-binding
                     ((callable nil :type function)
                      (lambda-list nil :type list :copy :list)
                      (display-name "" :type string)
                      (source-path nil :type (or null pathname string))
                      (source-span nil :type (or null list)))
                     :keyword-constructor
                     t)

(defun make-shell-function-binding (callable lambda-list
                                             display-name
                                             source-path
                                             source-span)
  (%make-shell-function-binding :callable
                                callable
                                :lambda-list
                                lambda-list
                                :display-name
                                display-name
                                :source-path
                                source-path
                                :source-span
                                source-span))

(defstruct (shell-function-registry
            (:constructor %make-shell-function-registry
                (&key (global-table
                        (make-hash-table :test (function equal)))
                      (lookup-miss-hook nil)))
            (:copier nil))
  (global-table (make-hash-table :test (function equal)) :type hash-table)
  (lookup-miss-hook nil :type (or null function)))

(defun make-shell-function-registry (&optional
                                     (global-table
                                      (make-hash-table :test #'equal))
                                     lookup-miss-hook)
  (check-type global-table hash-table)
  (unless
      (or (eq (hash-table-test global-table) 'equal)
          (eq (hash-table-test global-table) #'equal))
    (error "Shell-function registry tables must use EQUAL."))
  (check-type lookup-miss-hook (or null function))
  (%make-shell-function-registry :global-table
                                 global-table
                                 :lookup-miss-hook
                                 lookup-miss-hook))

(define-value-struct shell-function-scope
                     ((table (make-hash-table :test #'equal) :type hash-table)
                      (parent nil :type (or null shell-function-scope)))
                     :keyword-constructor
                     t)

(defun make-shell-function-scope (&optional
                                  (table (make-hash-table :test #'equal))
                                  parent)
  (check-type table hash-table)
  (unless
      (or (eq (hash-table-test table) 'equal)
          (eq (hash-table-test table) #'equal))
    (error "Shell-function scope tables must use EQUAL."))
  (check-type parent (or null shell-function-scope))
  (%make-shell-function-scope :table table :parent parent))

(declaim (ftype (function (t) shell-function-registry)
                context-shell-function-registry)
         (ftype (function () (values (or null shell-function-scope)))
                active-shell-function-scope))
