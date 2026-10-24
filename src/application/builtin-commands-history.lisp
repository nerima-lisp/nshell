(in-package #:nshell.application)

(declaim (ftype function
                nshell.infrastructure.persistence:history-record-timestamp
                nshell.infrastructure.persistence:history-record-for-entry
                nshell.infrastructure.persistence:history-record-matches-p
                nshell.infrastructure.persistence:history-record-filter-token
                nshell.infrastructure.persistence:delete-history-entry
                nshell.infrastructure.persistence:clear-history-file))

(defparameter +history-filter-usage+
  "history [--failed|--success|--exit CODE|--cwd PATH|--origin SOURCE|--host HOST|--duration-min MS|--duration-max MS] [--timestamps]")

(defun %history-usage ()
  (%builtin-usage
   "history"
   (%builtin-usage-clauses-summary
    (append +builtin-history-usage-clauses+
            (list +history-filter-usage+)))))

(defun %history-format-entries (history entries &optional timestamps-p)
  (labels ((timestamp-string (entry)
             (let ((timestamp
                     (nshell.infrastructure.persistence:history-record-timestamp
                      (nshell.infrastructure.persistence:history-record-for-entry
                       history entry))))
               (when (integerp timestamp)
                 (handler-case
                     (multiple-value-bind (second minute hour day month year)
                         (decode-universal-time timestamp 0)
                       (format nil
                               "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ"
                               year month day hour minute second))
                   (error () nil))))))
    (when entries
      (with-output-to-string (out)
        (dolist (entry entries)
          (if timestamps-p
              (format out "~a ~a~%"
                      (or (timestamp-string entry) "-")
                      (history-kit:history-entry-text entry))
              (format out "~a~%" (history-kit:history-entry-text entry))))))))

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
  (labels ((option-p (argument name)
                     (or (string= argument name)
                         (and (> (length argument) (length name))
                              (string= name argument :end2 (length name))
                              (char= #\= (char argument (length name))))))
           (option-value (remaining name)
                         (let* ((argument (first remaining))
                                (name-length (length name)))
                           (if (> (length argument) name-length)
                               (values (subseq argument (1+ name-length)) 1)
                             (if (rest remaining)
                                 (values (second remaining) 2)
                               (values nil 1)))))
           (option-key (argument)
                       (cond
                        ((option-p argument "--exit") :exit-code)
                        ((option-p argument "--cwd") :cwd)
                        ((option-p argument "--origin") :origin)
                        ((option-p argument "--host") :host)
                        ((option-p argument "--duration-min") :duration-min-ms)
                        ((option-p argument "--duration-max") :duration-max-ms)))
           (parse-option-value (key value)
                               (case key
                                 (:cwd (if (stringp value)
                                           (values value t)
                                         (values nil nil)))
                                 (:host (if (and (stringp value)
                                                 (plusp (length value))
                                                 (not (and (> (length value) 1)
                                                           (string= "--" value :end2 2))))
                                            (values value t)
                                          (values nil nil)))
                                 (:origin
                                  (if (member value (list "typed" "proposal" "agent")
                                              :test (function string=))
                                      (values (intern (string-upcase value) :keyword) t)
                                    (values nil nil)))
                                 (otherwise
                                  (let ((number (ignore-errors
                                                 (parse-integer value :junk-allowed nil))))
                                    (if (and (integerp number)
                                             (or (eq key :exit-code)
                                                 (not (minusp number))))
                                        (values number t)
                                      (values nil nil))))))
           (parse (remaining filter query timestamps-p)
                  (if (endp remaining)
                      (values filter (nreverse query) nil timestamps-p)
                    (let* ((argument (first remaining))
                           (key (option-key argument))
                           (token-filter
                            (nshell.infrastructure.persistence:history-record-filter-token
                             argument)))
                      (cond
                       ((string= argument "--timestamps")
                        (parse (rest remaining) filter query t))
                       ((string= argument "--failed")
                        (parse (rest remaining)
                               (%history-filter-with filter :exit-code :failed)
                               query timestamps-p))
                       ((string= argument "--success")
                        (parse (rest remaining)
                               (%history-filter-with filter :exit-code :success)
                               query timestamps-p))
                       (key
                        (multiple-value-bind (raw-value consumed)
                            (option-value remaining
                                          (case key
                                            (:exit-code "--exit")
                                            (:cwd "--cwd")
                                            (:origin "--origin")
                                            (:host "--host")
                                            (:duration-min-ms "--duration-min")
                                            (:duration-max-ms "--duration-max")))
                          (multiple-value-bind (value valid-p)
                              (parse-option-value key raw-value)
                            (if valid-p
                                (parse (nthcdr consumed remaining)
                                       (%history-filter-with filter key value)
                                       query
                                       timestamps-p)
                              (values nil nil :invalid timestamps-p)))))
                       (token-filter
                        (parse (rest remaining)
                               (%history-filter-merge filter token-filter)
                               query
                               timestamps-p))
                       (t
                        (parse (rest remaining)
                               filter
                               (cons argument query)
                               timestamps-p)))))))
    (parse args nil nil nil)))

(defun %history-entry-matches-filter-p (history entry filter)
  (apply #'nshell.infrastructure.persistence:history-record-matches-p
         (nshell.infrastructure.persistence:history-record-for-entry
          history entry)
         filter))

(defun %history-filter-entries (history entries filter)
  (if filter
      (remove-if-not (lambda (entry)
                       (%history-entry-matches-filter-p history entry filter))
                     entries)
      entries))

(defun %history-list (history &optional filter timestamps-p)
  (if (null history)
      (values nil 0)
      (values (%history-format-entries
               history
               (reverse (%history-filter-entries
                         history
                         (history-kit:history-entries history)
                         filter))
               timestamps-p)
              0)))

(defun %history-search (history args)
  (multiple-value-bind (filter remaining invalid timestamps-p)
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
               history
               (%history-filter-entries
                history
                (if query-parts
                    (history-kit:history-search
                     history (%string-join query-parts " ")
                     :mode mode
                     :case-sensitive case-sensitive
                     :smartcase (not case-sensitive))
                    (history-kit:history-entries history))
                filter)
               timestamps-p)
              0)))))))

(defun %history-delete (history args)
  (cond
    ((null args) (values (%history-usage) 1))
    ((null history) (values (format nil "~d~%" 0) 0))
    (t
     (let* ((text (%string-join args " "))
            (matches
              (count text
                     (history-kit:history-entries history)
                     :key #'history-kit:history-entry-text
                     :test #'string=)))
       (cond
         ((zerop matches)
          (values (format nil "~d~%" 0) 0))
         ((not
           (nshell.infrastructure.persistence:delete-history-entry text))
          (values nil 1))
         (t
          (values (format nil "~d~%"
                          (history-kit:history-delete history text))
                  0)))))))

(defun %history-clear (history args)
  (declare (ignore args))
  (cond
    ((null history) (values nil 0))
    ((not (nshell.infrastructure.persistence:clear-history-file))
     (values nil 1))
    (t
     (history-kit:history-clear history)
     (values nil 0))))

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
              (multiple-value-bind (filter query invalid timestamps-p)
                  (%history-filter-options args)
                (if (or invalid query)
                    (values (%history-usage) 1)
                    (%history-list history filter timestamps-p)))))
        (%history-list history))))
