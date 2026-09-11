(in-package #:nshell.application)

(declaim (ftype function
                nshell.infrastructure.persistence::history-record-for-entry
                nshell.infrastructure.persistence::history-record-matches-p
                nshell.infrastructure.persistence::history-record-filter-token))

(defparameter +history-filter-usage+
  "history [--failed|--success|--exit CODE|--cwd PATH|--origin SOURCE]")

(defun %history-usage ()
  (%builtin-usage
   "history"
   (%builtin-usage-clauses-summary
    (append +builtin-history-usage-clauses+
            (list +history-filter-usage+)))))

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

(defun %history-filter-with (filter key value)
  (list* key value
         (loop for (old-key old-value) on filter by #'cddr
               unless (eq old-key key)
                 append (list old-key old-value))))

(defun %history-filter-merge (filter additions)
  (loop with result = filter
        for (key value) on additions by #'cddr
        do (setf result (%history-filter-with result key value))
        finally (return result)))

(defun %history-filter-options (args)
  (labels ((parse (remaining filter query)
             (if (endp remaining)
                 (values filter (nreverse query) nil)
                 (let* ((argument (first remaining))
                        (token-filter
                          (nshell.infrastructure.persistence::history-record-filter-token
                           argument)))
                   (cond
                     ((string= argument "--failed")
                      (parse (rest remaining)
                             (%history-filter-with filter :exit-code :failed)
                             query))
                     ((string= argument "--success")
                      (parse (rest remaining)
                             (%history-filter-with filter :exit-code :success)
                             query))
                     ((and (> (length argument) 7)
                           (string= "--exit=" argument :end2 7))
                      (let ((value (ignore-errors
                                     (parse-integer argument
                                                     :start 7
                                                     :junk-allowed nil))))
                        (if value
                            (parse (rest remaining)
                                   (%history-filter-with filter :exit-code value)
                                   query)
                            (values nil nil :invalid))))
                     ((and (> (length argument) 6)
                           (string= "--cwd=" argument :end2 6))
                      (parse (rest remaining)
                             (%history-filter-with
                              filter :cwd (subseq argument 6))
                             query))
                     ((and (> (length argument) 9)
                           (string= "--origin=" argument :end2 9))
                      (let ((value (subseq argument 9)))
                        (if (member value '("typed" "proposal" "agent")
                                    :test #'string=)
                            (parse (rest remaining)
                                   (%history-filter-with
                                    filter :origin
                                    (intern (string-upcase value) :keyword))
                                   query)
                            (values nil nil :invalid))))
                     ((member argument '(("--exit" . :exit-code)
                                         ("--cwd" . :cwd)
                                         ("--origin" . :origin))
                              :test #'string= :key #'car)
                      (if (rest remaining)
                          (let ((value (second remaining)))
                            (case (cdr (assoc argument
                                               '(("--exit" . :exit-code)
                                                 ("--cwd" . :cwd)
                                                 ("--origin" . :origin))
                                               :test #'string=))
                              (:exit-code
                               (let ((code (ignore-errors
                                             (parse-integer value
                                                             :junk-allowed nil))))
                                 (if code
                                     (parse (cddr remaining)
                                            (%history-filter-with
                                             filter :exit-code code)
                                            query)
                                     (values nil nil :invalid))))
                              (:cwd
                               (parse (cddr remaining)
                                      (%history-filter-with filter :cwd value)
                                      query))
                              (:origin
                               (if (member value '("typed" "proposal" "agent")
                                           :test #'string=)
                                   (parse (cddr remaining)
                                          (%history-filter-with
                                           filter :origin
                                           (intern (string-upcase value)
                                                   :keyword))
                                          query)
                                   (values nil nil :invalid)))))
                          (values nil nil :invalid)))
                     (token-filter
                      (parse (rest remaining)
                             (%history-filter-merge filter token-filter)
                             query))
                     (t (parse (rest remaining) filter (cons argument query))))))))
    (parse args nil nil)))

(defun %history-entry-matches-filter-p (history entry filter)
  (apply #'nshell.infrastructure.persistence::history-record-matches-p
         (nshell.infrastructure.persistence::history-record-for-entry
          history entry)
         filter))

(defun %history-filter-entries (history entries filter)
  (if filter
      (remove-if-not (lambda (entry)
                       (%history-entry-matches-filter-p history entry filter))
                     entries)
      entries))

(defun %history-list (history &optional filter)
  (if (null history)
      (values nil 0)
      (values (%history-format-entries
               (reverse (%history-filter-entries
                         history
                         (history-kit:history-entries history)
                         filter)))
              0)))

(defun %history-search (history args)
  (multiple-value-bind (filter remaining invalid)
      (%history-filter-options args)
    (if invalid
        (values (%history-usage) 1)
        (multiple-value-bind (mode case-sensitive query-parts)
            (%history-search-options remaining)
          (cond
            ((not (or query-parts filter))
             (values (%history-usage) 1))
            ((null history)
             (values nil 0))
            (t
             (values
              (%history-format-entries
               (%history-filter-entries
                history
                (if query-parts
                    (history-kit:history-search
                     history (%string-join query-parts " ")
                     :mode mode
                     :case-sensitive case-sensitive
                     :smartcase (not case-sensitive))
                    (history-kit:history-entries history))
                filter))
              0)))))))

(defun %history-delete (history args)
  (cond
    ((null args) (values (%history-usage) 1))
    ((null history) (values (format nil "~d~%" 0) 0))
    (t (values (format nil "~d~%" (history-kit:history-delete
                                    history (%string-join args " ")))
               0))))

(defun %history-clear (history args)
  (declare (ignore args))
  (when history
    (history-kit:history-clear history))
  (values nil 0))

(defun %history-size (history args)
  (declare (ignore args))
  (values (format nil "~d~%" (if history (history-kit:history-count history) 0)) 0))

(define-builtin %builtin-history (context args) ()
  (let ((history (shell-context-history context)))
    (if args
        (let ((spec (cdr (assoc (first args)
                                +history-subcommand-specs+
                                :test #'string=))))
          (if spec
              (funcall (getf spec :handler) history (rest args))
              (multiple-value-bind (filter query invalid)
                  (%history-filter-options args)
                (if (or invalid query)
                    (values (%history-usage) 1)
                    (%history-list history filter)))))
        (%history-list history))))
