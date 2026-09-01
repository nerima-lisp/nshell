(in-package #:nshell.domain.parsing)

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
