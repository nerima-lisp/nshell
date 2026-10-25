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
  (let ((record (nshell.domain.abbreviation:abbreviation-p value)))
    (format out "abbr -a")
    (when (and record
               (eq :anywhere
                   (nshell.domain.abbreviation:abbreviation-position value)))
      (format out " --position anywhere"))
    (when (and record (nshell.domain.abbreviation:abbreviation-regex value))
      (format out " --regex ~a"
              (nshell.domain.abbreviation:abbreviation-regex value)))
    (when (and record
               (nshell.domain.abbreviation:abbreviation-set-cursor-marker value))
      (format out " --set-cursor=~a"
              (nshell.domain.abbreviation:abbreviation-set-cursor-marker value)))
    (when (and record
               (nshell.domain.abbreviation:abbreviation-function-name value))
      (format out " --function ~a"
              (nshell.domain.abbreviation:abbreviation-function-name value)))
    (format out " ~a" key)
    (unless (and record
                 (nshell.domain.abbreviation:abbreviation-function-name value))
      (format out " ~a" (%abbreviation-expansion value)))
    (terpri out)))

(%define-name-table-formatter %format-abbreviation-names (key value)
  (declare (ignore value))
  (format out "~a~%" key))

(defun %abbr-usage ()
  (%builtin-usage
   "abbr"
   "abbr -a [-p command|anywhere] [--regex PATTERN] [--function FUNCTION | EXPANSION...] [--set-cursor[=MARKER]] NAME"))

(progn
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
                   "abbr" "--position" "command or anywhere"))))))

(defun %abbr-parse-add-arguments (rest-args)
  (let ((position :command)
        (regex nil)
        (function-name nil)
        (set-cursor-marker nil)
        (remaining rest-args))
    (loop while remaining
          for option = (first remaining)
          do (cond
               ((%builtin-option-p option '("-p" "--position"))
                (multiple-value-bind (parsed next-remaining error)
                    (%abbr-ensure-position-argument remaining)
                  (when error
                    (return-from %abbr-parse-add-arguments
                      (values nil nil nil nil nil nil error)))
                  (setf position parsed
                        remaining next-remaining)))
               ((%builtin-option-p option '("-r" "--regex"))
                (unless (second remaining)
                  (return-from %abbr-parse-add-arguments
                    (values nil nil nil nil nil nil
                            (%required-argument-error
                             "abbr" "--regex" "a pattern"))))
                (setf regex (second remaining)
                      remaining (cddr remaining))
                (handler-case
                    (cl-regex-kit:compile-regex regex)
                  (cl-regex-kit:regex-syntax-error (condition)
                    (return-from %abbr-parse-add-arguments
                      (values nil nil nil nil nil nil
                              (format nil "abbr: invalid regular expression: ~a~%"
                                      condition))))))
               ((%builtin-option-p option '("-f" "--function"))
                (unless (second remaining)
                  (return-from %abbr-parse-add-arguments
                    (values nil nil nil nil nil nil
                            (%required-argument-error
                             "abbr" "--function" "a function name"))))
                (setf function-name (second remaining)
                      remaining (cddr remaining)))
               ((string= option "--set-cursor")
                (setf set-cursor-marker "%"
                      remaining (rest remaining)))
               ((string-prefix-p "--set-cursor=" option)
                (let ((marker (subseq option (length "--set-cursor="))))
                  (when (string= marker "")
                    (return-from %abbr-parse-add-arguments
                      (values nil nil nil nil nil nil
                              (%abbr-usage))))
                  (setf set-cursor-marker marker
                        remaining (rest remaining))))
               ((string= option "--")
                (setf remaining (rest remaining))
                (return))
               (t (return))))
    (let ((name (first remaining))
          (expansion-args (rest remaining)))
      (cond
        ((null name)
         (values nil nil nil nil nil nil (%abbr-usage)))
        ((and function-name expansion-args)
         (values nil nil nil nil nil nil (%abbr-usage)))
        ((and (null function-name) (null expansion-args))
         (values nil nil nil nil nil nil (%abbr-usage)))
        (t
         (values name
                 (if function-name "" (%string-join expansion-args " "))
                 position
                 regex
                 function-name
                 set-cursor-marker
                 nil))))))

(progn
  (defvar *abbr-registration-sequence* 0)

  (defun %abbr-value
      (expansion position regex function-name set-cursor-marker order)
    (nshell.domain.abbreviation:make-abbreviation
     :expansion expansion
     :position position
     :regex regex
     :function-name function-name
     :set-cursor-marker set-cursor-marker
     :order order)))

(defun %abbr-store
    (table name expansion position regex function-name set-cursor-marker)
  (setf (gethash name table)
        (%abbr-value expansion position regex function-name set-cursor-marker
                     (incf *abbr-registration-sequence*)))
  (values nil 0))

(defun %builtin-abbr (context args)
  (let ((table (shell-context-abbreviation-table context)))
    (%table-builtin-case args
      (:empty
       (values (%format-abbreviations table) 0))
      (:option ("-a" "--add")
       (multiple-value-bind (name expansion position regex function-name
                            set-cursor-marker error)
           (%abbr-parse-add-arguments (rest args))
         (if error
             (values error 2)
             (%abbr-store table name expansion position regex function-name
                          set-cursor-marker))))
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
