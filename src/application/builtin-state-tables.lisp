(in-package #:nshell.application)

(defun %table-erase-names (table names &key on-erase)
  (dolist (name names)
    (remhash name table)
    (when on-erase
      (funcall on-erase name)))
  (values nil 0))

(defun %table-query-status (table names)
  (if (and names
           (every (lambda (name)
                    (nth-value 1 (gethash name table)))
                  names))
      0
      1))

(defmacro %table-builtin-case (args &body clauses)
  (let ((args-variable (gensym "ARGS-")))
    `(let ((,args-variable ,args))
       (cond
         ,@(mapcar (lambda (clause)
                     (destructuring-bind (kind &rest rest) clause
                       (ecase kind
                         (:empty
                          `((null ,args-variable)
                            ,@rest))
                         (:option
                          (destructuring-bind (names &body body) rest
                            `((%builtin-option-p (first ,args-variable) ',names)
                              ,@body)))
                         (:default
                          `(t
                            ,@rest)))))
                   clauses)))))

(defun %format-name-table (table emitter &optional names)
  (with-output-to-string (out)
    (labels ((emit (name)
               (multiple-value-bind (value present-p)
                   (gethash name table)
                 (when present-p
                   (funcall emitter out name value)))))
      (if names
          (dolist (name names)
            (emit name))
          (maphash (lambda (name value)
                     (declare (ignore value))
                     (emit name))
                   table)))))

(defmacro %define-name-table-formatter (name (key value) &body body)
  `(defun ,name (table &optional names)
     (%format-name-table
      table
      (lambda (out ,key ,value)
        ,@body)
      names)))

(defun %split-alias-assignment (arg)
  (let ((position (position #\= arg)))
    (when (and position (plusp position))
      (values (subseq arg 0 position)
              (subseq arg (1+ position))))))

(defun %alias-usage ()
  (%builtin-usage "alias" "alias name expansion..."))

(defun %alias-store (table name expansion)
  (if (or (string= name "")
          (string= expansion ""))
      (%alias-usage)
      (progn
        (setf (gethash name table) expansion)
        (values nil 0))))

(defun %alias-query-or-list (table args)
  (values (%format-aliases table args)
          (%table-query-status table args)))

(defun %alias-inline-expansion (name inline-value args)
  (%string-join
   (if name
       (cons inline-value (rest args))
       (rest args))
   " "))

(defun %alias-store-assignment (table args)
  (multiple-value-bind (name value) (%split-alias-assignment (first args))
    (if name
        (%alias-store table name value)
        (%alias-query-or-list table args))))

(defun %builtin-alias (context args)
  (let ((table (shell-context-alias-table context)))
    (%table-builtin-case args
      (:empty
       (values (%format-aliases table) 0))
      (:option ("-e" "--erase")
       (%with-required-argument (%builtin-alias args "alias" "-e" "a name" 2)
         (%table-erase-names table (rest args))))
      (:option ("-q" "--query")
       (values nil (%table-query-status table (rest args))))
      (:default
       (if (rest args)
           (multiple-value-bind (name inline-value) (%split-alias-assignment (first args))
             (%alias-store table
                           (or name (first args))
                           (%alias-inline-expansion name inline-value args)))
           (%alias-store-assignment table args))))))

(%define-name-table-formatter %format-aliases (name value)
  (format out "alias ~a=~a~%" name value))

(defun %abbreviation-expansion (value)
  (if (nshell.domain.abbreviation:abbreviation-p value)
      (nshell.domain.abbreviation:abbreviation-expansion value)
      value))

(defun %abbreviation-position (value)
  (when (nshell.domain.abbreviation:abbreviation-p value)
    (nshell.domain.abbreviation:abbreviation-position value)))

(%define-name-table-formatter %format-abbreviations (key value)
  (let ((expansion (%abbreviation-expansion value))
        (position (%abbreviation-position value)))
    (if position
        (format out "abbr -a --position ~a ~a ~a~%"
                (string-downcase (symbol-name position))
                key
                expansion)
        (format out "abbr -a ~a ~a~%" key expansion))))

(%define-name-table-formatter %format-abbreviation-names (key value)
  (declare (ignore value))
  (format out "~a~%" key))

(defun %abbr-usage ()
  (%builtin-usage
   "abbr"
   "abbr [-a [-p command|anywhere] name expansion...] [-e name...] [-q name...] [-l] [-s]"))

(defun %abbr-parse-position (value)
  (cdr (assoc value +abbr-position-specs+ :test #'string=)))

(defun %abbr-ensure-position-argument (remaining)
  (let ((value (second remaining)))
    (if value
        (let ((parsed (%abbr-parse-position value)))
          (if parsed
              (values parsed (cddr remaining) nil)
              (values nil nil
                      (%required-argument-error
                       "abbr" "--position" "command or anywhere"))))
        (values nil nil
                (%required-argument-error
                 "abbr" "--position" "command or anywhere")))))

(defun %abbr-parse-add-arguments (rest-args)
  (labels ((parse (remaining position)
             (cond
               ((and remaining
                     (%builtin-option-p (first remaining)
                                        '("-p" "--position")))
                (multiple-value-bind (parsed next-remaining error)
                    (%abbr-ensure-position-argument remaining)
                  (if error
                      (values nil nil nil error)
                      (parse next-remaining parsed))))
               ((< (length remaining) 2)
                (values nil nil nil (%abbr-usage)))
               (t
                (values (first remaining)
                        (%string-join (rest remaining) " ")
                        position
                        nil)))))
    (parse rest-args nil)))

(defun %abbr-value (expansion position)
  (if position
      (nshell.domain.abbreviation:make-abbreviation
       :expansion expansion
       :position position)
      expansion))

(defun %abbr-store (table name expansion position)
  (setf (gethash name table) (%abbr-value expansion position))
  (values nil 0))

(defun %builtin-abbr (context args)
  (let ((table (shell-context-abbreviation-table context)))
    (%table-builtin-case args
      (:empty
       (values (%format-abbreviations table) 0))
      (:option ("-a" "--add")
       (multiple-value-bind (name expansion position error)
           (%abbr-parse-add-arguments (rest args))
         (if error
             (values error 2)
             (%abbr-store table name expansion position))))
      (:option ("-e" "--erase")
       (%with-required-argument (%builtin-abbr args "abbr" "-e" "a name" 2)
         (%table-erase-names table (rest args))))
      (:option ("-q" "--query")
       (values nil (%table-query-status table (rest args))))
      (:option ("-l" "--list")
       (values (%format-abbreviation-names table) 0))
      (:option ("-s" "--show")
       (values (%format-abbreviations table) 0))
      (:default
       (values (%abbr-usage) 1)))))
