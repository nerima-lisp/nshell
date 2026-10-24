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

(define-value-struct shell-function-registry
                     ((global-table (make-hash-table :test #'equal)
                                    :type
                                    hash-table)
                      (lookup-miss-hook nil :type (or null function)))
                     :keyword-constructor
                     t)

(defun make-shell-function-registry (&optional
                                     (global-table
                                      (make-hash-table :test #'equal))
                                     lookup-miss-hook)
  (%make-shell-function-registry :global-table
                                 global-table
                                 :lookup-miss-hook
                                 lookup-miss-hook))

(define-value-struct shell-function-scope
                     ((table (make-hash-table :test #'equal) :type hash-table)
                      (parent nil))
                     :keyword-constructor
                     t)

(defun make-shell-function-scope (&optional
                                  (table (make-hash-table :test #'equal))
                                  parent)
  (%make-shell-function-scope :table table :parent parent))

(defun register-shell-function (registry name binding &key escaped-p)
  (declare (ignore registry name binding escaped-p))
  (%signal-unimplemented-wp-interface "L07" 'register-shell-function))

(defun peek-shell-function (registry name &key scope escaped-p)
  (declare (ignore registry name scope escaped-p))
  (%signal-unimplemented-wp-interface "L07" 'peek-shell-function))

(defun lookup-shell-function (registry name &key scope escaped-p)
  (declare (ignore registry name scope escaped-p))
  (%signal-unimplemented-wp-interface "L07" 'lookup-shell-function))

(defmacro define-shell-function (name lambda-list &body body)
  (declare (ignore name lambda-list body))
  (%signal-unimplemented-wp-interface "L07" (quote define-shell-function)))

(defmacro with-shell-functions (bindings &body body)
  (declare (ignore bindings body))
  (%signal-unimplemented-wp-interface "L07" (quote with-shell-functions)))
(declaim
 (ftype (function (t) shell-function-registry)
        context-shell-function-registry)
 (ftype (function () (values (or null shell-function-scope)))
        active-shell-function-scope))
(defun context-shell-function-registry (context)
  (declare (ignore context))
  (%signal-unimplemented-wp-interface "L07" 'context-shell-function-registry))
(defun active-shell-function-scope ()
  (%signal-unimplemented-wp-interface "L07" 'active-shell-function-scope))
