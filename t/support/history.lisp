(in-package #:nshell/test)

(defun history-with-lines (&rest lines)
  (let ((history (nshell.domain.history:make-command-history :max-entries 100)))
    (dolist (line lines history)
      (nshell.domain.history:history-add history line))))

(defmacro with-history ((name &rest lines) &body body)
  `(let ((,name (history-with-lines ,@lines)))
     ,@body))

(defmacro with-repl-history-lines ((&rest lines) &body body)
  `(with-repl-test-state
     (with-history (history ,@lines)
       (setf nshell.presentation::*history* history)
       ,@body)))
