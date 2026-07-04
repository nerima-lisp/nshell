;;; AST Node Types
(in-package #:nshell.domain.parsing)

(defun %copy-ast-list (items)
  (copy-list (or items '())))

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
                      (%copy-ast-list args)
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

(defstruct (%sequence-node-command-separator
            (:constructor %make-sequence-node-command-separator (command separator)))
  (command nil :read-only t)
  (separator nil :read-only t))

(defun %make-sequence-node-command-separator-entry (command separator)
  (%make-sequence-node-command-separator command separator))

(defun %sequence-node-command-separators (node)
  (let ((separators (copy-list (sequence-node-separators node))))
    (loop for command in (sequence-node-commands node)
          collect (%make-sequence-node-command-separator-entry command (pop separators)))))

(defun sequence-node-command-separator-pairs (node)
  "Return (command . separator) pairs for NODE in command order."
  (mapcar (lambda (entry)
            (cons (%sequence-node-command-separator-command entry)
                  (%sequence-node-command-separator-separator entry)))
          (%sequence-node-command-separators node)))

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


;; -- Arg utilities (cons-based arg support) -----------------
(defstruct (%command-arg
            (:constructor %make-command-arg (value quote-style)))
  (value nil :read-only t)
  (quote-style nil :read-only t))

(defun %command-arg-from-raw (arg)
  (if (consp arg)
      (%make-command-arg (car arg) (cdr arg))
      (%make-command-arg arg nil)))

(defun %validated-command-arg-quote-style (arg style)
  (case style
    ((nil :single :double) style)
    (t (error "Invalid quote style ~S in arg ~S" style arg))))

(defun arg-value (arg)
  "Extract string value from an arg (string or (value . quote-style) cons)."
  (%command-arg-value (%command-arg-from-raw arg)))

(defun arg-quote-style (arg)
  "Return the quote style of ARG: NIL, :SINGLE, or :DOUBLE.
Bare-string args and redirect-target conses are unquoted."
  (when (consp arg)
    (%validated-command-arg-quote-style
     arg
     (%command-arg-quote-style (%command-arg-from-raw arg)))))

(defun command-node-arg-values (node)
  "Return all args as plain strings (unwrapping cons cells)."
  (mapcar #'arg-value (command-node-args node)))

(defun split-command-node-redirects (cmd-node)
  "Split CMD-NODE into (clean-command-node redirects).
Redirect operator args and their targets are removed from the clean command."
  (let ((clean nil)
        (redirects nil)
        (args (command-node-args cmd-node)))
    (loop with index = 0
          with limit = (length args)
          while (< index limit)
          for arg = (nth index args)
          for value = (arg-value arg)
          for spec = (assoc value +redirect-specs+ :test #'string=)
          do (cond
               ((and spec (member (cdr spec) +redirect-fd-dup-specs+))
                (push (cons (cdr spec) nil) redirects)
                (incf index))
               ((and spec (< (1+ index) limit))
                (let ((target (arg-value (nth (1+ index) args))))
                  (push (cons (cdr spec) target) redirects)
                  (incf index 2)))
               (t
                (push arg clean)
                (incf index))))
    (values (make-command-node
             (command-node-command cmd-node)
             (nreverse clean)
             (ast-node-span cmd-node)
             (command-node-command-quote-style cmd-node))
            (nreverse redirects))))

(defun split-command-nodes-redirects (commands)
  "Split each command in COMMANDS into (clean-commands per-stage-redirects)."
  (let ((clean-commands nil)
        (redirects nil))
    (dolist (command commands)
      (multiple-value-bind (clean-command command-redirects)
          (split-command-node-redirects command)
        (push clean-command clean-commands)
        (push command-redirects redirects)))
    (values (nreverse clean-commands) (nreverse redirects))))

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
