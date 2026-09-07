(in-package #:nshell/test)

(defun add-history-record (history text &rest initargs)
  (apply #'nshell.infrastructure.persistence::history-record-add
         history text initargs)
  history)

(defun history-with-lines (&rest lines)
  (let ((history (history-kit:make-history :capacity 100)))
    (dolist (line lines history)
      (add-history-record history line))))

(defun history-with-records (&rest records)
  (let ((history (history-kit:make-history :capacity 100)))
    (dolist (record records history)
      (apply #'add-history-record
             history
             (getf record :text)
             (loop for (key value) on record by #'cddr
                   unless (eq key :text)
                     append (list key value))))))

(defmacro with-history ((name &rest lines) &body body)
  `(let ((,name (history-with-lines ,@lines)))
     ,@body))

(defmacro with-repl-history-lines ((&rest lines) &body body)
  `(with-repl-test-state
     (with-history (history ,@lines)
       (setf nshell.presentation::*history* history)
       ,@body)))
