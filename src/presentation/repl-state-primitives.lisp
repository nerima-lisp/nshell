(in-package #:nshell.presentation)

(defmacro %define-repl-state-table-factory (name test)
  `(defun ,name ()
     (make-hash-table :test ,test)))

(%define-repl-state-table-factory %make-repl-name-table #'equal)
(%define-repl-state-table-factory %make-repl-process-registry #'eql)

(defun %make-repl-state-tables ()
  (values (%make-repl-name-table)
          (%make-repl-name-table)
          (%make-repl-name-table)
          (%make-repl-name-table)
          (%make-repl-process-registry)))
