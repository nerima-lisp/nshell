(in-package #:nshell.application)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro define-plist-accessors (&rest specs)
    `(progn
       ,@(loop for (name key) in specs
               collect `(defun ,name (spec)
                          (getf spec ,key)))))

  (defmacro define-string-line-builtin (name transform)
    `(defun ,name (context args)
       (declare (ignore context))
       (values (%string-emit-lines args :transform ,transform)
               (if args 0 1)))))

(define-plist-accessors
  (%builtin-string-spec-name :name)
  (%builtin-string-spec-handler :handler)
  (%builtin-string-spec-manipulation-p :manipulation-p)
  (%string-option-spec-name :name)
  (%string-option-spec-short :short)
  (%string-option-spec-long :long)
  (%string-option-spec-kind :kind)
  (%string-option-spec-short-prefix-length :short-prefix-length)
  (%string-option-spec-long-prefix-length :long-prefix-length))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro %string-flag-option-handler ((name remaining) &body clauses)
    `(lambda (,name ,remaining)
       (case ,name
         ,@clauses)
       ,remaining))

  (defmacro %string-integer-option-handler ((name parsed next-remaining) &body clauses)
    (if clauses
        `(lambda (,name ,parsed ,next-remaining)
           (case ,name
             ,@clauses)
           ,next-remaining)
        `(lambda (,name ,parsed ,next-remaining)
           (declare (ignore ,parsed))
           (case ,name)
           ,next-remaining))))

;; Macro that binds the new remaining-args and option-error after parsing.
;; OPTION-ERROR is NIL on success; the caller decides how to handle it.
(defmacro with-string-options ((next-remaining-var option-error-var
                                remaining builtin flag-specs integer-specs
                                on-flag on-integer)
                               &body body)
  "Parse REMAINING with %string-parse-option-stream, binding results as
NEXT-REMAINING-VAR (updated remaining args) and OPTION-ERROR-VAR (NIL or
an error string). BODY runs with both variables in scope."
  `(multiple-value-bind (,next-remaining-var ,option-error-var)
       (%string-parse-option-stream ,remaining ,builtin
                                    ,flag-specs ,integer-specs
                                    ,on-flag ,on-integer)
     ,@body))

(defun %builtin-string-summary (separator &key manipulation-only-p)
  (format nil "string ~a"
          (%string-join
           (mapcar #'%builtin-string-spec-name
                   (%builtin-string-subcommand-specs
                    :manipulation-only-p manipulation-only-p))
           separator)))

(defun %builtin-string-usage (&optional (separator "|"))
  (%builtin-usage "string" (%builtin-string-summary separator)))

(defun %string-character-test (ignore-case)
  (if ignore-case #'char-equal #'char=))

(defun %string-option-spec-matches-p (option spec)
  (let ((short (%string-option-spec-short spec))
        (long (%string-option-spec-long spec)))
    (case (%string-option-spec-kind spec)
      (:prefixed
       (or (string-prefix-p short option)
           (string-prefix-p long option)))
      (:required
       (or (string= option short)
           (string= option long)
           (string-prefix-p short option)
           (string-prefix-p long option)))
      (t
       (or (string= option short)
           (string= option long))))))

(defun %string-find-option-spec (option specs)
  (find-if (lambda (spec)
             (%string-option-spec-matches-p option spec))
           specs))

(defun %string-parse-integer-option (option value)
  (handler-case
      (values (parse-integer value :junk-allowed nil) nil)
    (error ()
      (values nil (format nil "string: invalid integer for ~a: ~a~%" option value)))))

(defun %string-resolve-attached-value (option short long short-prefix-length long-prefix-length)
  "Return the integer text attached inline to OPTION (e.g. -N5 or --width=5), or NIL."
  (cond
    ((and short-prefix-length
          (string-prefix-p short option)
          (> (length option) short-prefix-length))
     (subseq option short-prefix-length))
    ((and long-prefix-length
          (string-prefix-p long option)
          (>= (length option) long-prefix-length)
          (char= (char option (1- long-prefix-length)) #\=))
     (subseq option long-prefix-length))))

(defun %string-parse-integer-option-spec (option remaining spec)
  (let* ((short  (%string-option-spec-short spec))
         (long   (%string-option-spec-long spec))
         (attached-value (%string-resolve-attached-value
                          option short long
                          (%string-option-spec-short-prefix-length spec)
                          (%string-option-spec-long-prefix-length spec)))
         (separate-value (and (null attached-value) (second remaining))))
    (labels ((parse-value (value next-remaining)
               (multiple-value-bind (parsed error)
                   (%string-parse-integer-option option value)
                 (if error
                     (values nil remaining error)
                     (values parsed next-remaining nil)))))
      (cond
        (attached-value  (parse-value attached-value (rest remaining)))
        (separate-value  (parse-value separate-value (cddr remaining)))
        (t (values nil remaining
                   (%required-argument-error "string" option "an integer")))))))

(defun %string-option-argument-p (option)
  (%builtin-option-like-p option))

(defun %string-parse-option-stream (remaining builtin flag-specs integer-specs on-flag on-integer)
  (labels ((advance-flag (spec)
             (funcall on-flag (%string-option-spec-name spec) remaining)
             (rest remaining))
           (advance-integer (option spec)
             (multiple-value-bind (parsed next-remaining error)
                 (%string-parse-integer-option-spec option remaining spec)
               (when error
                 (return-from %string-parse-option-stream
                   (values remaining error)))
               (funcall on-integer (%string-option-spec-name spec)
                        parsed next-remaining)))
           (unknown-option (option)
             (return-from %string-parse-option-stream
               (values remaining
                       (format nil "~a: unknown option ~a~%"
                               builtin option)))))
    (loop while remaining
          for option = (first remaining)
          do (cond
               ((string= option "--")
                (setf remaining (rest remaining))
                (return))
               ((not (%string-option-argument-p option))
                (return))
               (t
                (let ((flag-spec (%string-find-option-spec option flag-specs))
                      (integer-spec (%string-find-option-spec option integer-specs)))
                  (cond
                    (flag-spec
                     (setf remaining (advance-flag flag-spec)))
                    (integer-spec
                     (setf remaining (advance-integer option integer-spec)))
                    (t
                     (unknown-option option))))))))
  (values remaining nil))

(defun %string-empty-p (string)
  (zerop (length string)))

(defun %string-emit-lines (lines &key (transform #'identity))
  (with-output-to-string (out)
    (dolist (line lines)
      (write-string (funcall transform line) out)
      (write-char #\Newline out))))

(defun %string-collect-texts (texts quiet-p collector)
  (let ((matched-p nil))
    (values
     (with-output-to-string (out)
       (dolist (text texts)
         (multiple-value-bind (line text-matched-p)
             (funcall collector text)
           (when text-matched-p
             (setf matched-p t)
             (unless quiet-p
               (write-string line out)
               (write-char #\Newline out))))))
     (if matched-p 0 1))))

(defun %string-wildcard-match-p (pattern string &key ignore-case)
  (let ((test (%string-character-test ignore-case))
        (pattern-length (length pattern))
        (string-length (length string))
        (memo (make-hash-table :test #'equal)))
    (labels ((match (pattern-index string-index)
               (let ((key (cons pattern-index string-index)))
                 (multiple-value-bind (cached-value present-p)
                     (gethash key memo)
                   (if present-p
                       cached-value
                       (setf (gethash key memo)
                             (cond
                               ((= pattern-index pattern-length)
                                (= string-index string-length))
                               ((char= (char pattern pattern-index) #\*)
                                (or (match (1+ pattern-index) string-index)
                                    (and (< string-index string-length)
                                         (match pattern-index (1+ string-index)))))
                               ((char= (char pattern pattern-index) #\?)
                                (and (< string-index string-length)
                                     (match (1+ pattern-index) (1+ string-index))))
                               (t
                                (and (< string-index string-length)
                                     (funcall test (char pattern pattern-index)
                                              (char string string-index))
                                     (match (1+ pattern-index)
                                            (1+ string-index)))))))))))
      (match 0 0))))

(defun %string-replace-text (text pattern replacement &key all ignore-case)
  (let ((test (%string-character-test ignore-case))
        (pattern-length (length pattern)))
    (if (%string-empty-p pattern)
        (values text nil)
        (if all
            (let ((matched-p nil))
              (values
               (with-output-to-string (out)
                 (loop with start = 0
                       for pos = (search pattern text :start2 start :test test)
                       while pos
                       do (setf matched-p t)
                          (write-string (subseq text start pos) out)
                          (write-string replacement out)
                          (setf start (+ pos pattern-length))
                       finally (write-string (subseq text start) out)))
               matched-p))
            (let ((pos (search pattern text :start2 0 :test test)))
              (if pos
                  (values (concatenate 'string
                                       (subseq text 0 pos)
                                       replacement
                                       (subseq text (+ pos pattern-length)))
                          t)
                  (values text nil)))))))

(defun %string-trim-trailing-newlines (string)
  (let ((end (length string)))
    (loop while (and (> end 0)
                     (char= (char string (1- end)) #\Newline))
          do (decf end))
    (subseq string 0 end)))
