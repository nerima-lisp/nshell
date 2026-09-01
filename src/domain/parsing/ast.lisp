;;; AST Node Types
(in-package #:nshell.domain.parsing)

(defun %ensure-ast-string (value field-name)
  (unless (stringp value)
    (error "~A must be a string: ~S" field-name value))
  value)
(defun %validated-command-quote-style (value style)
  (case style
    ((nil :single :double) style)
    (t (error "Invalid quote style ~S in value ~S" style value))))
(defun %copy-command-fragment-escaped-positions (positions)
  (if positions
      (progn
        (unless (and (listp positions)
                     (every (lambda (position)
                             (and (integerp position)
                                  (<= 0 position)))
                            positions))
          (error "Command fragment escaped positions must be non-negative integers: ~S"
                 positions))
        (copy-list positions))
      nil))
(define-value-struct command-fragment
    ((value "" :type string)
     (quote-style nil :type (member nil :single :double))
     (escaped-positions nil :type list
                        :copy %copy-command-fragment-escaped-positions))
  :keyword-constructor t)
(defun make-command-fragment (value &optional quote-style escaped-positions)
  (%make-command-fragment
   :value (%ensure-ast-string value "COMMAND-FRAGMENT value")
   :quote-style (%validated-command-quote-style value quote-style)
   :escaped-positions
   (%copy-command-fragment-escaped-positions escaped-positions)))
(defun %copy-command-fragments (fragments)
  (if fragments
      (progn
        (unless (and (listp fragments)
                     (every #'command-fragment-p fragments))
          (error "Command fragments must be a list of command fragments: ~S"
                 fragments))
        (copy-list fragments))
      nil))

(defun %copy-ast-list (items)
  (if items
      (progn
        (unless (listp items)
          (error "AST list slot must be a list: ~S" items))
        (copy-list items))
      nil))

(defun %copy-command-args (args)
  (loop with here-doc-target-p = nil
        for original in (%copy-ast-list args)
        for arg = (%command-arg original)
        collect
          (prog1
              (if (and here-doc-target-p
                       (command-arg-quote-style arg))
                  (make-command-arg
                   (command-arg-value arg)
                   (command-arg-quote-style arg)
                   t
                   (command-arg-fragments arg))
                  arg)
            (setf here-doc-target-p
                  (and (null (command-arg-quote-style arg))
                       (member (command-arg-value arg)
                               '("<<" "<<-")
                               :test #'string=))))))

(defstruct (ast-node (:constructor %make-ast-node (type &optional span)))
  (type :unknown :type keyword :read-only t)
  (span nil :type list :read-only t))

(defstruct (command-node (:include ast-node)
                         (:constructor %make-command-node
                             (command args &optional span command-quote-style
                                      command-fragments)))
  (command "" :type string :read-only t)
  (command-quote-style nil :type (member nil :single :double) :read-only t)
  (args nil :type list :read-only t)
  (command-fragments nil :type list :read-only t))

(defun %command-node-fragment-quote-style (fragments)
  (let ((styles
          (remove-duplicates
           (mapcar #'command-fragment-quote-style fragments))))
    (when (= (length styles) 1)
      (first styles))))
(defun make-command-node (command args &optional span command-quote-style
                                           command-fragments)
  (let ((fragments
          (%copy-command-fragments
           (or command-fragments
               (list (make-command-fragment command command-quote-style))))))
    (%make-command-node command
                        (%copy-command-args args)
                        span
                        (%command-node-fragment-quote-style fragments)
                        fragments)))

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

(define-value-struct sequence-node-command-separator
    ((command nil)
     (separator nil)))

(defun sequence-node-command-separators (node)
  "Return SEQUENCE-NODE-COMMAND-SEPARATOR values for NODE in command order,
pairing each command with the separator that follows it (NIL after the last).
Expressed as a pure zip -- no mutable running list -- since MAPCAR stops at the
shorter argument and the command list is one longer than the separators."
  (mapcar #'%make-sequence-node-command-separator
          (sequence-node-commands node)
          (append (sequence-node-separators node) '(nil))))

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
(define-value-struct command-arg
    ((value "" :type string)
     (quote-style nil :type (member nil :single :double))
     (here-doc-literal-p nil :type boolean)
     (fragments nil :type list :copy %copy-command-fragments))
  :keyword-constructor t)

(defun make-command-arg (value &optional quote-style here-doc-literal-p
                                      fragments)
  (%make-command-arg
   :value (%ensure-ast-string value "COMMAND-ARG value")
   :quote-style (%validated-command-quote-style value quote-style)
   :here-doc-literal-p (and here-doc-literal-p t)
   :fragments (%copy-command-fragments
               (or fragments
                   (list (make-command-fragment value quote-style))))))

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

(defun arg-here-doc-literal-p (arg)
  "Return true when ARG is a quoted here-document target/body argument."
  (command-arg-here-doc-literal-p (%command-arg arg)))

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
