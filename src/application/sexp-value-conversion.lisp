(in-package #:nshell.application)

(defun argv-scalar-string (value &key source-span)
  (cond
    ((stringp value) value)
    ((characterp value) (string value))
    ((numberp value) (princ-to-string value))
    ((and (symbolp value) (not (null value))) (symbol-name value))
    ((or (null value) (consp value))
     (error 'command-argument-type-error
            :value value
            :source-span source-span))
    (t
     (error 'type-error
            :datum value
            :expected-type '(or string character number
                                (and symbol (not (eql nil))))))))

(in-package #:nshell.user)

(progn
  (defun %proper-list-p (value)
    (and (listp value)
         (handler-case
             (integerp (list-length value))
           (type-error () nil))))

  (defun %ensure-proper-list (value)
    (unless (%proper-list-p value)
      (error 'type-error :datum value
             :expected-type '(satisfies %proper-list-p)))
    value)

  (defun %malformed-cause (reason)
    (make-condition 'simple-error
                    :format-control "~A"
                    :format-arguments (list reason)))

  (defun %conversion-failure (operation input reason)
    (error 'nshell.application::value-conversion-error
           :operation operation
           :input input
           :cause (if (typep reason 'condition)
                      reason
                      (%malformed-cause reason))))

  (defun %split-literal (text separator)
    (if (zerop (length separator))
        (if (zerop (length text))
            (list "")
            (loop for character across text
                  collect (string character)))
        (let ((parts nil)
              (position 0))
          (loop
            for match = (search separator text :start2 position)
            do (push (subseq text position (or match (length text))) parts)
               (if match
                   (setf position (+ match (length separator)))
                   (return (nreverse parts)))))))

  (defun %join-literal (strings separator)
    (with-output-to-string (output)
      (loop for tail on strings
            do (write-string (car tail) output)
            when (cdr tail)
              do (write-string separator output))))

  (defun %json-object-alist-p (value)
    (and (consp value)
         (%proper-list-p value)
         (every (lambda (entry)
                  (and (consp entry)
                       (stringp (car entry))))
                value)))

  ;; NIL is the public empty-list representation, so JSON empty containers cannot be distinguished.
  (defun %json-value-for-output (value)
    (cond
      ((or (json-kit:json-null-p value)
           (json-kit:json-false-p value))
       value)
      ((eq value t) t)
      ((stringp value) value)
      ((and (numberp value) (realp value)) value)
      ((numberp value)
       (error 'type-error :datum value :expected-type 'real))
      ((%json-object-alist-p value)
       (json-kit:make-json-object
        (mapcar (lambda (entry)
                  (cons (car entry)
                        (%json-value-for-output (cdr entry))))
                value)))
      ((%proper-list-p value)
       (mapcar #'%json-value-for-output value))
      (t
       (error 'type-error
              :datum value
              :expected-type '(or null string real
                                  (satisfies %proper-list-p))))))

  (defun %compile-user-regex (pattern operation)
    (handler-case
        (cl-regex-kit:compile-regex pattern)
      (cl-regex-kit:regex-syntax-error (cause)
        (%conversion-failure operation pattern cause))))

  (defun %normalize-crlf (text)
    (with-output-to-string (output)
      (loop for index from 0 below (length text)
            for character = (char text index)
            do (if (and (char= character #\Return)
                        (< (1+ index) (length text))
                        (char= (char text (1+ index)) #\Newline))
                   (progn
                     (write-char #\Newline output)
                     (incf index))
                   (write-char character output)))))

  (defun %replace-literal (text needle replacement all-p)
    (if (zerop (length needle))
        (if all-p
            (with-output-to-string (output)
              (write-string replacement output)
              (loop for character across text
                    do (write-char character output)
                       (write-string replacement output)))
            (concatenate 'string replacement text))
        (if all-p
            (with-output-to-string (output)
              (loop with position = 0
                    for match = (search needle text :start2 position)
                    while match
                    do (write-string (subseq text position match) output)
                       (write-string replacement output)
                       (setf position (+ match (length needle)))
                    finally
                       (write-string (subseq text position) output)))
            (let ((match (search needle text)))
              (if match
                  (concatenate 'string
                               (subseq text 0 match)
                               replacement
                               (subseq text (+ match (length needle))))
                  text))))))

(defun to-json (value)
  (json-kit:stringify (%json-value-for-output value)))

(defun from-json (text)
  (check-type text string)
  (handler-case
      (json-kit:parse text :object-type :alist :array-type :list)
    (json-kit:json-parse-error (cause)
      (%conversion-failure :from-json text cause))))

(defun to-tsv (rows)
  (%ensure-proper-list rows)
  (let ((tab (string #\Tab))
        (newline (string #\Newline))
        (records nil))
    (dolist (row rows)
      (%ensure-proper-list row)
      (when (null row)
        (%conversion-failure :to-tsv rows
                             "TSV rows must contain at least one field"))
      (dolist (field row)
        (check-type field string)
        (when (or (find #\Tab field)
                  (find #\Newline field)
                  (find #\Return field))
          (%conversion-failure :to-tsv rows
                               "TSV fields cannot contain tabs or line breaks")))
      (push (%join-literal row tab) records))
    (with-output-to-string (output)
      (dolist (record (nreverse records))
        (write-string record output)
        (write-string newline output)))))

(defun from-tsv (text)
  (check-type text string)
  (when (find #\Return text)
    (%conversion-failure :from-tsv text "TSV must use LF line endings"))
  (cond
    ((zerop (length text)) nil)
    ((not (char= (char text (1- (length text))) #\Newline))
     (%conversion-failure :from-tsv text "TSV records must end with LF"))
    (t
     (let ((records (%split-literal
                     (subseq text 0 (1- (length text)))
                     (string #\Newline))))
       (mapcar (lambda (record)
                 (%split-literal record (string #\Tab)))
               records)))))

(defun to-lines (text)
  (check-type text string)
  (let ((normalized (%normalize-crlf text)))
    (when (find #\Return normalized)
      (%conversion-failure :to-lines text
                           "Line text contains a bare carriage return"))
    (if (zerop (length normalized))
        nil
        (let ((lines (%split-literal normalized (string #\Newline))))
          (if (char= (char normalized (1- (length normalized))) #\Newline)
              (butlast lines)
              lines)))))

(defun from-lines (lines)
  (%ensure-proper-list lines)
  (with-output-to-string (output)
    (dolist (line lines)
      (check-type line string)
      (when (or (find #\Newline line) (find #\Return line))
        (%conversion-failure :from-lines lines
                             "A line value cannot contain a line break"))
      (write-string line output)
      (write-char #\Newline output))))

(defun regex-match-p (pattern text)
  (check-type pattern string)
  (check-type text string)
  (let ((regex (%compile-user-regex pattern :regex-match-p)))
    (not (null (cl-regex-kit:scan regex text)))))

(defun regex-find (pattern text &key (start 0))
  (check-type pattern string)
  (check-type text string)
  (check-type start (integer 0 *))
  (let* ((regex (%compile-user-regex pattern :regex-find))
         (match (when (<= start (length text))
                  (cl-regex-kit:scan regex text :start start))))
    (if match
        (values (cl-regex-kit:match-string match text)
                (cl-regex-kit:match-start match)
                (cl-regex-kit:match-end match)
                (coerce (subseq (cl-regex-kit:match-captures match text) 1)
                        'list))
        (values nil nil nil nil))))

(defun regex-replace (pattern replacement text &key (all-p nil))
  (check-type pattern string)
  (check-type replacement string)
  (check-type text string)
  (check-type all-p boolean)
  (let* ((regex (%compile-user-regex pattern :regex-replace))
         (literal-replacement
           (lambda (match input)
             (declare (ignore match input))
             replacement)))
    (if all-p
        (cl-regex-kit:replace-all regex text literal-replacement)
        (cl-regex-kit:replace-first regex text literal-replacement))))

(defun split-string (text separator &key (omit-empty-p nil))
  (check-type text string)
  (check-type separator string)
  (check-type omit-empty-p boolean)
  (let ((parts (%split-literal text separator)))
    (if omit-empty-p
        (remove "" parts :test #'string=)
        parts)))

(defun join-strings (strings separator)
  (%ensure-proper-list strings)
  (check-type separator string)
  (dolist (string strings)
    (check-type string string))
  (%join-literal strings separator))

(defun replace-string (text needle replacement &key (all-p nil))
  (check-type text string)
  (check-type needle string)
  (check-type replacement string)
  (check-type all-p boolean)
  (%replace-literal text needle replacement all-p))
