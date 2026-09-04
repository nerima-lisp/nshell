;;; Control-flow AST nodes.
(in-package #:nshell.domain.parsing)

(defstruct (if-node (:include ast-node)
                    (:constructor %make-if-node
                        (condition then-branch &optional else-branch span)))
  (condition nil :type (or null ast-node) :read-only t)
  (then-branch nil :type list :read-only t)
  (else-branch nil :type list :read-only t))

(define-ast-constructor make-if-node
    (condition then-branch &optional else-branch span)
    %make-if-node
    condition
    (%copy-ast-list then-branch)
    (%copy-ast-list else-branch)
    span)

(defstruct (for-node (:include ast-node)
                     (:constructor %make-for-node
                         (var-name in-values body &optional span)))
  (var-name "" :type string :read-only t)
  (in-values nil :type list :read-only t)
  (body nil :type list :read-only t))

(define-ast-constructor make-for-node
    (var-name in-values body &optional span)
    %make-for-node
    var-name
    (%copy-ast-list in-values)
    (%copy-ast-list body)
    span)

(defstruct (while-node (:include ast-node)
                       (:constructor %make-while-node (condition body &optional span)))
  (condition nil :type (or null ast-node) :read-only t)
  (body nil :type list :read-only t))

(define-ast-constructor make-while-node
    (condition body &optional span)
    %make-while-node
    condition
    (%copy-ast-list body)
    span)

(define-value-struct case-clause
    ((pattern "*" :type string)
     (body nil :type list :copy %copy-ast-list))
  :keyword-constructor t)

(defun make-case-clause (pattern body)
  (%make-case-clause
   :pattern (%ensure-ast-string pattern "CASE-CLAUSE pattern")
   :body (%copy-ast-list body)))

(defstruct (case-node (:include ast-node)
                      (:constructor %make-case-node (value clauses &optional span)))
  (value "" :type string :read-only t)
  (clauses nil :type list :read-only t))

(define-ast-constructor make-case-node
    (value clauses &optional span)
    %make-case-node
    value
    (%copy-ast-list clauses)
    span)

(defstruct (begin-end-node (:include ast-node)
                           (:constructor %make-begin-end-node (body &optional span)))
  (body nil :type list :read-only t))

(define-ast-constructor make-begin-end-node
    (body &optional span)
    %make-begin-end-node
    (%copy-ast-list body)
    span)
