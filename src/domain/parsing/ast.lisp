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
              (if (and here-doc-target-p (command-arg-quote-style arg))
                  (make-command-arg
                   (command-arg-value arg)
                   (command-arg-quote-style arg)
                   t
                   (command-arg-fragments arg)
                   (command-arg-source-span arg)
                   (command-arg-glob-p arg))
                  arg)
            (setf here-doc-target-p
                  (and (null (command-arg-quote-style arg))
                       (member (command-arg-value arg)
                               (list "<<" "<<-")
                               :test (function string=)))))))

(defstruct (ast-node (:constructor %make-ast-node (type &optional span)))
  (type :unknown :type keyword :read-only t)
  (span nil :type list :read-only t))

(defstruct (command-node
             (:include ast-node)
             (:constructor %make-command-node
                 (command args &optional span command-quote-style
                          command-fragments redirects force-external-p)))
  (command "" :type string :read-only t)
  (command-quote-style nil :type (member nil :single :double) :read-only t)
  (args nil :type list :read-only t)
  (command-fragments nil :type list :read-only t)
  (redirects nil :type list :read-only t)
  (force-external-p nil :type boolean :read-only t))

(defun %command-node-fragment-quote-style (fragments)
  (let ((styles
          (remove-duplicates
           (mapcar #'command-fragment-quote-style fragments))))
    (when (= (length styles) 1)
      (first styles))))
(defun %copy-redirect-entries (redirects)
  (if redirects
      (progn
        (unless (and (listp redirects)
                     (every (lambda (redirect)
                              (redirect-entry-p redirect))
                            redirects))
          (error "Command redirects must be a list of redirect entries: ~S"
                 redirects))
        (copy-list redirects))
    nil))
(defun make-command-node (command args &optional span command-quote-style
                                  command-fragments redirects force-external-p)
  (let ((fragments
         (%copy-command-fragments
          (or command-fragments
              (list (make-command-fragment command command-quote-style))))))
    (%make-command-node command
                        (%copy-command-args args)
                        span
                        (%command-node-fragment-quote-style fragments)
                        fragments
                        (%copy-redirect-entries redirects)
                        (and force-external-p t))))

(defun %validated-source-span (span)
  (when span
    (unless (and (consp span)
                 (consp (cdr span))
                 (null (cddr span))
                 (every (lambda (position)
                          (and (integerp position)
                               (<= 0 position)))
                        span)
                 (<= (first span) (second span)))
      (error "Source span must be NIL or a half-open pair of non-negative integers: ~S"
             span))
    (copy-list span)))
(define-value-struct pipeline-edge
    ((kind :pipe :type (member :pipe :pipe-stderr-to-stdout))
     (source-span nil :type (or null list) :copy %validated-source-span))
  :keyword-constructor t)
(defun make-pipeline-edge (kind &optional source-span)
  (unless (member kind (list :pipe :pipe-stderr-to-stdout))
    (error "Invalid pipeline edge kind: ~S" kind))
  (%make-pipeline-edge :kind kind
                       :source-span (%validated-source-span source-span)))
(defstruct (pipeline-node
             (:include ast-node)
             (:constructor %make-pipeline-node (commands &optional span edges)))
  (commands nil :type list :read-only t)
  (edges nil :type list :read-only t))
(defun %copy-pipeline-edges (edges)
  (if edges
      (progn
        (unless (and (listp edges)
                     (every (lambda (edge) (pipeline-edge-p edge)) edges))
          (error "Pipeline edges must be a list of pipeline edges: ~S" edges))
        (copy-list edges))
    nil))

(defmacro define-ast-constructor (name lambda-list constructor &body arguments)
  `(defun ,name ,lambda-list
     (,constructor ,@arguments)))

(defun make-pipeline-node (commands &optional span edges)
  (let* ((commands (%copy-ast-list commands))
         (edges (%copy-pipeline-edges edges)))
    (when (and edges
               (/= (length edges) (max 0 (1- (length commands)))))
      (error "Pipeline edge count must be one less than command count: ~S edges for ~S commands"
             (length edges)
             (length commands)))
    (%make-pipeline-node commands span edges)))

(defstruct (sequence-node (:include ast-node)
                           (:constructor %make-sequence-node (commands &optional separators span)))
  "Represents a sequence of command or pipeline items and their following separators. A terminal :amp is retained on the final item; otherwise the last item has no following separator."
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t))

(define-ast-constructor make-sequence-node
    (commands &optional separators span)
    %make-sequence-node
    (%copy-ast-list commands)
    (%copy-ast-list separators)
    span)

(define-value-struct sequence-node-command-separator
    ((command nil)
     (separator nil)))

(defun sequence-node-command-separators (node)
  "Return one pair per sequence item. The command slot may hold a command or pipeline node. A terminal :amp stays on the final item; other final items receive nil."
  (mapcar #'%make-sequence-node-command-separator
          (sequence-node-commands node)
          (append (sequence-node-separators node) '(nil))))

(defmacro define-ast-leaf-node (name constructor lambda-list &body slots)
  `(defstruct (,name (:include ast-node)
                    (:constructor ,constructor ,lambda-list))
     ,@slots))

(define-ast-leaf-node argument-node %make-argument-node
    (value &optional span)
  (value "" :type string :read-only t))
(define-ast-leaf-node operator-node %make-operator-node
    (operator &optional span)
  (operator "" :type string :read-only t))
(define-ast-leaf-node error-node %make-error-node
    (message position &optional span)
  (message "" :type string :read-only t)
  (position 0 :type integer :read-only t))
(define-ast-leaf-node incomplete-node %make-incomplete-node
    (partial-text kind &optional span)
  (partial-text "" :type string :read-only t)
  (kind :unknown :type keyword :read-only t))
