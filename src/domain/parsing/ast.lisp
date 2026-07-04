;;; AST Node Types
(in-package #:nshell.domain.parsing)

(defun %copy-ast-list (items)
  (copy-list (or items '())))

(defun %copy-command-args (args)
  (mapcar #'%command-arg args))

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

(defstruct (case-clause (:constructor make-case-clause (pattern body)))
  (pattern "*" :type string :read-only t)
  (body nil :type list :read-only t))

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
            (:constructor make-command-arg (value &optional quote-style)))
  (value "" :type string :read-only t)
  (quote-style nil :type (member nil :single :double) :read-only t))

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

(defstruct (%command-redirect-split-state
            (:constructor %make-command-redirect-split-state (clean redirects)))
  (clean nil :type list :read-only t)
  (redirects nil :type list :read-only t))

(defun %empty-command-redirect-split-state ()
  (%make-command-redirect-split-state nil nil))

(defun %command-redirect-split-state-push-clean (state arg)
  (%make-command-redirect-split-state
   (cons arg (%command-redirect-split-state-clean state))
   (%command-redirect-split-state-redirects state)))

(defun %command-redirect-split-state-push-redirect (state kind target)
  (%make-command-redirect-split-state
   (%command-redirect-split-state-clean state)
   (cons (cons kind target)
         (%command-redirect-split-state-redirects state))))

(defstruct (%command-redirect-arg-cursor
            (:constructor %make-command-redirect-arg-cursor
                (arg remaining-args)))
  (arg nil :read-only t)
  (remaining-args nil :type list :read-only t))

(defun %command-redirect-arg-cursor-from-args (args)
  (when args
    (%make-command-redirect-arg-cursor (first args) (rest args))))

(defun %command-redirect-arg-cursor-after-current (cursor)
  (%command-redirect-arg-cursor-from-args
   (%command-redirect-arg-cursor-remaining-args cursor)))

(defun %command-redirect-arg-cursor-target-arg (cursor)
  (first (%command-redirect-arg-cursor-remaining-args cursor)))

(defun %command-redirect-arg-cursor-after-target (cursor)
  (%command-redirect-arg-cursor-from-args
   (rest (%command-redirect-arg-cursor-remaining-args cursor))))

(defun %command-redirect-split-state-accept-cursor (state cursor)
  (let* ((arg (%command-redirect-arg-cursor-arg cursor))
         (value (arg-value arg))
         (redirect-facts (%redirect-facts value)))
    (cond
      ((and redirect-facts
            (%redirect-facts-fd-dup-p redirect-facts))
       (values
        (%command-redirect-split-state-push-redirect
         state
         (%redirect-facts-kind redirect-facts)
         nil)
        (%command-redirect-arg-cursor-after-current cursor)))
      ((and redirect-facts
            (%command-redirect-arg-cursor-remaining-args cursor))
       (values
        (%command-redirect-split-state-push-redirect
         state
         (%redirect-facts-kind redirect-facts)
         (arg-value (%command-redirect-arg-cursor-target-arg cursor)))
        (%command-redirect-arg-cursor-after-target cursor)))
      (t
       (values (%command-redirect-split-state-push-clean state arg)
               (%command-redirect-arg-cursor-after-current cursor))))))

(defun %command-redirect-split-state-values (state)
  (values (nreverse (%command-redirect-split-state-clean state))
          (nreverse (%command-redirect-split-state-redirects state))))

(defun split-command-node-redirects (cmd-node)
  "Split CMD-NODE into (clean-command-node redirects).
Redirect operator args and their targets are removed from the clean command."
  (let ((state (%empty-command-redirect-split-state))
        (cursor (%command-redirect-arg-cursor-from-args
                 (command-node-args cmd-node))))
    (loop while cursor
          do (multiple-value-setq (state cursor)
               (%command-redirect-split-state-accept-cursor state cursor)))
    (multiple-value-bind (clean redirects)
        (%command-redirect-split-state-values state)
      (values (make-command-node
               (command-node-command cmd-node)
               clean
               (ast-node-span cmd-node)
              (command-node-command-quote-style cmd-node))
              redirects))))

(defstruct (%command-list-redirect-split-state
            (:constructor %make-command-list-redirect-split-state
                (clean-commands redirects)))
  (clean-commands nil :type list :read-only t)
  (redirects nil :type list :read-only t))

(defun %empty-command-list-redirect-split-state ()
  (%make-command-list-redirect-split-state nil nil))

(defun %command-list-redirect-split-state-push (state clean-command command-redirects)
  (%make-command-list-redirect-split-state
   (cons clean-command
         (%command-list-redirect-split-state-clean-commands state))
   (cons command-redirects
         (%command-list-redirect-split-state-redirects state))))

(defun %command-list-redirect-split-state-accept-command (state command)
  (multiple-value-bind (clean-command command-redirects)
      (split-command-node-redirects command)
    (%command-list-redirect-split-state-push
     state
     clean-command
     command-redirects)))

(defun %command-list-redirect-split-state-values (state)
  (values
   (nreverse (%command-list-redirect-split-state-clean-commands state))
   (nreverse (%command-list-redirect-split-state-redirects state))))

(defun split-command-nodes-redirects (commands)
  "Split each command in COMMANDS into (clean-commands per-stage-redirects)."
  (let ((state (%empty-command-list-redirect-split-state)))
    (dolist (command commands)
      (setf state
            (%command-list-redirect-split-state-accept-command state command)))
    (%command-list-redirect-split-state-values state)))

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
