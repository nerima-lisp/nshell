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
                          command-fragments redirects force-external-p
                          argument-forms)))
  (command "" :type string :read-only t)
  (command-quote-style nil :type (member nil :single :double) :read-only t)
  (args nil :type list :read-only t)
  (argument-forms nil :type list :read-only t)
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
                              (ast-redirect-entry-p redirect))
                            redirects))
          (error "Command redirects must be a list of redirect entries: ~S"
                 redirects))
        (copy-list redirects))
    nil))
(defun make-command-node (command args &optional span command-quote-style
                                  command-fragments redirects force-external-p
                                  (argument-forms nil argument-forms-supplied-p))
  (let* ((legacy-args (%copy-command-args args))
         (argument-forms
           (%copy-command-argument-forms
            (if argument-forms-supplied-p argument-forms legacy-args)))
         (argument-args
           (if argument-forms-supplied-p
               (%command-argument-forms-command-args argument-forms)
               legacy-args))
         (fragments
           (%copy-command-fragments
            (or command-fragments
                (list (make-command-fragment command command-quote-style)))))
         (validated-span (%validated-source-span span)))
    (when (and argument-forms-supplied-p
               legacy-args
               (not (%command-arg-sequences-equal-p
                     legacy-args
                     argument-args)))
      (error "COMMAND-NODE args must match its command-argument projection: ~S"
             args))
    (%make-command-node command
                        argument-args
                        validated-span
                        (%command-node-fragment-quote-style fragments)
                        fragments
                        (%copy-redirect-entries redirects)
                        (and force-external-p t)
                        argument-forms)))

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

(define-value-struct command-value-form
    ((kind :value :type (member :value :splice :quoted))
     (form nil :type t)
     (source-span nil :type (or null list) :copy %validated-source-span))
  :keyword-constructor t)

(defun make-command-value-form (kind form &optional source-span)
  (unless (member kind '(:value :splice :quoted))
    (error "Invalid command value form kind: ~S" kind))
  (%make-command-value-form :kind kind
                            :form form
                            :source-span (%validated-source-span source-span)))

(defun %copy-command-argument-forms (forms)
  (unless (and (listp forms)
               (every (lambda (form)
                        (or (command-arg-p form)
                            (command-value-form-p form)))
                      forms))
    (error "Command argument forms must contain command args or value forms: ~S"
           forms))
  (copy-list forms))

(defun %command-argument-forms-command-args (forms)
  (remove-if-not #'command-arg-p forms))

(defun %command-arg-sequences-equal-p (left right)
  (and (= (length left) (length right))
       (every (lambda (left-arg right-arg)
                (and (string= (command-arg-value left-arg)
                              (command-arg-value right-arg))
                     (eql (command-arg-quote-style left-arg)
                          (command-arg-quote-style right-arg))
                     (eql (command-arg-here-doc-literal-p left-arg)
                          (command-arg-here-doc-literal-p right-arg))
                     (equal (mapcar
                             (lambda (fragment)
                               (list (command-fragment-value fragment)
                                     (command-fragment-quote-style fragment)
                                     (command-fragment-escaped-positions fragment)))
                             (command-arg-fragments left-arg))
                            (mapcar
                             (lambda (fragment)
                               (list (command-fragment-value fragment)
                                     (command-fragment-quote-style fragment)
                                     (command-fragment-escaped-positions fragment)))
                             (command-arg-fragments right-arg)))
                     (equal (command-arg-source-span left-arg)
                            (command-arg-source-span right-arg))
                     (eql (command-arg-glob-p left-arg)
                          (command-arg-glob-p right-arg))))
              left
              right)))
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
  (let ((span-form (car (last arguments)))
        (constructor-arguments (butlast arguments)))
    `(defun ,name ,lambda-list
       (,constructor ,@constructor-arguments
                     (%validated-source-span ,span-form)))))

(defun make-pipeline-node (commands &optional span edges)
  (let* ((commands (%copy-ast-list commands))
         (edges (%copy-pipeline-edges edges))
         (span (%validated-source-span span)))
    (when (and edges
               (/= (length edges) (max 0 (1- (length commands)))))
      (error "Pipeline edge count must be one less than command count: ~S edges for ~S commands"
             (length edges)
             (length commands)))
    (%make-pipeline-node commands span edges)))

(defstruct (sequence-node (:include ast-node)
                           (:constructor %make-sequence-node (commands &optional separators span)))
  "Represents a sequence of AST items and their following separators. A terminal :amp is retained on the final item; otherwise the last item has no following separator."
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t))

(defun make-sequence-node (commands &optional separators span)
  (let* ((commands (%copy-ast-list commands))
         (separators (%copy-ast-list separators))
         (span (%validated-source-span span)))
    (unless (every (lambda (command) (ast-node-p command))
                   commands)
      (error "Sequence items must be AST nodes: ~S" commands))
    (unless (every (lambda (separator)
                     (member separator '(:semi :and :or :amp)))
                   separators)
      (error "Invalid sequence separator: ~S" separators))
    (let ((command-count (length commands))
          (separator-count (length separators)))
      (cond
        ((zerop command-count)
         (unless (zerop separator-count)
           (error "An empty sequence cannot have separators: ~S" separators)))
        ((= separator-count command-count)
         (case (car (last separators))
           (:semi (setf separators (butlast separators)))
           ((:and :or)
            (error "A sequence cannot end in :AND or :OR: ~S" separators))
           (:amp nil)
           (otherwise
            (error "Invalid terminal sequence separator: ~S" separators))))
        ((/= separator-count (1- command-count))
         (error "Sequence separator count must be one less than item count, or match it only for terminal :AMP: ~S items, ~S separators"
                command-count
                separator-count)))
      (%make-sequence-node commands separators span))))

(define-value-struct sequence-node-command-separator
    ((command nil)
     (separator nil)))

(defun sequence-node-command-separators (node)
  "Return one pair per sequence item. Its command slot may hold any AST node. A terminal :amp stays on the final item; other final items receive nil."
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
