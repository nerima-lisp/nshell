(in-package #:nshell.domain.parsing)

(define-value-struct command-arg
    ((value "" :type string)
     (quote-style nil :type (member nil :single :double))
     (here-doc-literal-p nil :type boolean)
     (fragments nil :type list :copy %copy-command-fragments)
     (source-span nil :type (or null list) :copy %validated-source-span)
     (glob-p nil :type boolean))
  :keyword-constructor t)

(defun make-command-arg (value &optional quote-style here-doc-literal-p
                                      fragments source-span
                                      (glob-p nil glob-p-supplied-p))
  (%make-command-arg
   :value (%ensure-ast-string value "COMMAND-ARG value")
   :quote-style (%validated-command-quote-style value quote-style)
   :here-doc-literal-p (and here-doc-literal-p t)
   :fragments (%copy-command-fragments
               (or fragments
                   (list (make-command-fragment value quote-style))))
   :source-span (%validated-source-span source-span)
   :glob-p (and (if glob-p-supplied-p glob-p (null quote-style)) t)))

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

(define-value-struct evaluated-command-arg
    ((value nil :type t)
     (source-span nil :type (or null list) :copy %validated-source-span)
     (glob-p nil :type boolean))
  :keyword-constructor t)
(defun make-evaluated-command-arg (value &optional source-span glob-p)
  (%make-evaluated-command-arg
   :value value
   :source-span (%validated-source-span source-span)
   :glob-p (and glob-p t)))
(defun %validated-nonnegative-integer (value field-name)
  (unless (and (integerp value) (<= 0 value))
    (error "~A must be a non-negative integer: ~S" field-name value))
  value)
(defun %validated-redirect-file-descriptor (value)
  (when value
    (%validated-nonnegative-integer value "File descriptor"))
  value)
(define-value-struct redirect-fd-target
    ((file-descriptor 0 :type (integer 0 *)))
  :keyword-constructor t)
(defun make-redirect-fd-target (file-descriptor)
  (%make-redirect-fd-target
   :file-descriptor
   (%validated-nonnegative-integer file-descriptor "File descriptor")))
(define-value-struct redirect-fd-close-target ())
(defun make-redirect-fd-close-target ()
  (%make-redirect-fd-close-target))
(define-value-struct redirect-heredoc-target
    ((delimiter nil :type command-arg)
     (body "" :type string)
     (expand-p nil :type boolean)
     (strip-tabs-p nil :type boolean)
     (body-span nil :type (or null list) :copy %validated-source-span))
  :keyword-constructor t)
(defun make-redirect-heredoc-target (delimiter body expand-p strip-tabs-p
                                               body-span)
  (unless (command-arg-p delimiter)
    (error "Here-document delimiter must be a command argument: ~S" delimiter))
  (%make-redirect-heredoc-target
   :delimiter delimiter
   :body (%ensure-ast-string body "REDIRECT-HEREDOC-TARGET body")
   :expand-p (and expand-p t)
   :strip-tabs-p (and strip-tabs-p t)
   :body-span (%validated-source-span body-span)))
(define-value-struct redirect-procsub-target
    ((direction :input :type (member :input :output))
     (form nil :type ast-node))
  :keyword-constructor t)
(defun make-redirect-procsub-target (direction form)
  (unless (member direction (list :input :output))
    (error "Process-substitution direction must be :INPUT or :OUTPUT: ~S"
           direction))
  (unless (ast-node-p form)
    (error "Process-substitution form must be an AST node: ~S" form))
  (%make-redirect-procsub-target :direction direction :form form))
(define-value-struct ast-redirect-entry
    ((kind :input-file
           :type (member :input-file :output-file :append-output-file
                         :force-output-file :error-file :append-error-file
                         :both-output-files :append-both-output-files
                         :duplicate-input-fd :duplicate-output-fd
                         :here-document :here-document-strip-tabs
                         :here-string :process-substitution-input
                         :process-substitution-output))
     (file-descriptor nil :type (or null (integer 0 *)))
     (target nil :type (or command-arg redirect-fd-target
                           redirect-fd-close-target redirect-heredoc-target
                           redirect-procsub-target))
     (source-span nil :type (or null list) :copy %validated-source-span)
     (source-order 0 :type (integer 0 *)))
  :keyword-constructor t)
(defun make-ast-redirect-entry (kind file-descriptor target source-span source-order)
  (unless (member kind
                  (list :input-file :output-file :append-output-file
                        :force-output-file :error-file :append-error-file
                        :both-output-files :append-both-output-files
                        :duplicate-input-fd :duplicate-output-fd
                        :here-document :here-document-strip-tabs
                        :here-string :process-substitution-input
                        :process-substitution-output))
    (error "Invalid redirect kind: ~S" kind))
  (unless (or (command-arg-p target)
              (redirect-fd-target-p target)
              (redirect-fd-close-target-p target)
              (redirect-heredoc-target-p target)
              (redirect-procsub-target-p target))
    (error "Redirect target has an unsupported type: ~S" target))
  (%make-ast-redirect-entry
   :kind kind
   :file-descriptor (%validated-redirect-file-descriptor file-descriptor)
   :target target
   :source-span (%validated-source-span source-span)
   :source-order
   (%validated-nonnegative-integer source-order "Redirect source order")))
(defun ast-node->command-line (ast)
  "Render a command or pipeline AST node as a shell command line string."
  (cond
   ((command-node-p ast)
    (format nil "~{~a~^ ~}"
            (cons (command-node-command ast)
                  (command-node-arg-values ast))))
   ((pipeline-node-p ast)
    (format nil "~{~a~^ | ~}"
            (mapcar (function ast-node->command-line)
                    (pipeline-node-commands ast))))
   (t "")))
