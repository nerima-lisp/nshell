(in-package #:nshell.domain.expansion)


(defun %append-list-reference-fields (prefixes fields)
  (let ((alternatives (or fields (list ""))))
    (loop for prefix in prefixes
          append (loop for field in alternatives
                       collect (concatenate 'string prefix field)))))

(defun %append-expanded-literal-fragment (prefixes fragment env)
  (if (zerop (length fragment))
      prefixes
      (let ((expanded (expand-variables fragment env)))
        (loop for prefix in prefixes
              collect (concatenate 'string prefix expanded)))))

(defstruct (unquoted-field-fragment
            (:constructor %make-unquoted-field-fragment (kind value)))
  (kind nil :read-only t)
  (value nil :read-only t))

(defun %literal-unquoted-field-fragment (text)
  (%make-unquoted-field-fragment :literal text))

(defun %list-reference-unquoted-field-fragment (fields)
  (%make-unquoted-field-fragment :list-reference fields))

(defun %apply-unquoted-field-fragment (prefixes fragment env)
  (case (unquoted-field-fragment-kind fragment)
    (:literal
     (%append-expanded-literal-fragment
      prefixes
      (unquoted-field-fragment-value fragment)
      env))
    (:list-reference
     (%append-list-reference-fields
      prefixes
      (unquoted-field-fragment-value fragment)))
    (t (error "Invalid unquoted field fragment kind ~S"
              (unquoted-field-fragment-kind fragment)))))

(defun %list-reference-fragment-at (input start len env)
  "Return a field-producing list reference fragment at START, plus the next index."
  (when (char= (char input start) #\$)
    (multiple-value-bind (fields next list-reference-p)
        (%variable-reference-at input start len env)
      (when list-reference-p
        (values (%list-reference-unquoted-field-fragment fields) next)))))

(defun %expand-list-references (input env)
  "Expand fish-style list references as field-producing fragments.
This is used only by unquoted expansion. The scalar expand-variables API still
joins list values with spaces, while unquoted list references become separate
fields. Only literal fragments from INPUT are variable-expanded; inserted list
values stay literal."
  (let ((results (list ""))
        (recognized-p nil)
        (literal (make-string-output-stream)))
    (labels ((flush-literal ()
               (let ((fragment (get-output-stream-string literal)))
                 (setf results
                       (%apply-unquoted-field-fragment
                        results
                        (%literal-unquoted-field-fragment fragment)
                        env)))))
      (loop with len = (length input)
            for i from 0 below len
            for ch = (char input i)
            do (if (char= ch #\$)
                   (multiple-value-bind (fragment next)
                       (%list-reference-fragment-at input i len env)
                     (if fragment
                         (progn
                           (flush-literal)
                           (setf results
                                 (%apply-unquoted-field-fragment
                                  results fragment env))
                           (setf recognized-p t)
                           (setf i (1- next)))
                         (write-char ch literal)))
                   (write-char ch literal)))
      (flush-literal))
    (if recognized-p
        results
        (list (expand-variables input env)))))

(defun expand-all (input env)
  "Apply brace, tilde, arithmetic, variable, and glob expansion to INPUT,
returning the (possibly multiple) resulting fields."
  (loop for braced in (expand-braces input)
        append (loop for argv-expanded in
                     (%expand-list-references
                      (expand-arithmetic (expand-tilde braced env) env) env)
                     append (%expand-glob-with-prefix argv-expanded))))

(defmacro expand-by-quote-style (style unquoted-form single-form double-form)
  "Dispatch on STYLE and evaluate the matching form."
  (let ((style-var (gensym "STYLE")))
    `(let ((,style-var ,style))
       (case ,style-var
         ((nil) ,unquoted-form)
         (:single ,single-form)
         (:double ,double-form)
         (t (error "Invalid quote style ~S" ,style-var))))))

(defun expand-double-quoted (input env)
  "Expand INPUT as the contents of a double-quoted string.
Arithmetic ($((...))) and variables are expanded, but tilde, globbing, and
word-splitting are suppressed (POSIX semantics), so the result is always a
single string. Command substitution is applied by the caller before this."
  (expand-variables (expand-arithmetic input env) env))

(defstruct (whitespace-field-boundary
            (:constructor %make-whitespace-field-boundary (start end)))
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t))

(defun whitespace-field-boundary-text (boundary text)
  (subseq text
          (whitespace-field-boundary-start boundary)
          (whitespace-field-boundary-end boundary)))

(defstruct (whitespace-field-scanner
            (:constructor %make-whitespace-field-scanner (text)))
  (text "" :type string :read-only t)
  (boundaries nil :type list)
  (start nil :type (or null integer)))

(defun whitespace-field-separator-p (char)
  (member char '(#\Space #\Tab #\Newline) :test #'char=))

(defun whitespace-field-scanner-start-field (scanner index)
  (unless (whitespace-field-scanner-start scanner)
    (setf (whitespace-field-scanner-start scanner) index))
  scanner)

(defun whitespace-field-scanner-finish-field (scanner end)
  (let ((start (whitespace-field-scanner-start scanner)))
    (when start
      (push (%make-whitespace-field-boundary start end)
            (whitespace-field-scanner-boundaries scanner))
      (setf (whitespace-field-scanner-start scanner) nil)))
  scanner)

(defun whitespace-field-scanner-accept (scanner index char)
  (if (whitespace-field-separator-p char)
      (whitespace-field-scanner-finish-field scanner index)
      (whitespace-field-scanner-start-field scanner index))
  scanner)

(defun whitespace-field-scanner-field-boundaries (scanner)
  (whitespace-field-scanner-finish-field
   scanner
   (length (whitespace-field-scanner-text scanner)))
  (reverse (whitespace-field-scanner-boundaries scanner)))

(defun whitespace-field-scanner-result (scanner)
  (let ((text (whitespace-field-scanner-text scanner)))
    (loop for boundary in (whitespace-field-scanner-field-boundaries scanner)
          collect (whitespace-field-boundary-text boundary text))))

(defun %split-whitespace-fields (text)
  (let ((scanner (%make-whitespace-field-scanner text)))
    (loop for index from 0 below (length text)
          do (whitespace-field-scanner-accept scanner index (char text index)))
    (whitespace-field-scanner-result scanner)))

(defun %command-name-field-splitting-required-p (text)
  (find #\$ text :test #'char=))

(defun %command-name-unquoted-fields (text env)
  (let ((fields (expand-all text env)))
    (if (%command-name-field-splitting-required-p text)
        (loop for field in fields
              append (%split-whitespace-fields field))
        fields)))

(defun expand-command-name-fields-by-quote-style (text style env)
  "Expand a command name according to STYLE and shell field-splitting rules."
  (expand-by-quote-style
   style
   (%command-name-unquoted-fields text env)
   (list text)
   (list (expand-double-quoted text env))))

(defstruct (command-name-candidate
            (:constructor %make-command-name-candidate (text fields)))
  (text "" :type string :read-only t)
  (fields nil :type list :read-only t))

(defun command-name-candidate-non-empty-fields (candidate)
  (remove "" (command-name-candidate-fields candidate) :test #'string=))

(defun %command-name-candidate-error (candidate field-count)
  (format nil "nshell: ~a: command name expansion produced ~d fields~%"
          (command-name-candidate-text candidate)
          field-count))

(defun %resolve-command-name-candidate (candidate)
  (let ((fields (command-name-candidate-non-empty-fields candidate)))
    (if (= 1 (length fields))
        (values (first fields) nil)
        (values nil
                (%command-name-candidate-error candidate (length fields))))))

(defun %single-command-name-or-error (text fields)
  "Return one command name from FIELDS or the canonical ambiguity error."
  (%resolve-command-name-candidate
   (%make-command-name-candidate text fields)))

(defun expand-command-name-by-quote-style (text style env)
  "Expand a command name and return either one field or an ambiguity error."
  (%single-command-name-or-error
   text
   (expand-command-name-fields-by-quote-style text style env)))
