(in-package #:nshell.application)
(defun %history-usage ()
  (%builtin-usage
   "history"
   (%builtin-usage-clauses-summary +builtin-history-usage-clauses+)))

(defun %history-format-entries (entries)
  (when entries
    (with-output-to-string (out)
      (dolist (entry entries)
        (format out "~a~%" (history-kit:history-entry-text entry))))))

(defun %history-search-options (args)
  (labels ((parse (remaining mode case-sensitive)
             (let ((spec (and remaining
                              (cdr (assoc (first remaining)
                                          +history-search-option-specs+
                                          :test #'string=)))))
               (if spec
                   (parse (rest remaining)
                          (or (getf spec :mode) mode)
                          (or case-sensitive (getf spec :case-sensitive)))
                   (values mode case-sensitive remaining)))))
    (parse args :contains nil)))

(defun %history-list (history)
  (values (%history-format-entries
           (reverse (history-kit:history-entries history)))
          0))

(defun %history-search (history args)
  (multiple-value-bind (mode case-sensitive query-parts)
      (%history-search-options args)
    (if query-parts
        (values
         (%history-format-entries
          (history-kit:history-search
           history (%string-join query-parts " ")
           :mode mode
           :case-sensitive case-sensitive
           :smartcase (not case-sensitive)))
         0)
        (values (%history-usage) 1))))

(defun %history-delete (history args)
  (if args
      (let ((deleted (history-kit:history-delete
                      history (%string-join args " "))))
        (values (format nil "~d~%" deleted) 0))
      (values (%history-usage) 1)))

(defun %history-clear (history args)
  (declare (ignore args))
  (history-kit:history-clear history)
  (values nil 0))

(defun %history-size (history args)
  (declare (ignore args))
  (values (format nil "~d~%" (history-kit:history-count history)) 0))

(define-builtin %builtin-history (context args) ()
  (let ((history (shell-context-history context)))
    (if args
        (let ((spec (cdr (assoc (first args)
                                +history-subcommand-specs+
                                :test #'string=))))
          (if spec
              (funcall (getf spec :handler) history (rest args))
              (values (%history-usage) 1)))
        (%history-list history))))
