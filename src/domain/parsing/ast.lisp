;;; AST Node Types
(in-package #:nshell.domain.parsing)

(defun %ensure-ast-string (value field-name)
  (unless (stringp value)
    (error "~A must be a string: ~S" field-name value))
  value)

(defun %copy-ast-list (items)
  (let ((items (or items '())))
    (unless (listp items)
      (error "AST list slot must be a list: ~S" items))
    (copy-list items)))

(defun %copy-command-args (args)
  (mapcar #'%command-arg (%copy-ast-list args)))

(defstruct (ast-node (:constructor %make-ast-node (type &optional span)))
  (type :unknown :type keyword :read-only t)
  (span nil :type list :read-only t))

(defstruct (command-node (:include ast-node)
                         (:constructor %make-command-node
                             (command args &optional span command-quote-style)))
  (command "" :type string :read-only t)
  (command-quote-style nil :type (member nil :single :double) :read-only t)
  (args nil :type list :read-only t))

(defun make-command-node (command args &optional span command-quote-style)
  (%make-command-node command
                      (%copy-command-args args)
                      span
                      command-quote-style))

(defstruct (pipeline-node (:include ast-node)
                          (:constructor %make-pipeline-node (commands &optional span)))
  (commands nil :type list :read-only t))

(defun make-pipeline-node (commands &optional span)
  (%make-pipeline-node (%copy-ast-list commands) span))

(defstruct (sequence-node (:include ast-node)
                           (:constructor %make-sequence-node (commands &optional separators span)))
  "Represents shell command sequences separated by ;, &, &&, or ||.
   SEPARATORS is a list of :semi, :amp, :and, or :or keywords, one per command except the last."
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t))

(defun make-sequence-node (commands &optional separators span)
  (%make-sequence-node (%copy-ast-list commands)
                       (%copy-ast-list separators)
                       span))

(defstruct (sequence-node-command-separator
            (:constructor %make-sequence-node-command-separator (command separator)))
  (command nil :read-only t)
  (separator nil :read-only t))

(defun sequence-node-command-separators (node)
  "Return SEQUENCE-NODE-COMMAND-SEPARATOR values for NODE in command order."
  (let ((separators (copy-list (sequence-node-separators node))))
    (loop for command in (sequence-node-commands node)
          collect (%make-sequence-node-command-separator command (pop separators)))))

(defstruct (if-node (:include ast-node)
                    (:constructor %make-if-node
                        (condition then-branch &optional else-branch span)))
  (condition nil :type (or null ast-node) :read-only t)
  (then-branch nil :type list :read-only t)
  (else-branch nil :type list :read-only t))

(defun make-if-node (condition then-branch &optional else-branch span)
  (%make-if-node condition
                 (%copy-ast-list then-branch)
                 (%copy-ast-list else-branch)
                 span))

(defstruct (for-node (:include ast-node)
                     (:constructor %make-for-node
                         (var-name in-values body &optional span)))
  (var-name "" :type string :read-only t)
  (in-values nil :type list :read-only t)
  (body nil :type list :read-only t))

(defun make-for-node (var-name in-values body &optional span)
  (%make-for-node var-name
                  (%copy-ast-list in-values)
                  (%copy-ast-list body)
                  span))

(defstruct (while-node (:include ast-node)
                       (:constructor %make-while-node (condition body &optional span)))
  (condition nil :type (or null ast-node) :read-only t)
  (body nil :type list :read-only t))

(defun make-while-node (condition body &optional span)
  (%make-while-node condition (%copy-ast-list body) span))

(defstruct (case-clause
            (:constructor %allocate-case-clause)
            (:copier nil)
            (:predicate %case-clause-p)
            (:conc-name %case-clause-))
  (pattern "*" :type string :read-only t)
  (body nil :type list :read-only t))

(defun case-clause-p (value)
  (%case-clause-p value))

(defun make-case-clause (pattern body)
  (%allocate-case-clause
   :pattern (%ensure-ast-string pattern "CASE-CLAUSE pattern")
   :body (%copy-ast-list body)))

(defun case-clause-pattern (clause)
  (%case-clause-pattern clause))

(defun case-clause-body (clause)
  (%copy-ast-list (%case-clause-body clause)))

(defstruct (case-node (:include ast-node)
                      (:constructor %make-case-node (value clauses &optional span)))
  (value "" :type string :read-only t)
  (clauses nil :type list :read-only t))

(defun make-case-node (value clauses &optional span)
  (%make-case-node value (%copy-ast-list clauses) span))

(defstruct (begin-end-node (:include ast-node)
                           (:constructor %make-begin-end-node (body &optional span)))
  (body nil :type list :read-only t))

(defun make-begin-end-node (body &optional span)
  (%make-begin-end-node (%copy-ast-list body) span))

(defstruct (argument-node (:include ast-node)
                          (:constructor %make-argument-node (value &optional span)))
  (value "" :type string :read-only t))

(defstruct (operator-node (:include ast-node)
                          (:constructor %make-operator-node (operator &optional span)))
  (operator "" :type string :read-only t))

(defstruct (error-node (:include ast-node)
                       (:constructor %make-error-node (message position &optional span)))
  (message "" :type string :read-only t)
  (position 0 :type integer :read-only t))

(defstruct (incomplete-node (:include ast-node)
                            (:constructor %make-incomplete-node (partial-text kind &optional span)))
  (partial-text "" :type string :read-only t)
  (kind :unknown :type keyword :read-only t))


;; -- Arg utilities ------------------------------------------
(defstruct (command-arg
            (:constructor %allocate-command-arg)
            (:copier nil)
            (:predicate %command-arg-p)
            (:conc-name %command-arg-))
  (value "" :type string :read-only t)
  (quote-style nil :type (member nil :single :double) :read-only t))

(defun command-arg-p (value)
  (%command-arg-p value))

(defun make-command-arg (value &optional quote-style)
  (%allocate-command-arg
   :value (%ensure-ast-string value "COMMAND-ARG value")
   :quote-style (%validated-command-arg-quote-style value quote-style)))

(defun command-arg-value (arg)
  (%command-arg-value arg))

(defun command-arg-quote-style (arg)
  (%command-arg-quote-style arg))

(defun %command-arg (arg)
  (etypecase arg
    (command-arg arg)
    (string (make-command-arg arg nil))))

(defun %validated-command-arg-quote-style (arg style)
  (case style
    ((nil :single :double) style)
    (t (error "Invalid quote style ~S in arg ~S" style arg))))

(defun arg-value (arg)
  "Return the string value from a typed command argument."
  (command-arg-value (%command-arg arg)))

(defun arg-quote-style (arg)
  "Return the quote style of ARG: NIL, :SINGLE, or :DOUBLE."
  (%validated-command-arg-quote-style
   arg
   (command-arg-quote-style (%command-arg arg))))

(defun command-node-arg-values (node)
  "Return all typed args as plain strings."
  (mapcar #'arg-value (command-node-args node)))

(defun ast-node->command-line (ast)
  "Render a command or pipeline AST node as a shell command line string."
  (cond
    ((command-node-p ast)
     (format nil "~{~a~^ ~}"
             (cons (command-node-command ast)
                   (command-node-arg-values ast))))
    ((pipeline-node-p ast)
     (format nil "~{~a~^ | ~}"
             (mapcar #'ast-node->command-line
                     (pipeline-node-commands ast))))
    (t "")))
