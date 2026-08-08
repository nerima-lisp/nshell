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

(defun %builtin-string-collect (context args)
  (declare (ignore context))
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

(defun %builtin-string-join (context args)
  (declare (ignore context))
  (if (rest args) (values (format nil "~a~%" (%string-join (rest args) (first args))) 0)
    (%builtin-string-usage)))

(defun %builtin-string-split (context args)
  (declare (ignore context))
  (if (rest args) (labels ((split-on (separator string)
               (cond
            ((%string-empty-p separator) (map 'list #'string string))
            (t
              (let ((start 0)
                    (parts nil)
                    (separator-length (length separator)))
                (loop for pos = (search separator string :start2 start)
                      do (push (subseq string start pos) parts)
                      while pos
                      do (setf start (+ pos separator-length)))
                (nreverse parts))))))
      (values
        (%string-emit-lines
          (loop for text in (rest args)
                append (split-on (first args) text)))
        0))
    (%builtin-string-usage)))

(defun %parse-string-flags (remaining builtin flag-specs)
  (let ((quiet-p nil)
        (all-p nil)
        (ignore-case-p nil))
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
            (setf ignore-case-p t)))
        (%string-integer-option-handler (name parsed next-remaining)))
      (values quiet-p all-p ignore-case-p remaining error))))

(defun %string-pattern-builtin (args flag-specs required-args collector)
  (multiple-value-bind (quiet-p all-p ignore-case-p remaining error) (%parse-string-flags args "string" flag-specs)
    (when error
      (return-from %string-pattern-builtin (values error 1)))
    (if (< (length remaining) required-args) (%builtin-string-usage)
      (funcall collector quiet-p all-p ignore-case-p remaining))))

(defun %builtin-string-replace (context args)
  (declare (ignore context))
  (%string-pattern-builtin
    args
    +string-replace-flag-option-specs+
    3
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

(defun %builtin-string-match (context args)
  (declare (ignore context))
  (%string-pattern-builtin
    args
    +string-match-flag-option-specs+
    2
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

(defun %string-repeat-effective-count (text count max-length)
  (or count (and max-length (max 1 (ceiling max-length (max 1 (length text))))) 1))

(defun %string-repeat-text (text count &optional max-length)
  (when (plusp count)
    (if max-length (let ((remaining max-length)
            (text-length (length text)))
        (with-output-to-string (out)
          (loop repeat
                count
                while (and (plusp remaining) (plusp text-length))
                for written = (min remaining text-length)
                do (write-string text out :end written) (decf remaining written))))
      (with-output-to-string (out)
        (loop repeat
              count
              do (write-string text out))))))

(defun %parse-string-repeat-options (remaining)
  (let ((repeat-count nil)
        (max-length nil)
        (quiet-p nil)
        (no-newline-p nil))
    (with-string-options
      (next-remaining
        error
        remaining
        "string"
        +string-repeat-flag-option-specs+
        +string-repeat-integer-option-specs+
        (%string-flag-option-handler
          (name remaining)
          (quiet
            (setf quiet-p t))
          (no-newline
            (setf no-newline-p t)))
        (%string-integer-option-handler
          (name parsed next-remaining)
          (count
            (setf repeat-count parsed))
          (max
            (setf max-length parsed))))
      (values repeat-count max-length quiet-p no-newline-p next-remaining error))))

(defun %string-repeat-bare-count-usage-p (repeat-count max-length remaining)
  (and
    (null repeat-count)
    (null max-length)
    (rest remaining)
    (multiple-value-bind (parsed error) (%string-parse-integer-option "count" (first remaining))
      (declare (ignore error))
      parsed)))

(defun %string-repeat-output (remaining repeat-count max-length quiet-p no-newline-p)
  (with-output-to-string (out)
    (loop for texts on remaining
          for text = (first texts)
          for effective-count = (%string-repeat-effective-count text repeat-count max-length)
          for repeated = (%string-repeat-text text effective-count max-length)
          do (when repeated
        (unless quiet-p
          (write-string repeated out))
        (unless (or quiet-p (and no-newline-p (null (rest texts))))
          (write-char #\Newline out))))))

(defun %builtin-string-repeat (context args)
  (declare (ignore context))
  (multiple-value-bind (repeat-count max-length quiet-p no-newline-p remaining error) (%parse-string-repeat-options args)
    (when error
      (return-from %builtin-string-repeat (values error 1)))
    (when (%string-repeat-bare-count-usage-p repeat-count max-length remaining)
      (return-from %builtin-string-repeat (%builtin-string-usage)))
    (if (or
        (null remaining)
        (not
          (and (plusp (or repeat-count 1)) (or (null max-length) (plusp max-length))))) (values "" 1)
      (values
        (%string-repeat-output remaining repeat-count max-length quiet-p no-newline-p)
        0))))

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

(defun %builtin-string-sub (context args)
  (declare (ignore context))
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

(define-string-line-builtin
  %builtin-string-trim
  (lambda (text)
    (string-trim '(#\Space #\Tab #\Newline #\Return) text)))

(defun %builtin-string-dispatch (context args)
  (let* ((subcommand (first args))
         (spec (%builtin-string-subcommand-spec subcommand))
         (handler (%builtin-string-spec-handler spec)))
    (if handler (funcall handler context (rest args))
      (%builtin-string-usage))))
