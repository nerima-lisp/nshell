(in-package #:nshell.presentation)

(defun %reset-repl-state-tables ()
  (multiple-value-setq (*aliases*
                        *abbreviations*
                        *functions*
                        *function-sources*
                        *proc-registry*)
    (%make-repl-state-tables))
  (clrhash *completion-help-cache*)
  (values))

(defmacro with-fresh-repl-state-tables (&body body)
  `(multiple-value-bind (*aliases*
                         *abbreviations*
                         *functions*
                         *function-sources*
                         *proc-registry*)
       (%make-repl-state-tables)
     (let ((*completion-help-cache* (make-hash-table :test #'equal)))
       ,@body)))
