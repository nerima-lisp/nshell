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
                       (%append-expanded-literal-fragment results fragment env)))))
      (loop with len = (length input)
            for i from 0 below len
            for ch = (char input i)
            do (if (char= ch #\$)
                   (multiple-value-bind (fields next list-reference-p)
                       (%variable-reference-at input i len env)
                     (if list-reference-p
                         (progn
                           (flush-literal)
                           (setf results (%append-list-reference-fields results fields))
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

(defun %split-whitespace-fields (text)
  (let ((fields '())
        (start nil))
    (labels ((finish (end)
               (when start
                 (push (subseq text start end) fields)
                 (setf start nil))))
      (loop for index from 0 below (length text)
            for ch = (char text index)
            if (member ch '(#\Space #\Tab #\Newline) :test #'char=)
              do (finish index)
            else
              do (unless start
                   (setf start index)))
      (finish (length text)))
    (nreverse fields)))

(defun expand-command-name-fields-by-quote-style (text style env)
  "Expand a command name according to STYLE and shell field-splitting rules."
  (expand-by-quote-style
   style
   (let ((fields (expand-all text env)))
     (if (find #\$ text :test #'char=)
         (loop for field in fields
               append (%split-whitespace-fields field))
         fields))
   (list text)
   (list (expand-double-quoted text env))))
