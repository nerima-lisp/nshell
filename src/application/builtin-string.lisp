(in-package #:nshell.application)

(defun %string-collect-lines (texts preserve-newlines-p allow-empty-p)
  "Filter TEXTS into a flat ordered list of non-empty lines.
Trailing newlines are stripped unless PRESERVE-NEWLINES-P.
Blank lines are dropped unless ALLOW-EMPTY-P or PRESERVE-NEWLINES-P."
  (let ((has-non-empty nil)
        (lines nil))
    (dolist (text texts)
      (dolist (line
          (%string-lines
            (if preserve-newlines-p text
              (%string-trim-trailing-newlines text))))
        (unless (and (not preserve-newlines-p) (not allow-empty-p) (%string-empty-p line))
          (unless (%string-empty-p line)
            (setf has-non-empty t))
          (push line lines))))
    (values (nreverse lines) has-non-empty)))

(define-builtin %builtin-string-collect (context args) ()
  (let ((allow-empty-p nil)
        (preserve-newlines-p nil)
        (remaining args))
    (with-string-options
      (next-remaining
        error
        remaining
        "string"
        +string-collect-flag-option-specs+
        nil
        (%string-flag-option-handler
          (name remaining)
          (allow-empty
            (setf allow-empty-p t))
          (no-newline
            (setf preserve-newlines-p t)))
        (%string-integer-option-handler (name parsed next-remaining)))
      (when error
        (return-from %builtin-string-collect (values error 1)))
      (setf remaining next-remaining))
    (multiple-value-bind (lines has-non-empty) (%string-collect-lines remaining preserve-newlines-p allow-empty-p)
      (values
        (%string-emit-lines lines)
        (if has-non-empty 0
          1)))))

(define-string-line-builtin
  %builtin-string-length
  (lambda (text)
    (princ-to-string (length text))))

(define-string-line-builtin %builtin-string-lower #'string-downcase)

(define-string-line-builtin %builtin-string-upper #'string-upcase)

(defun %string-no-op-flags (remaining builtin)
  "Parse REMAINING for leading options, rejecting all of them: for
subcommands that define no flags of their own."
  (%string-parse-option-stream
    remaining builtin nil nil
    (%string-flag-option-handler (name remaining))
    (%string-integer-option-handler (name parsed next-remaining))))

(define-builtin %builtin-string-join (context args) ()
  (multiple-value-bind (remaining error) (%string-no-op-flags args "string")
    (cond
      (error (values error 1))
      ((rest remaining) (values (format nil "~a~%" (%string-join (rest remaining) (first remaining))) 0))
      (t (%builtin-string-usage)))))

(defun %string-split-full (separator string)
  (if (%string-empty-p separator) (map 'list #'string string)
    (let ((start 0)
          (parts nil)
          (separator-length (length separator)))
      (loop for pos = (search separator string :start2 start)
            do (push (subseq string start pos) parts)
            while pos
            do (setf start (+ pos separator-length)))
      (nreverse parts))))

(defun %string-collapse-split-parts (parts max-splits from-right-p separator)
  "Merge the pieces beyond MAX-SPLITS back together with SEPARATOR, from the
left or the right, so the caller sees at most MAX-SPLITS+1 fields."
  (if (or (null max-splits) (<= (1- (length parts)) max-splits)) parts
    (if from-right-p
        (cons (%string-join (subseq parts 0 (- (length parts) max-splits)) separator)
              (last parts max-splits))
      (append (subseq parts 0 max-splits)
              (list (%string-join (nthcdr max-splits parts) separator))))))

(define-builtin %builtin-string-split (context args) ()
  (let ((max-splits nil)
        (right-p nil))
    (with-string-options
      (remaining
        error
        args
        "string"
        +string-split-flag-option-specs+
        +string-split-integer-option-specs+
        (%string-flag-option-handler
          (name remaining)
          (right
            (setf right-p t)))
        (%string-integer-option-handler
          (name parsed next-remaining)
          (max
            (setf max-splits parsed))))
      (when error
        (return-from %builtin-string-split (values error 1)))
      (if (rest remaining)
          (values
            (%string-emit-lines
              (loop for text in (rest remaining)
                    append (%string-collapse-split-parts
                             (%string-split-full (first remaining) text)
                             max-splits right-p (first remaining))))
            0)
        (%builtin-string-usage)))))

(defun %parse-string-flags (remaining builtin flag-specs)
  (let ((quiet-p nil)
        (all-p nil)
        (ignore-case-p nil)
        (regex-p nil))
    (with-string-options
      (remaining
        error
        remaining
        builtin
        flag-specs
        nil
        (%string-flag-option-handler
          (name remaining)
          (quiet
            (setf quiet-p t))
          (all
            (setf all-p t))
          (ignore-case
            (setf ignore-case-p t))
          (regex
            (setf regex-p t)))
        (%string-integer-option-handler (name parsed next-remaining)))
      (values quiet-p all-p ignore-case-p regex-p remaining error))))

(defun %string-pattern-builtin (args flag-specs required-args regex-error-builtin collector)
  (multiple-value-bind (quiet-p all-p ignore-case-p regex-p remaining error)
      (%parse-string-flags args "string" flag-specs)
    (when error
      (return-from %string-pattern-builtin (values error 1)))
    (when regex-p
      (return-from %string-pattern-builtin
        (values
          (format nil "~a: -r requires regular expressions, which this build does not provide~%"
                  regex-error-builtin)
          2)))
    (if (< (length remaining) required-args) (%builtin-string-usage)
      (funcall collector quiet-p all-p ignore-case-p remaining))))

(define-builtin %builtin-string-replace (context args) ()
  (%string-pattern-builtin
    args
    +string-replace-flag-option-specs+
    3
    "string replace"
    (lambda (quiet-p all-p ignore-case-p remaining)
      (let ((pattern (first remaining))
            (replacement (second remaining))
            (values (cddr remaining)))
        (%string-collect-texts
          values
          quiet-p
          (lambda (text)
            (%string-replace-text
              text
              pattern
              replacement
              :all
              all-p
              :ignore-case
              ignore-case-p)))))))

(define-builtin %builtin-string-match (context args) ()
  (%string-pattern-builtin
    args
    +string-match-flag-option-specs+
    2
    "string match"
    (lambda (quiet-p all-p ignore-case-p remaining)
      (declare (ignore all-p))
      (let ((pattern (first remaining))
            (values (rest remaining)))
        (%string-collect-texts
          values
          quiet-p
          (lambda (text)
            (if (%string-wildcard-match-p pattern text :ignore-case ignore-case-p) (values text t)
              (values nil nil))))))))

(defun %parse-string-sub-options (remaining)
  (let ((start 1)
        (length nil)
        (end nil)
        (quiet-p nil))
    (with-string-options
      (remaining
        error
        remaining
        "string"
        +string-sub-flag-option-specs+
        +string-sub-integer-option-specs+
        (%string-flag-option-handler
          (name remaining)
          (quiet
            (setf quiet-p t)))
        (%string-integer-option-handler
          (name parsed next-remaining)
          (start
            (setf start parsed))
          (length
            (setf length parsed))
          (end
            (setf end parsed))))
      (values start length end quiet-p remaining error))))

(defun %string-sub-normalize-start (start length)
  (if (minusp start) (+ length start 1)
    start))

(defun %string-sub-normalize-end (end length)
  (if (minusp end) (+ length end)
    end))

(defun %string-slice (text start &key length end)
  (let* ((text-length (length text))
         (start-index (max 0 (1- (%string-sub-normalize-start start text-length))))
         (end-position
        (cond
          (length (+ (%string-sub-normalize-start start text-length) length -1))
          (end (%string-sub-normalize-end end text-length))
          (t text-length)))
         (end-index (min text-length (max 0 end-position))))
    (if (and (< start-index text-length) (>= end-index start-index)) (subseq text start-index end-index)
      "")))

(define-builtin %builtin-string-sub (context args) ()
  (multiple-value-bind (start length end quiet-p remaining error) (%parse-string-sub-options args)
    (when error
      (return-from %builtin-string-sub (values error 1)))
    (cond
      ((and length end) (values "string: -l and -e are mutually exclusive~%" 1))
      ((null remaining) (%builtin-string-usage))
      (t
        (values
          (with-output-to-string (out)
            (dolist (text remaining)
              (let ((slice (%string-slice text start :length length :end end)))
                (unless quiet-p
                  (write-string slice out)
                  (write-char #\Newline out)))))
          0)))))

(defun %string-trim-char-bag (chars)
  (if chars (coerce chars 'list)
    '(#\Space #\Tab #\Newline #\Return)))

(defun %string-trim-line (text left-p right-p chars)
  (let ((bag (%string-trim-char-bag chars)))
    (cond
      ((and left-p (not right-p)) (string-left-trim bag text))
      ((and right-p (not left-p)) (string-right-trim bag text))
      (t (string-trim bag text)))))

(define-builtin %builtin-string-trim (context args) ()
  (let ((left-p nil)
        (right-p nil)
        (chars nil))
    (with-string-options
      (remaining
        error
        args
        "string"
        +string-trim-flag-option-specs+
        +string-trim-value-option-specs+
        (%string-flag-option-handler
          (name remaining)
          (left
            (setf left-p t))
          (right
            (setf right-p t)))
        (%string-integer-option-handler
          (name parsed next-remaining)
          (chars
            (setf chars parsed))))
      (when error
        (return-from %builtin-string-trim (values error 1)))
      (values
        (%string-emit-lines remaining
          :transform (lambda (text) (%string-trim-line text left-p right-p chars)))
        (if remaining 0 1)))))

(define-builtin %builtin-string-dispatch (context args) ()
  (let* ((subcommand (first args))
         (spec (%builtin-string-subcommand-spec subcommand))
         (handler (%builtin-string-spec-handler spec)))
    (if handler (funcall handler context (rest args))
      (%builtin-string-usage))))
