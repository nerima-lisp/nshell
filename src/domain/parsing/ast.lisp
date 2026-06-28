;;; AST Node Types
(in-package #:nshell.domain.parsing)

(defstruct (ast-node (:constructor make-ast-node (type &optional span)))
  (type :unknown :type keyword :read-only t)
  (span nil :type list :read-only t))

(defstruct (command-node (:include ast-node)
                         (:constructor make-command-node
                             (command args &optional span command-quote-style)))
  (command "" :type string :read-only t)
  (command-quote-style nil :type (member nil :single :double) :read-only t)
  (args nil :type list :read-only t))

(defstruct (pipeline-node (:include ast-node)
                          (:constructor make-pipeline-node (commands &optional span)))
  (commands nil :type list :read-only t))

(defstruct (sequence-node (:include ast-node)
                           (:constructor make-sequence-node (commands &optional separators span)))
  "Represents shell command sequences separated by ;, &, &&, or ||.
   SEPARATORS is a list of :semi, :amp, :and, or :or keywords, one per command except the last."
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t))

(defun %sequence-node-command-separator-pairs (node)
  (let ((separators (copy-list (sequence-node-separators node))))
    (loop for command in (sequence-node-commands node)
          collect (cons command (pop separators)))))

(defmacro do-sequence-node-command-separator-pairs ((command separator node &optional result) &body body)
  `(dolist (pair (%sequence-node-command-separator-pairs ,node) ,result)
     (let ((,command (car pair))
           (,separator (cdr pair)))
       ,@body)))

(defstruct (if-node (:include ast-node)
                    (:constructor make-if-node (condition then-branch &optional else-branch span)))
  (condition nil :type (or null ast-node) :read-only t)
  (then-branch nil :type list :read-only t)
  (else-branch nil :type list :read-only t))

(defstruct (for-node (:include ast-node)
                     (:constructor make-for-node (var-name in-values body &optional span)))
  (var-name "" :type string :read-only t)
  (in-values nil :type list :read-only t)
  (body nil :type list :read-only t))

(defstruct (while-node (:include ast-node)
                       (:constructor make-while-node (condition body &optional span)))
  (condition nil :type (or null ast-node) :read-only t)
  (body nil :type list :read-only t))

(defstruct (case-node (:include ast-node)
                      (:constructor make-case-node (value clauses &optional span)))
  (value "" :type string :read-only t)
  (clauses nil :type list :read-only t))

(defstruct (begin-end-node (:include ast-node)
                           (:constructor make-begin-end-node (body &optional span)))
  (body nil :type list :read-only t))

(defstruct (argument-node (:include ast-node)
                          (:constructor make-argument-node (value &optional span)))
  (value "" :type string :read-only t))

(defstruct (operator-node (:include ast-node)
                          (:constructor make-operator-node (operator &optional span)))
  (operator "" :type string :read-only t))

(defstruct (error-node (:include ast-node)
                       (:constructor make-error-node (message position &optional span)))
  (message "" :type string :read-only t)
  (position 0 :type integer :read-only t))

(defstruct (incomplete-node (:include ast-node)
                            (:constructor make-incomplete-node (partial-text kind &optional span)))
  (partial-text "" :type string :read-only t)
  (kind :unknown :type keyword :read-only t))


;; -- Arg utilities (cons-based arg support) -----------------
(defun arg-value (arg)
  "Extract string value from an arg (string or (value . quote-style) cons)."
  (if (consp arg) (car arg) arg))

(defun arg-quote-style (arg)
  "Return the quote style of ARG: NIL, :SINGLE, or :DOUBLE.
Bare-string args and redirect-target conses are unquoted."
  (when (consp arg)
    (let ((style (cdr arg)))
      (case style
        ((nil :single :double) style)
        (t (error "Invalid quote style ~S in arg ~S" style arg))))))

(defun command-node-arg-values (node)
  "Return all args as plain strings (unwrapping cons cells)."
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
