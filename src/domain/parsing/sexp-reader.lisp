(in-package #:nshell.domain.parsing)

(progn
  (define-condition sexp-reader-error
    (error)
    ((source-span :initarg :source-span :reader sexp-reader-error-source-span)
     (source-path :initarg :source-path :reader sexp-reader-error-source-path)
     (source-map :initarg :source-map :reader sexp-reader-error-source-map)
     (cause :initarg :cause :reader sexp-reader-error-cause)))
  (defstruct reader-result
    form
    source
    source-span
    form-span-map
    source-path
    source-map
    symbol-origins))
(defstruct (%sexp-reader-state (:constructor %make-sexp-reader-state))
  source
  source-path
  source-map
  (position 0)
  (form-spans (make-hash-table :test #'eq))
  (symbol-origins (make-hash-table :test #'eq))
  (list-elements (make-hash-table :test #'eq)))
(defvar *sexp-reader-state* nil)
(progn (defvar *sexp-reader-backquote-depth* 0) (defvar *sexp-reader-nesting-depth* 0) (defparameter +sexp-reader-max-nesting-depth+ 256))
(defparameter *sexp-reader-eof* (gensym "READER-EOF-"))
(defparameter *sexp-reader-skipped* (gensym "READER-SKIPPED-"))
(defun %sexp-reader-whitespace-p (character)
  (and character (find character '(#\Space #\Tab #\Newline #\Return #\Page))))
(defun %sexp-reader-signal (cause source-path source-map span)
  (error (make-condition 'sexp-reader-error
                         :source-span span
                         :source-path source-path
                         :source-map source-map
                         :cause cause)))
(defun %sexp-reader-record-span (form start end)
  (when (or (consp form)
            (and (vectorp form) (not (stringp form))))
    (setf (gethash form (%sexp-reader-state-form-spans *sexp-reader-state*))
          (list start end)))
  form)
(defun %sexp-reader-new-marker (source-name escaped-p qualifier start end
                                &optional flag)
  (let* ((marker (make-symbol source-name))
         (origin (list :source-name source-name
                       :escaped-p (and escaped-p t)
                       :package-qualifier qualifier
                       :source-span (list start end))))
    (when flag
      (setf origin (append origin (list flag t))))
    (setf (gethash marker (%sexp-reader-state-symbol-origins *sexp-reader-state*))
          origin)
    marker))
(defun %sexp-reader-current-position ()
  (%sexp-reader-state-position *sexp-reader-state*))
(defun %sexp-reader-peek (&optional (offset 0))
  (let* ((source (%sexp-reader-state-source *sexp-reader-state*))
         (position (+ (%sexp-reader-current-position) offset)))
    (when (< position (length source))
      (char source position))))
(defun %sexp-reader-advance (&optional (count 1))
  (incf (%sexp-reader-state-position *sexp-reader-state*) count))
(defun %sexp-reader-fail (message start &optional cause)
  (%sexp-reader-signal
   (or cause (make-condition 'simple-error
                              :format-control "~A"
                              :format-arguments (list message)))
   (%sexp-reader-state-source-path *sexp-reader-state*)
   (%sexp-reader-state-source-map *sexp-reader-state*)
   (list start (%sexp-reader-current-position))))
(defun %sexp-reader-match-at-p (source start text)
  (and (<= (+ start (length text)) (length source))
       (string= text source :start2 start :end2 (+ start (length text)))))
(defun %sexp-reader-skip-trivia ()
  (let ((source (%sexp-reader-state-source *sexp-reader-state*)))
    (loop for position = (%sexp-reader-current-position)
          do (cond
               ((%sexp-reader-whitespace-p (%sexp-reader-peek))
                (%sexp-reader-advance))
               ((eql (%sexp-reader-peek) #\;)
                (loop while (and (%sexp-reader-peek)
                                 (char/= (%sexp-reader-peek) #\Newline))
                      do (%sexp-reader-advance)))
               ((%sexp-reader-match-at-p source position "#|")
                (let ((depth 1)
                      (start position))
                  (%sexp-reader-advance 2)
                  (loop while (and (plusp depth) (%sexp-reader-peek))
                        do (cond
                             ((%sexp-reader-match-at-p
                               source (%sexp-reader-current-position) "#|")
                              (incf depth)
                              (%sexp-reader-advance 2))
                             ((%sexp-reader-match-at-p
                               source (%sexp-reader-current-position) "|#")
                              (decf depth)
                              (%sexp-reader-advance 2))
                             (t (%sexp-reader-advance))))
                  (unless (zerop depth)
                    (%sexp-reader-fail "Unterminated nested block comment." start))))
               (t (return position))))))
(defstruct (%sexp-reader-list-element
             (:constructor %make-sexp-reader-list-element (form span)))
  form
  span)
(defun %sexp-reader-source-slice (start end)
  (subseq (%sexp-reader-state-source *sexp-reader-state*) start end))
(defun %sexp-reader-token-delimiter-p (character)
  (or (null character)
      (member (char-code character) '(32 9 10 13 12 40 41 34 39 96 44 59))))
(defun %sexp-reader-read-token ()
  (let* ((source (%sexp-reader-state-source *sexp-reader-state*))
         (start (%sexp-reader-current-position))
         (first (%sexp-reader-peek))
         (next (%sexp-reader-peek 1))
         (after-next (%sexp-reader-peek 2))
         (pipe-token-p
           (and first
                (= (char-code first) 124)
                (or (%sexp-reader-token-delimiter-p next)
                    (and next
                         (= (char-code next) 38)
                         (%sexp-reader-token-delimiter-p after-next)))))
         (barred-p nil))
    (when pipe-token-p
      (let ((token (if (and next (= (char-code next) 38)) "|&" "|")))
        (%sexp-reader-advance (length token))
        (return-from %sexp-reader-read-token
          (values token (list start (%sexp-reader-current-position))))))
    (loop for character = (%sexp-reader-peek)
          while character
          do (cond
               ((and (not barred-p)
                     (%sexp-reader-token-delimiter-p character))
                (return))
               ((= (char-code character) 124)
                (setf barred-p (not barred-p))
                (%sexp-reader-advance))
               ((= (char-code character) 92)
                (%sexp-reader-advance)
                (unless (%sexp-reader-peek)
                  (%sexp-reader-fail "Trailing escape in symbol token." start))
                (%sexp-reader-advance))
               (t (%sexp-reader-advance))))
    (when barred-p
      (%sexp-reader-fail "Unterminated escaped symbol." start))
    (when (= start (%sexp-reader-current-position))
      (%sexp-reader-fail "Expected a symbol token." start))
    (values (%sexp-reader-source-slice start (%sexp-reader-current-position))
            (list start (%sexp-reader-current-position))))
)
(defun %sexp-reader-decode-symbol-token (token)
  (let ((characters nil)
        (colon-positions nil)
        (barred-p nil)
        (escaped-p nil)
        (position 0))
    (loop while (< position (length token))
          for character = (char token position)
          for code = (char-code character)
          do (cond
               ((= code 92)
                (incf position)
                (when (>= position (length token))
                  (%sexp-reader-fail "Trailing escape in symbol token."
                                     (%sexp-reader-current-position)))
                (push (char token position) characters)
                (incf position))
               ((= code 124)
                (setf barred-p (not barred-p)
                      escaped-p t)
                (incf position))
               (t
                (when (and (not barred-p) (= code 58))
                  (push (length characters) colon-positions))
                (push character characters)
                (incf position))))
    (values (coerce (nreverse characters) 'string)
            escaped-p
            (nreverse colon-positions))))
(defun %sexp-reader-symbol-from-token (token span)
  (multiple-value-bind (name escaped-p colon-positions)
      (%sexp-reader-decode-symbol-token token)
    (let ((qualifier nil)
          (keyword-p nil))
      (cond
        ((null colon-positions))
        ((and (= (length colon-positions) 1)
              (zerop (first colon-positions)))
         (setf keyword-p t
               name (subseq name 1)))
        ((and (member (length colon-positions) '(1 2))
              (plusp (first colon-positions))
              (or (= (length colon-positions) 1)
                  (= (second colon-positions) (1+ (first colon-positions)))))
         (let* ((separator-count (length colon-positions))
                (separator-position (first colon-positions))
                (raw-qualifier (subseq name 0 separator-position)))
           (setf qualifier
                 (if escaped-p raw-qualifier (string-upcase raw-qualifier))
                 name (subseq name (+ separator-position separator-count)))))
        (t
         (%sexp-reader-fail "Invalid package-qualified symbol token."
                            (first span))))
      (if keyword-p
          (intern name :keyword)
          (%sexp-reader-new-marker name escaped-p qualifier
                                   (first span) (second span))))))
(defun %sexp-reader-decimal-number-token-p (token)
  (let ((length (length token))
        (position 0)
        (digit-count 0)
        (fractional-p nil)
        (exponent-p nil))
    (when (and (< position length)
               (member (char token position) '(#\+ #\-)))
      (incf position))
    (loop while (and (< position length)
                     (digit-char-p (char token position)))
          do (incf digit-count)
             (incf position))
    (when (and (< position length) (char= (char token position) #\/))
      (incf position)
      (let ((denominator-digits 0))
        (loop while (and (< position length)
                         (digit-char-p (char token position)))
              do (incf denominator-digits)
                 (incf position))
        (return-from %sexp-reader-decimal-number-token-p
          (and (plusp digit-count)
               (plusp denominator-digits)
               (= position length)))))
    (when (and (< position length) (char= (char token position) #\.))
      (setf fractional-p t)
      (incf position)
      (loop while (and (< position length)
                       (digit-char-p (char token position)))
            do (incf digit-count)
               (incf position)))
    (when (and (< position length)
               (find (char token position) "eEsSfFdDlL"))
      (setf exponent-p t)
      (incf position)
      (when (and (< position length)
                 (member (char token position) '(#\+ #\-)))
        (incf position))
      (let ((exponent-digits 0))
        (loop while (and (< position length)
                         (digit-char-p (char token position)))
              do (incf exponent-digits)
                 (incf position))
        (unless (plusp exponent-digits)
          (return-from %sexp-reader-decimal-number-token-p nil))))
    (and (plusp digit-count)
         (= position length)
         t))
)
(defun %sexp-reader-number-from-token (token span)
  (when (%sexp-reader-decimal-number-token-p token)
    (let ((*read-eval* nil)
          (*readtable* (copy-readtable nil)))
      (multiple-value-bind (number position)
          (handler-case
              (read-from-string token nil nil)
            (error (cause)
              (%sexp-reader-signal
               cause
               (%sexp-reader-state-source-path *sexp-reader-state*)
               (%sexp-reader-state-source-map *sexp-reader-state*)
               span)))
        (unless (and (numberp number)
                     (= position (length token)))
          (%sexp-reader-fail "Invalid decimal number token." (first span)))
        (values number t)))))
(defun %sexp-reader-atom-from-token (token span)
  (cond
    ((member token '("|" "|&") :test #'string=)
     (%sexp-reader-new-marker token nil nil
                              (first span) (second span)))
    ((string= token ".")
     (%sexp-reader-new-marker token nil nil
                              (first span) (second span)
                              :opaque-dot-p))
    (t
     (multiple-value-bind (number number-p)
         (%sexp-reader-number-from-token token span)
       (if number-p
           number
           (%sexp-reader-symbol-from-token token span))))))
(defun %sexp-reader-read-string ()
  (let ((start (%sexp-reader-current-position)))
    (%sexp-reader-advance)
    (values
     (with-output-to-string (output)
       (loop for character = (%sexp-reader-peek)
             do (cond
                  ((null character)
                   (%sexp-reader-fail "Unterminated string literal." start))
                  ((char= character #\")
                   (%sexp-reader-advance)
                   (return))
                  ((char= character #\\)
                   (%sexp-reader-advance)
                   (unless (%sexp-reader-peek)
                     (%sexp-reader-fail "Trailing escape in string literal." start))
                   (write-char (%sexp-reader-peek) output)
                   (%sexp-reader-advance))
                  (t
                   (write-char character output)
                   (%sexp-reader-advance)))))
     (list start (%sexp-reader-current-position)))))
(defun %sexp-reader-record-list-elements (form elements)
  (when (consp form)
    (setf (gethash form
                   (%sexp-reader-state-list-elements *sexp-reader-state*))
          elements))
  form)
(defun %sexp-reader-read-list (&optional vector-p
                                       (span-start (%sexp-reader-current-position)))
  (let ((elements nil))
    (%sexp-reader-advance)
    (loop
      (%sexp-reader-skip-trivia)
      (case (and (%sexp-reader-peek)
                 (char-code (%sexp-reader-peek)))
        (nil
         (%sexp-reader-fail "Unterminated list." span-start))
        (41
         (%sexp-reader-advance)
         (let* ((ordered-elements (nreverse elements))
                (forms (mapcar #'%sexp-reader-list-element-form
                               ordered-elements))
                (form (if vector-p (coerce forms 'vector) forms))
                (end (%sexp-reader-current-position)))
           (%sexp-reader-record-span form span-start end)
           (unless vector-p
             (%sexp-reader-record-list-elements form ordered-elements))
           (return-from %sexp-reader-read-list
             (values form span-start end nil))))
        (otherwise
         (multiple-value-bind (form start end skipped-p)
             (%sexp-reader-read-datum)
           (unless skipped-p
             (push (%make-sexp-reader-list-element
                    form (list start end))
                   elements)))))))
)
(defun %sexp-reader-read-prefix (name package prefix-length)
  (let ((start (%sexp-reader-current-position)))
    (%sexp-reader-advance prefix-length)
    (%sexp-reader-skip-trivia)
    (when (null (%sexp-reader-peek))
      (%sexp-reader-fail "Reader prefix requires a following datum." start))
    (multiple-value-bind (operand operand-start end skipped-p)
        (%sexp-reader-read-datum)
      (when skipped-p
        (%sexp-reader-fail "Reader prefix cannot precede an excluded datum."
                           start))
      (let* ((head (%sexp-reader-new-marker
                    name nil package start (+ start prefix-length)))
             (form (list head operand))
             (elements (list
                        (%make-sexp-reader-list-element
                         head (list start (+ start prefix-length)))
                        (%make-sexp-reader-list-element
                         operand (list operand-start end)))))
        (%sexp-reader-record-span form start end)
        (%sexp-reader-record-list-elements form elements)
        (values form start end nil)))))
(defun %sexp-reader-feature-symbol-name (form)
  (when (symbolp form)
    (let ((origin (gethash form
                           (%sexp-reader-state-symbol-origins
                            *sexp-reader-state*))))
      (if origin
          (let ((name (getf origin :source-name)))
            (if (getf origin :escaped-p) name (string-upcase name)))
          (symbol-name form)))))
(defun %sexp-reader-feature-expression-enabled-p (form)
  (if (consp form)
      (let ((operator (%sexp-reader-feature-symbol-name (first form)))
            (operands (rest form)))
        (cond
          ((equal operator "AND")
           (every #'%sexp-reader-feature-expression-enabled-p operands))
          ((equal operator "OR")
           (some #'%sexp-reader-feature-expression-enabled-p operands))
          ((equal operator "NOT")
           (unless (= (length operands) 1)
             (%sexp-reader-fail "Feature NOT requires one operand."
                                (%sexp-reader-current-position)))
           (not (%sexp-reader-feature-expression-enabled-p
                 (first operands))))
          (t nil)))
      (let ((name (%sexp-reader-feature-symbol-name form)))
        (and name
             (some (lambda (feature)
                     (string-equal name (symbol-name feature)))
                   *features*)))))
(defun %sexp-reader-read-feature-conditional ()
  (let* ((start (%sexp-reader-current-position))
         (include-p (char= (char (%sexp-reader-state-source
                                  *sexp-reader-state*)
                               (1+ start))
                           #\+)))
    (%sexp-reader-advance 2)
    (%sexp-reader-skip-trivia)
    (multiple-value-bind (feature-form feature-start feature-end feature-skipped-p)
        (%sexp-reader-read-datum)
      (declare (ignore feature-start feature-end))
      (when feature-skipped-p
        (%sexp-reader-fail "Feature conditional requires a feature expression."
                           start))
      (%sexp-reader-skip-trivia)
      (multiple-value-bind (form form-start end skipped-p)
          (%sexp-reader-read-datum)
        (when (null form-start)
          (%sexp-reader-fail "Feature conditional requires a payload form." start))
        (let ((enabled-p (%sexp-reader-feature-expression-enabled-p
                          feature-form)))
          (when (and include-p (not enabled-p))
            (setf skipped-p t))
          (when (and (not include-p) enabled-p)
            (setf skipped-p t))
          (if skipped-p
              (values *sexp-reader-skipped* start end t)
              (progn
                (%sexp-reader-record-span form start end)
                (values form start end nil))))))))
(defun %sexp-reader-read-radix-dispatch (base start)
  (multiple-value-bind (token token-span)
      (%sexp-reader-read-token)
    (declare (ignore token-span))
    (multiple-value-bind (number position)
        (parse-integer token :radix base :junk-allowed t)
      (unless (and number (= position (length token)))
        (%sexp-reader-fail "Invalid radix integer." start))
      (values number start (%sexp-reader-current-position) nil))))
(defun %sexp-reader-read-bit-vector-dispatch (start)
  (let ((token-start (%sexp-reader-current-position)))
    (loop while (and (%sexp-reader-peek)
                     (not (%sexp-reader-token-delimiter-p
                           (%sexp-reader-peek))))
          do (%sexp-reader-advance))
    (let* ((token (%sexp-reader-source-slice
                   token-start (%sexp-reader-current-position)))
           (bits (map 'list (lambda (character)
                              (case character
                                (#\0 0)
                                (#\1 1)
                                (otherwise
                                 (%sexp-reader-fail
                                  "Bit vector contains a non-bit character."
                                  start))))
                      token))
           (vector (make-array (length bits)
                               :element-type 'bit
                               :initial-contents bits))
           (end (%sexp-reader-current-position)))
      (%sexp-reader-record-span vector start end)
      (values vector start end nil))))
(defun %sexp-reader-read-complex-dispatch (start)
  (%sexp-reader-skip-trivia)
  (multiple-value-bind (parts part-start end skipped-p)
      (%sexp-reader-read-datum)
    (when skipped-p
      (%sexp-reader-fail "Complex dispatch requires two numeric components."
                         start))
    (unless (and (listp parts)
                 (= (length parts) 2)
                 (realp (first parts))
                 (realp (second parts)))
      (%sexp-reader-fail "Complex dispatch requires two real components."
                         part-start))
    (values (complex (first parts) (second parts))
            start end nil)))
(defun %sexp-reader-read-pathname-dispatch (start)
  (%sexp-reader-skip-trivia)
  (multiple-value-bind (namestring name-start end skipped-p)
      (%sexp-reader-read-datum)
    (when skipped-p
      (%sexp-reader-fail "Pathname dispatch requires a namestring." start))
    (unless (stringp namestring)
      (%sexp-reader-fail "Pathname dispatch requires a string literal."
                         name-start))
    (values (pathname namestring) start end nil)))
(defun %sexp-reader-array-shape (contents)
  (cond
    ((or (stringp contents) (not (or (consp contents)
                                     (and (vectorp contents)
                                          (not (stringp contents))))))
     nil)
    (t
     (let* ((items (coerce contents 'list))
            (shapes (mapcar #'%sexp-reader-array-shape items))
            (first-shape (first shapes)))
       (unless (every (lambda (shape) (equal shape first-shape)) shapes)
         (%sexp-reader-fail "Array literal has inconsistent dimensions."
                            (%sexp-reader-current-position)))
       (cons (length items) first-shape)))))
(defun %sexp-reader-read-array-dispatch (start rank)
  (%sexp-reader-skip-trivia)
  (multiple-value-bind (contents content-start end skipped-p)
      (%sexp-reader-read-datum)
    (when skipped-p
      (%sexp-reader-fail "Array dispatch requires initial contents." start))
    (let* ((dimensions (%sexp-reader-array-shape contents))
           (rank (or rank (length dimensions))))
      (unless (= rank (length dimensions))
        (%sexp-reader-fail "Array literal rank does not match its contents."
                           content-start))
      (let ((array
              (handler-case
                  (if (zerop rank)
                      (make-array nil :initial-element contents)
                      (make-array dimensions :initial-contents contents))
                (error (cause)
                  (%sexp-reader-signal
                   cause
                   (%sexp-reader-state-source-path *sexp-reader-state*)
                   (%sexp-reader-state-source-map *sexp-reader-state*)
                   (list start end))))))
        (%sexp-reader-record-span array start end)
        (values array start end nil)))))
(defun %sexp-reader-read-prefixed-datum
    (name package source-start prefix-length prefix-end)
  (%sexp-reader-advance prefix-length)
  (%sexp-reader-skip-trivia)
  (when (null (%sexp-reader-peek))
    (%sexp-reader-fail "Reader prefix requires a following datum."
                       source-start))
  (multiple-value-bind (operand operand-start end skipped-p)
      (%sexp-reader-read-datum)
    (when skipped-p
      (%sexp-reader-fail "Reader prefix cannot precede an excluded datum."
                         source-start))
    (let* ((head (%sexp-reader-new-marker name nil package source-start prefix-end :reader-prefix-p))
           (form (list head operand))
           (elements (list
                      (%make-sexp-reader-list-element
                       head (list source-start prefix-end))
                      (%make-sexp-reader-list-element
                       operand (list operand-start end)))))
      (%sexp-reader-record-span form source-start end)
      (%sexp-reader-record-list-elements form elements)
      (values form source-start end nil))))
(defun %sexp-reader-read-dispatch ()
  (let* ((source (%sexp-reader-state-source *sexp-reader-state*))
         (start (%sexp-reader-current-position))
         (next (%sexp-reader-peek 1)))
    (cond
      ((and next (member (char-code next) '(43 45)))
       (%sexp-reader-read-feature-conditional))
      ((and next (= (char-code next) 92))
       (%sexp-reader-read-character-dispatch start))
      ((and next (= (char-code next) 59))
       (%sexp-reader-advance 2)
       (%sexp-reader-skip-trivia)
       (multiple-value-bind (ignored ignored-start end skipped-p)
           (%sexp-reader-read-datum)
         (declare (ignore ignored ignored-start))
         (values *sexp-reader-skipped* start end (or skipped-p t))))
      (t
       (%sexp-reader-advance)
       (let ((prefix-start (%sexp-reader-current-position)))
         (loop while (and (%sexp-reader-peek)
                          (digit-char-p (%sexp-reader-peek)))
               do (%sexp-reader-advance))
         (let* ((digits (%sexp-reader-source-slice
                         prefix-start (%sexp-reader-current-position)))
                (dispatch (%sexp-reader-peek))
                (code (and dispatch (char-upcase dispatch))))
           (when (and digits dispatch (member (char-code dispatch) '(35 61)))
             (%sexp-reader-advance)
             (%sexp-reader-fail "Shared and circular reader labels are disabled."
                                start))
           (unless dispatch
             (%sexp-reader-fail "Incomplete reader dispatch." start))
           (case (char-code code)
             (46
              (%sexp-reader-advance)
              (%sexp-reader-fail "Reader evaluation dispatch #. is disabled."
                                 start))
             (39
              (%sexp-reader-read-prefixed-datum
               "FUNCTION" "CL" start 1 (+ start 2)))
             (40
              (%sexp-reader-read-list t start))
             (58
              (%sexp-reader-advance)
              (multiple-value-bind (token token-span)
                  (%sexp-reader-read-token)
                (multiple-value-bind (name escaped-p ignored-colons)
                    (%sexp-reader-decode-symbol-token token)
                  (declare (ignore ignored-colons))
                  (let ((end (%sexp-reader-current-position)))
                    (values (%sexp-reader-new-marker
                             name escaped-p nil start end)
                            start end nil)))))
             (66
              (%sexp-reader-advance)
              (%sexp-reader-read-radix-dispatch 2 start))
             (79
              (%sexp-reader-advance)
              (%sexp-reader-read-radix-dispatch 8 start))
             (88
              (%sexp-reader-advance)
              (%sexp-reader-read-radix-dispatch 16 start))
             (82
              (unless (plusp (length digits))
                (%sexp-reader-fail "Radix dispatch requires a base." start))
              (%sexp-reader-advance)
              (let ((base (parse-integer digits)))
                (unless (<= 2 base 36)
                  (%sexp-reader-fail "Radix base must be from 2 through 36."
                                     start))
                (%sexp-reader-read-radix-dispatch base start)))
             (65
              (%sexp-reader-advance)
              (%sexp-reader-read-array-dispatch
               start (and (plusp (length digits)) (parse-integer digits))))
             (67
              (%sexp-reader-advance)
              (%sexp-reader-read-complex-dispatch start))
             (80
              (%sexp-reader-advance)
              (%sexp-reader-read-pathname-dispatch start))
             (83
              (%sexp-reader-advance)
              (%sexp-reader-skip-trivia)
              (multiple-value-bind (payload payload-start end skipped-p)
                  (%sexp-reader-read-datum)
                (declare (ignore payload payload-start))
                (when skipped-p
                  (%sexp-reader-fail "Structure dispatch requires a payload."
                                     start))
                (values (%sexp-reader-new-marker
                         (%sexp-reader-source-slice start end)
                         nil nil start end :opaque-dispatch-p)
                        start end nil)))
             (42
              (%sexp-reader-advance)
              (%sexp-reader-read-bit-vector-dispatch start))
             (59
              (%sexp-reader-advance)
              (%sexp-reader-skip-trivia)
              (multiple-value-bind (ignored ignored-start end skipped-p)
                  (%sexp-reader-read-datum)
                (declare (ignore ignored ignored-start))
                (values *sexp-reader-skipped* start end (or skipped-p t))))
             (t
              (multiple-value-bind (token token-span)
                  (%sexp-reader-read-token)
                (declare (ignore token-span))
                (let ((end (%sexp-reader-current-position)))
                  (values (%sexp-reader-new-marker
                           (%sexp-reader-source-slice start end)
                           nil nil start end :opaque-dispatch-p)
                          start end nil))))))))))
)
(defun %sexp-reader-read-datum ()
  (let ((*sexp-reader-nesting-depth* (1+ *sexp-reader-nesting-depth*)))
    (%sexp-reader-skip-trivia)
    (let* ((start (%sexp-reader-current-position))
           (character (%sexp-reader-peek))
           (code (and character (char-code character))))
      (when (> *sexp-reader-nesting-depth* +sexp-reader-max-nesting-depth+)
        (%sexp-reader-signal
         (make-condition 'simple-error
                         :format-control "Reader nesting exceeds the limit of ~D."
                         :format-arguments
                         (list +sexp-reader-max-nesting-depth+))
         (%sexp-reader-state-source-path *sexp-reader-state*)
         (%sexp-reader-state-source-map *sexp-reader-state*)
         (list start (if character (1+ start) start))))
      (unless character
        (%sexp-reader-fail "Expected a datum." start))
      (case code
        (40
         (%sexp-reader-read-list))
        (41
         (%sexp-reader-advance)
         (%sexp-reader-fail "Unexpected closing parenthesis." start))
        (34
         (multiple-value-bind (string span)
             (%sexp-reader-read-string)
           (values string (first span) (second span) nil)))
        (39
         (%sexp-reader-read-prefixed-datum "QUOTE" "CL"
                                           start 1 (1+ start)))
        (96
         (let ((*sexp-reader-backquote-depth*
                 (1+ *sexp-reader-backquote-depth*)))
           (%sexp-reader-read-prefixed-datum "QUASIQUOTE" "CL"
                                             start 1 (1+ start))))
        (44
         (let* ((splicing-p (= (or (and (%sexp-reader-peek 1)
                                        (char-code (%sexp-reader-peek 1)))
                                   0)
                               64))
                (length (if splicing-p 2 1)))
           (%sexp-reader-read-prefixed-datum
            (if splicing-p "UNQUOTE-SPLICING" "UNQUOTE")
            "CL" start length (+ start length))))
        (36
         (%sexp-reader-read-prefixed-datum "UNQUOTE" "NSHELL.USER"
                                           start 1 (1+ start)))
        (35
         (if (null (%sexp-reader-peek 1))
             (progn
               (%sexp-reader-advance)
               (values (%sexp-reader-new-marker
                        "#" nil nil start (%sexp-reader-current-position)
                        :opaque-dispatch-p)
                       start (%sexp-reader-current-position) nil))
             (%sexp-reader-read-dispatch)))
        (otherwise
         (multiple-value-bind (token span)
             (%sexp-reader-read-token)
           (values (%sexp-reader-atom-from-token token span)
                   (first span) (second span) nil)))))))
(defun %sexp-reader-copy-form-metadata (metadata form)
  (let ((copy (make-hash-table :test #'eq))
        (visited (make-hash-table :test #'eq)))
    (labels ((visit (object)
               (multiple-value-bind (value present-p)
                   (gethash object metadata)
                 (when present-p
                   (setf (gethash object copy) value)))
               (when (or (consp object)
                         (and (vectorp object) (not (stringp object))))
                 (unless (gethash object visited)
                   (setf (gethash object visited) t)
                   (if (consp object)
                       (progn
                         (visit (car object))
                         (visit (cdr object)))
                       (loop for element across object
                             do (visit element))))))) (visit form)
    copy))
)
(defun %sexp-reader-first-non-whitespace (source)
  (or (position-if-not #'%sexp-reader-whitespace-p source)
      (length source)))
(defun %sexp-reader-make-result (form span bare-line-p)
  (make-reader-result
   :form form
   :source (%sexp-reader-state-source *sexp-reader-state*)
   :source-span span
   :form-span-map
   (if bare-line-p
       (make-hash-table :test #'eq)
       (%sexp-reader-copy-form-metadata
        (%sexp-reader-state-form-spans *sexp-reader-state*) form))
   :source-path (%sexp-reader-state-source-path *sexp-reader-state*)
   :source-map (%sexp-reader-state-source-map *sexp-reader-state*)
   :symbol-origins
   (if bare-line-p
       (let ((copy (make-hash-table :test #'eq)))
         (maphash (lambda (symbol origin)
                    (setf (gethash symbol copy) (copy-list origin)))
                  (%sexp-reader-state-symbol-origins *sexp-reader-state*))
         copy)
       (%sexp-reader-copy-form-metadata
        (%sexp-reader-state-symbol-origins *sexp-reader-state*) form))))
(defun %sexp-reader-read-sexps ()
  (let ((results nil))
    (loop
      (clrhash (%sexp-reader-state-form-spans *sexp-reader-state*))
      (clrhash (%sexp-reader-state-symbol-origins *sexp-reader-state*))
      (clrhash (%sexp-reader-state-list-elements *sexp-reader-state*))
      (%sexp-reader-skip-trivia)
      (when (null (%sexp-reader-peek))
        (return (nreverse results)))
      (let ((position-before (%sexp-reader-current-position)))
        (multiple-value-bind (form start end skipped-p)
            (%sexp-reader-read-datum)
          (unless (> (%sexp-reader-current-position) position-before)
            (%sexp-reader-fail
             (format nil "Reader datum did not consume input (~D to ~D at ~S)."
                     position-before
                     (%sexp-reader-current-position)
                     (%sexp-reader-peek))
             position-before))
          (unless skipped-p
            (push (%sexp-reader-make-result form (list start end) nil)
                  results)))))))
(defun read-submission (source &key
                                (reader-context :auto)
                                source-path
                                source-map)
  (unless (stringp source)
    (error "Reader source must be a string: ~S" source))
  (let* ((state (%make-sexp-reader-state
                 :source source
                 :source-path source-path
                 :source-map source-map))
         (*sexp-reader-state* state)
         (context reader-context))
    (unless (member context '(:auto :sexp :bare-line))
      (%sexp-reader-fail "Reader context must be :AUTO, :SEXP, or :BARE-LINE."
                         0))
    (unless (or (null source-path)
                (pathnamep source-path)
                (stringp source-path))
      (%sexp-reader-fail "Reader source path must be a pathname, string, or NIL."
                         0))
    (unless (or (null source-map)
                (and (vectorp source-map)
                     (= (length source-map) (length source))))
      (%sexp-reader-fail "Reader source map must have one entry per source character."
                         0))
    (when (eq context :auto)
      (let ((position (%sexp-reader-first-non-whitespace source)))
        (setf context
              (if (and (< position (length source))
                       (= (char-code (char source position)) 40))
                  :sexp
                  :bare-line))))
    (handler-case
        (if (eq context :sexp)
            (%sexp-reader-read-sexps)
            (multiple-value-bind (form span)
                (%sexp-reader-read-bare-line source)
              (if form
                  (list (%sexp-reader-make-result form span t))
                  nil)))
      (sexp-reader-error (condition)
        (error condition))
      (error (cause)
        (%sexp-reader-signal
         cause
         (%sexp-reader-state-source-path *sexp-reader-state*)
         (%sexp-reader-state-source-map *sexp-reader-state*)
         (list (%sexp-reader-current-position)
               (%sexp-reader-current-position)))))))
(defun %sexp-reader-command-form-name (form)
  (when (symbolp form)
    (let ((origin (gethash form
                           (%sexp-reader-state-symbol-origins
                            *sexp-reader-state*))))
      (or (and origin (getf origin :source-name))
          (and (keywordp form) (symbol-name form))))))
(defun %sexp-reader-command-value-argument (form span)
  (let* ((head (and (consp form) (first form)))
         (head-name (%sexp-reader-command-form-name head)))
    (cond
      ((string-equal (or head-name "") "UNQUOTE-SPLICING")
       (make-command-value-form :splice (second form) span))
      ((string-equal (or head-name "") "UNQUOTE")
       (make-command-value-form :value (second form) span))
      ((string-equal (or head-name "") "QUOTE")
       (make-command-value-form :quoted (second form) span))
      (t
       (make-command-value-form :value form span)))))
(defun %sexp-reader-command-argument (form span)
  (let* ((raw (%sexp-reader-source-slice (first span) (second span)))
         (origin (and (symbolp form)
                      (gethash form
                               (%sexp-reader-state-symbol-origins
                                *sexp-reader-state*))))
         (escaped-p (and origin (getf origin :escaped-p)))
         (opaque-dispatch-p
           (and origin (getf origin :opaque-dispatch-p)))
         (opaque-dot-p (and origin (getf origin :opaque-dot-p))))
    (cond
      ((stringp form)
       (make-command-arg form :double nil nil span nil nil))
      ((and (symbolp form) (keywordp form))
       (make-command-arg (symbol-name form) nil nil nil span nil nil))
      (opaque-dispatch-p
       (make-command-arg raw nil nil nil span nil nil))
      (opaque-dot-p
       (make-command-arg raw nil nil nil span nil nil))
      (escaped-p
       (make-command-arg (getf origin :source-name) nil nil nil span nil nil))
      ((and origin (symbolp form))
       (make-command-arg raw nil nil nil span t t))
      ((or (numberp form) (characterp form))
       (make-command-arg raw nil nil nil span nil nil))
      (t
       (%sexp-reader-command-value-argument form span)))))
(defun %sexp-reader-command-error (message span)
  (%sexp-reader-signal
   (make-condition 'simple-error
                   :format-control "~A"
                   :format-arguments (list message))
   (%sexp-reader-state-source-path *sexp-reader-state*)
   (%sexp-reader-state-source-map *sexp-reader-state*)
   span))
(defun %sexp-reader-command-origin (form)
  (and (symbolp form)
       (gethash form (%sexp-reader-state-symbol-origins *sexp-reader-state*))))
(defun %sexp-reader-command-direct-elements (form span)
  (unless (and (consp form)
               (handler-case (progn (list-length form) t)
                 (type-error () nil)))
    (%sexp-reader-command-error "A command form must be a proper nonempty list."
                                 span))
  (or (gethash form (%sexp-reader-state-list-elements *sexp-reader-state*))
      (%sexp-reader-command-error "The command form has no source element map."
                                  span)))
(defun %sexp-reader-command-token-text (form span)
  (let ((origin (%sexp-reader-command-origin form)))
    (when (and origin
               (not (getf origin :escaped-p))
               (not (getf origin :opaque-dispatch-p))
               (not (getf origin :opaque-dot-p))
               (equal span (getf origin :source-span)))
      (%sexp-reader-source-slice (first span) (second span)))))
(defun %sexp-reader-command-pipeline-operator-p (form span)
  (member (%sexp-reader-command-token-text form span)
          '("|" "|&")
          :test #'string=))
(defun %sexp-reader-command-head-source (form span)
  (cond
    ((and (symbolp form)
          (%sexp-reader-command-origin form)
          (not (getf (%sexp-reader-command-origin form) :opaque-dispatch-p))
          (not (getf (%sexp-reader-command-origin form) :opaque-dot-p)))
     (%sexp-reader-source-slice (first span) (second span)))
    (t nil)))
(defun %sexp-reader-command-head-name (form span)
  (let* ((origin (%sexp-reader-command-origin form))
         (source (%sexp-reader-command-head-source form span)))
    (cond
      ((null source)
       (%sexp-reader-command-error "A command head must be a simple source token."
                                   span))
      ((getf origin :escaped-p)
       (values (getf origin :source-name) nil))
      ((and (plusp (length source)) (char= (char source 0) #\^))
       (when (= (length source) 1)
         (%sexp-reader-command-error "The ^ marker requires a command name."
                                     span))
       (values (subseq source 1) t))
      (t
       (values source nil)))))
(defun %sexp-reader-command-pipeline-p (form span)
  (let ((elements (%sexp-reader-command-direct-elements form span)))
    (and elements
         (%sexp-reader-command-pipeline-operator-p
          (%sexp-reader-list-element-form (first elements))
          (%sexp-reader-list-element-span (first elements))))))
(defun %sexp-reader-command-classify-stage (form span head-classifier)
  (let* ((elements (%sexp-reader-command-direct-elements form span))
         (head-element (first elements))
         (head (%sexp-reader-list-element-form head-element))
         (head-span (%sexp-reader-list-element-span head-element))
         (head-source (%sexp-reader-command-head-source head head-span)))
    (unless head-source
      (%sexp-reader-command-error "A pipeline stage requires a simple command head."
                                  span))
    (unless (eq (funcall head-classifier head-source) :command-island)
      (%sexp-reader-command-error "A pipeline stage must be a command-island form."
                                  span))
    t))
(defun %sexp-reader-command-redirect-spec (operator &optional bare-line-p)
  (let ((spec (assoc operator
                     '(("<" :input-file 0)
                       ("0<" :input-file 0)
                       (">" :output-file 1)
                       ("1>" :output-file 1)
                       (">>" :append-output-file 1)
                       ("1>>" :append-output-file 1)
                       (">|" :force-output-file 1)
                       ("2>" :error-file 2)
                       ("2>>" :append-error-file 2)
                       ("&>" :both-output-files nil)
                       ("&>>" :append-both-output-files nil)
                       ("<&" :duplicate-input-fd 0)
                       (">&" :duplicate-output-fd 1)
                       ("<<" :here-document 0)
                       ("<<-" :here-document-strip-tabs 0)
                       ("<<<" :here-string 0))
                     :test #'string=)))
    (when spec
      (return-from %sexp-reader-command-redirect-spec
        (values (second spec) (third spec)))))
  (when bare-line-p
    (let ((descriptor-end (position-if-not #'digit-char-p operator)))
      (when (and descriptor-end (plusp descriptor-end))
        (let* ((base-operator (subseq operator descriptor-end))
               (base-spec
                 (assoc base-operator
                        '(("<" :input-file 0)
                          (">" :output-file 1)
                          (">>" :append-output-file 1))
                        :test #'string=)))
          (when base-spec
            (return-from %sexp-reader-command-redirect-spec
              (values (second base-spec)
                      (parse-integer operator :end descriptor-end)))))))
    (let* ((separator (or (search "<&" operator :from-end t)
                          (search ">&" operator :from-end t)))
           (descriptor-prefix
             (and separator (subseq operator 0 separator)))
           (inline-target-start (and separator (+ separator 2))))
      (when (and inline-target-start
                 (< inline-target-start (length operator))
                 (every #'digit-char-p descriptor-prefix))
        (let ((duplicate-input-p
                (string= (subseq operator separator) "<&")))
          (return-from %sexp-reader-command-redirect-spec
            (values (if duplicate-input-p
                        :duplicate-input-fd
                        :duplicate-output-fd)
                    (if (plusp (length descriptor-prefix))
                        (parse-integer descriptor-prefix)
                        (if duplicate-input-p 0 1))))))))
  (let ((separator (or (search "<&" operator :from-end t)
                       (search ">&" operator :from-end t))))
    (when (and separator
               (plusp separator)
               (= (+ separator 2) (length operator))
               (every #'digit-char-p (subseq operator 0 separator)))
      (values (if (string= (subseq operator separator) "<&")
                  :duplicate-input-fd
                  :duplicate-output-fd)
              (parse-integer operator :end separator)))))
(defun %sexp-reader-command-fd-target (form span)
  (let* ((argument (%sexp-reader-command-argument form span))
         (value (command-arg-value argument)))
    (cond
      ((string= value "-")
       (make-redirect-fd-close-target))
      ((and (plusp (length value)) (every #'digit-char-p value))
       (make-redirect-fd-target (parse-integer value)))
      (t
       (%sexp-reader-command-error "Descriptor duplication requires a decimal descriptor or -."
                                   span)))))
(defun %sexp-reader-command-process-substitution-at (elements index)
  (when (and (< (1+ index) (length elements))
             (member (%sexp-reader-command-token-text
                      (%sexp-reader-list-element-form (nth index elements))
                      (%sexp-reader-list-element-span (nth index elements)))
                     '("<" ">")
                     :test #'string=))
    (let* ((marker-element (nth index elements))
           (form-element (nth (1+ index) elements))
           (marker-span (%sexp-reader-list-element-span marker-element))
           (form-span (%sexp-reader-list-element-span form-element))
           (form (%sexp-reader-list-element-form form-element)))
      (when (and (consp form)
                 (= (second marker-span) (first form-span))
                 (char= (char (%sexp-reader-state-source *sexp-reader-state*)
                              (first form-span))
                        #\())
        (values (if (char= (char (%sexp-reader-source-slice
                                  (first marker-span) (second marker-span)) 0)
                           #\<)
                    :input
                    :output)
                form
                (list (first marker-span) (second form-span)))))))
(defun %sexp-reader-command-heredoc-target
    (form span kind elements target-index)
  (let* ((argument (%sexp-reader-command-argument form span))
         (origin (%sexp-reader-command-origin form))
         (strip-tabs-p (eq kind :here-document-strip-tabs))
         (quoted-p (or (command-arg-quote-style argument)
                       (and origin (getf origin :escaped-p))))
         (delimiter (command-arg-value argument))
         (source (%sexp-reader-state-source *sexp-reader-state*))
         (delimiter-line-end
           (position #\Newline source :start (second span))))
    (unless delimiter-line-end
      (%sexp-reader-command-error
       "A here-document delimiter must end its line."
       span))
    (let ((body-start (1+ delimiter-line-end))
          (terminator-start nil)
          (terminator-end nil)
          (terminator-element-index nil))
      (loop with line-start = body-start
            while (<= line-start (length source))
            do (let* ((line-end
                        (or (position #\Newline source :start line-start)
                            (length source)))
                      (content-start
                        (if strip-tabs-p
                            (or (position-if-not
                                 (lambda (character)
                                   (char= character #\Tab))
                                 source :start line-start :end line-end)
                                line-end)
                            line-start))
                      (content-end (+ content-start (length delimiter))))
                 (when (and (<= content-end line-end)
                            (string= delimiter source
                                     :start2 content-start :end2 content-end)
                            (every
                             (lambda (character)
                               (or (%sexp-reader-whitespace-p character)
                                   (= (char-code character) 41)))
                             (subseq source content-end line-end)))
                   (setf terminator-start line-start
                         terminator-end content-end)
                   (return))
                 (if (= line-end (length source))
                     (return)
                     (setf line-start (1+ line-end)))))
      (unless terminator-start
        (%sexp-reader-command-error
         "The here-document terminator was not found."
         (list body-start (length source))))
      (loop for element in elements
            for index from (1+ target-index)
            for element-span = (%sexp-reader-list-element-span element)
            when (and (>= (first element-span) terminator-start)
                      (= (second element-span) terminator-end))
              do (setf terminator-element-index index)
                 (return))
      (unless terminator-element-index
        (%sexp-reader-command-error
         "The here-document terminator must be a direct command element."
         (list terminator-start terminator-end)))
      (values
       (make-redirect-heredoc-target
        (make-command-arg delimiter
                          (command-arg-quote-style argument)
                          quoted-p
                          (command-arg-fragments argument)
                          span
                          nil
                          nil)
        (subseq source body-start terminator-start)
        (not quoted-p)
        strip-tabs-p
        (list body-start terminator-start))
       terminator-element-index))))
(defun %sexp-reader-command-redirect-target
    (kind form span elements target-index)
  (cond
    ((member kind '(:duplicate-input-fd :duplicate-output-fd))
     (values (%sexp-reader-command-fd-target form span) nil))
    ((member kind '(:here-document :here-document-strip-tabs))
     (%sexp-reader-command-heredoc-target
      form span kind elements target-index))
    (t
     (values (%sexp-reader-command-argument form span) nil))))
(defun %sexp-reader-command-convert (form span head-classifier)
  (labels ((convert-form (current current-span classify-head-p allow-pipeline-p)
             (if (%sexp-reader-command-pipeline-p current current-span)
                 (if allow-pipeline-p
                     (convert-pipeline current current-span)
                     (%sexp-reader-command-error
                      "A pipeline cannot be nested as a pipeline stage."
                      current-span))
                 (convert-command current current-span classify-head-p)))
           (convert-pipeline (current current-span)
             (let* ((elements (%sexp-reader-command-direct-elements
                               current current-span))
                    (operator-element (first elements))
                    (operator-span
                      (%sexp-reader-list-element-span operator-element))
                    (operator (%sexp-reader-command-token-text
                               (%sexp-reader-list-element-form operator-element)
                               operator-span))
                    (stages (rest elements)))
               (unless (>= (length stages) 2)
                 (%sexp-reader-command-error
                  "A pipeline requires at least two command stages."
                  current-span))
               (let ((commands
                       (loop for stage-element in stages
                             for stage = (%sexp-reader-list-element-form
                                          stage-element)
                             for stage-span = (%sexp-reader-list-element-span
                                               stage-element)
                             collect
                               (convert-form stage stage-span t nil)))
                     (edge-kind (if (string= operator "|&")
                                    :pipe-stderr-to-stdout
                                    :pipe)))
                 (make-pipeline-node
                  commands
                  current-span
                  (loop repeat (1- (length commands))
                        collect (make-pipeline-edge edge-kind operator-span))))))
           (convert-command (current current-span classify-head-p)
             (let* ((elements (%sexp-reader-command-direct-elements
                               current current-span))
                    (head-element (first elements))
                    (head (%sexp-reader-list-element-form head-element))
                    (head-span (%sexp-reader-list-element-span head-element)))
               (when classify-head-p
                 (%sexp-reader-command-classify-stage
                  current current-span head-classifier))
               (multiple-value-bind (command force-external-p)
                   (%sexp-reader-command-head-name head head-span)
                 (let ((argument-forms nil)
                       (arguments nil)
                       (redirects nil)
                       (index 1)
                       (redirect-order 0))
                   (loop while (< index (length elements))
                         do (let* ((element (nth index elements))
                                   (argument
                                     (%sexp-reader-list-element-form element))
                                   (argument-span
                                     (%sexp-reader-list-element-span element))
                                   (operator
                                     (%sexp-reader-command-token-text
                                      argument argument-span)))
                              (multiple-value-bind (kind descriptor)
                                  (and operator
                                       (%sexp-reader-command-redirect-spec
                                        operator))
                                (if (and kind
                                     (not (nth-value
                                           0
                                           (%sexp-reader-command-process-substitution-at
                                            elements index))))
                                    (let ((target-index (1+ index)))
                                      (when (>= target-index (length elements))
                                        (%sexp-reader-command-error
                                         "A redirect requires a target."
                                         argument-span))
                                      (let* ((target-element
                                               (nth target-index elements))
                                             (target-form
                                               (%sexp-reader-list-element-form
                                                target-element))
                                             (target-span
                                               (%sexp-reader-list-element-span
                                                target-element)))
                                        (multiple-value-bind
                                              (direction process-form
                                                         process-span)
                                            (%sexp-reader-command-process-substitution-at
                                             elements target-index)
                                          (let ((process-target
                                                  (and direction
                                                       (make-redirect-procsub-target
                                                        direction
                                                        (convert-form
                                                         process-form
                                                         process-span
                                                         t
                                                         t)))))
                                            (multiple-value-bind
                                                  (target terminator-index)
                                                (if process-target
                                                    (values process-target nil)
                                                    (%sexp-reader-command-redirect-target
                                                     kind target-form
                                                     target-span elements
                                                     target-index))
                                              (let* ((redirect-span
                                                       (list
                                                        (first argument-span)
                                                        (if process-span
                                                            (second process-span)
                                                            (second target-span))))
                                                     (entry
                                                       (make-ast-redirect-entry
                                                        kind descriptor target
                                                        redirect-span
                                                        redirect-order)))
                                                (push entry redirects)
                                                (incf redirect-order)
                                                (setf index
                                                      (if terminator-index
                                                          (1+ terminator-index)
                                                          (+ target-index
                                                             (if process-target
                                                                 2
                                                                 1))))))))))
                                    (multiple-value-bind
                                          (direction process-form process-span)
                                        (%sexp-reader-command-process-substitution-at
                                         elements index)
                                      (if direction
                                          (let* ((process-ast
                                                   (convert-form process-form
                                                                 process-span
                                                                 t
                                                                 t))
                                                 (value
                                                   (%sexp-reader-source-slice
                                                    (first process-span)
                                                    (second process-span)))
                                                 (argument-form
                                                   (make-command-arg
                                                    value nil nil nil
                                                    process-span nil nil))
                                                 (kind
                                                   (if (eq direction :input)
                                                       :process-substitution-input
                                                       :process-substitution-output))
                                                 (target
                                                   (make-redirect-procsub-target
                                                    direction process-ast)))
                                            (push argument-form argument-forms)
                                            (push argument-form arguments)
                                            (push
                                             (make-ast-redirect-entry
                                              kind nil target process-span
                                              redirect-order)
                                             redirects)
                                            (incf redirect-order)
                                            (incf index 2))
                                          (let ((argument-form
                                                  (%sexp-reader-command-argument
                                                   argument argument-span)))
                                            (push argument-form argument-forms)
                                            (when (command-arg-p argument-form)
                                              (push argument-form arguments))
                                            (incf index))))))))
                   (make-command-node
                    command
                    (nreverse arguments)
                    current-span
                    nil
                    nil
                    (nreverse redirects)
                    force-external-p
                    (nreverse argument-forms)
                    nil)))))) (convert-form form span nil t))
)
(defun command-form->ast
    (source form form-span-map head-classifier &key symbol-origins)
  (unless (stringp source)
    (error "Command source must be a string: ~S" source))
  (unless (functionp head-classifier)
    (error "Command head classifier must be a function: ~S" head-classifier))
  (let* ((state (%make-sexp-reader-state :source source))
         (*sexp-reader-state* state)
         (span (and (hash-table-p form-span-map)
                    (gethash form form-span-map))))
    (unless (and (consp span)
                 (integerp (first span))
                 (integerp (second span))
                 (<= 0 (first span) (second span) (length source)))
      (%sexp-reader-command-error
       "The command form must have a valid source span."
       (list 0 0)))
    (handler-case
        (progn
          (setf (%sexp-reader-state-position state) (first span))
          (multiple-value-bind (source-form start end skipped-p)
              (%sexp-reader-read-datum)
            (when (or skipped-p
                      (/= start (first span))
                      (/= end (second span)))
              (%sexp-reader-command-error
               "The source span does not identify exactly one command form."
               span))
            (let ((ast
                    (%sexp-reader-command-convert
                     source-form span head-classifier)))
              (when (hash-table-p symbol-origins)
                (maphash (lambda (symbol origin)
                           (setf (gethash symbol symbol-origins)
                                 (copy-list origin)))
                         (%sexp-reader-state-symbol-origins state)))
              ast)))
      (sexp-reader-error (condition)
        (error condition))
      (error (cause)
        (%sexp-reader-signal cause nil nil span)))))
(defun %sexp-reader-read-character-dispatch (start)
  (%sexp-reader-advance 2)
  (let ((character (%sexp-reader-peek)))
    (unless character
      (%sexp-reader-fail "Character dispatch requires a character name." start))
    (if (%sexp-reader-token-delimiter-p character)
        (progn
          (%sexp-reader-advance)
          (values character start (%sexp-reader-current-position) nil))
        (multiple-value-bind (token token-span)
            (%sexp-reader-read-token)
          (let ((value (if (= (length token) 1)
                           (char token 0)
                           (name-char token))))
            (unless value
              (%sexp-reader-fail "Unknown character name." start))
            (values value start (%sexp-reader-current-position) nil))))))
(defun %sexp-reader-bare-merge-tokens (tokens source)
  (labels ((process-substitution-token-p (token)
             (let ((start (token-start token)))
               (and (eq (token-type token) :word)
                    (< (+ start 1) (length source))
                    (member (char source start) '(#\< #\>))
                    (char= (char source (1+ start)) #\()))))
    (let ((reversed nil))
      (dolist (token tokens)
        (let ((previous (first reversed)))
          (if (and previous
                   (eq (token-type previous) :word)
                   (eq (token-type token) :word)
                   (= (token-end previous) (token-start token))
                   (not (process-substitution-token-p previous))
                   (not (process-substitution-token-p token)))
              (let* ((previous (pop reversed))
                     (fragments (append (token-fragments previous)
                                        (token-fragments token))))
                (push (make-token :word
                                  (concatenate 'string
                                               (token-value previous)
                                               (token-value token))
                                  (token-start previous)
                                  (token-end token)
                                  nil
                                  fragments)
                      reversed))
              (push token reversed))))
      (nreverse reversed))))
(defun %sexp-reader-bare-tokenize (source &optional (offset 0))
  (let* ((tokenization (%tokenize-here-doc-aware source nil))
         (tokens (tokenization-result-tokens tokenization))
         (shifted-tokens
           (mapcar (lambda (token)
                     (if (zerop offset)
                         token
                         (make-token (token-type token)
                                     (token-value token)
                                     (+ offset (token-start token))
                                     (+ offset (token-end token))
                                     (token-quote-style token)
                                     (token-fragments token))))
                   tokens)))
    (when (tokenization-result-incomplete-p tokenization)
      (%sexp-reader-command-error
       "Incomplete bare-line tokenization."
       (list (+ offset (length source)) (+ offset (length source)))))
    (dolist (token shifted-tokens)
      (when (eq (token-type token) :error)
        (%sexp-reader-command-error
         "Invalid or incomplete bare-line token."
         (list (token-start token) (token-end token)))))
    (let ((merged
            (%sexp-reader-bare-merge-tokens
             shifted-tokens (%sexp-reader-state-source *sexp-reader-state*))))
      merged)))
(defun %sexp-reader-bare-value-form (token)
  (let* ((source (%sexp-reader-state-source *sexp-reader-state*))
         (start (token-start token))
         (end (token-end token))
         (fragments (token-fragments token))
         (fragment (first fragments))
         (escaped-zero-p
           (and fragment
                (member 0 (command-fragment-escaped-positions fragment))))
         (double-quoted-prefix-p
           (and (eq (token-quote-style token) :double)
                (= (length fragments) 1)
                (not escaped-zero-p)
                (> (length (token-value token)) 0)
                (member (char-code (char (token-value token) 0)) '(36 44))
                (= (char-code (char source start)) 34)
                (= (char-code (char source (1- end))) 34)))
         (form-start (if double-quoted-prefix-p (1+ start) start))
         (form-end (if double-quoted-prefix-p (1- end) end))
         (first-character
           (and (< form-start form-end) (char source form-start))))
    (when (and first-character
               (member (char-code first-character) '(36 44))
               (not (and escaped-zero-p (not double-quoted-prefix-p))))
      (let ((saved-position (%sexp-reader-current-position)))
        (unwind-protect
             (progn
               (setf (%sexp-reader-state-position *sexp-reader-state*) form-start)
               (multiple-value-bind (wrapper wrapper-start wrapper-end skipped-p)
                   (%sexp-reader-read-datum)
                 (unless (and (not skipped-p)
                              (= wrapper-start form-start)
                              (= wrapper-end form-end)
                              (consp wrapper))
                   (%sexp-reader-command-error
                    "A bare-line value token must contain exactly one reader prefix."
                    (list start end)))
                 (let ((head-name
                         (%sexp-reader-command-form-name (first wrapper))))
                   (cond
                     ((string-equal (or head-name "") "UNQUOTE-SPLICING")
                      (make-command-value-form :splice (second wrapper)
                                               (list start end)))
                     ((string-equal (or head-name "") "UNQUOTE")
                      (make-command-value-form :value (second wrapper)
                                               (list start end)))
                     (t
                      (%sexp-reader-command-error
                       "A bare-line value prefix must be $ or comma."
                       (list start end)))))))
          (setf (%sexp-reader-state-position *sexp-reader-state*)
                saved-position)))))
)
(defun %sexp-reader-bare-argument (token)
  (let* ((span (list (token-start token) (token-end token)))
         (value-form (%sexp-reader-bare-value-form token))
         (fragments (token-fragments token))
         (quote-style (token-quote-style token))
         (expand-p
           (and (null quote-style)
                (every (lambda (fragment)
                         (and (null (command-fragment-quote-style fragment))
                              (null
                               (command-fragment-escaped-positions fragment))))
                       fragments))))
    (or value-form
        (make-command-arg (token-value token)
                          quote-style
                          nil
                          fragments
                          span
                          (null quote-style)
                          expand-p))))
(defun %sexp-reader-bare-pipeline-from-tokens (tokens &optional process-substitution-p)
  (let ((stage-reversed nil)
        (commands-reversed nil)
        (edges-reversed nil)
        (pending-pipe nil))
    (dolist (token tokens)
      (cond
        ((eq (token-type token) :pipe)
         (unless stage-reversed
           (%sexp-reader-command-error
            "A pipeline separator requires a command on its left."
            (list (token-start token) (token-end token))))
         (push (%sexp-reader-bare-command-from-tokens
                (nreverse stage-reversed) process-substitution-p)
               commands-reversed)
         (push (make-pipeline-edge
                (if (string= (token-value token) "|&")
                    :pipe-stderr-to-stdout
                    :pipe)
                (list (token-start token) (token-end token)))
               edges-reversed)
         (setf stage-reversed nil
               pending-pipe token))
        ((member (token-type token)
                 (list :word :redirect)
                 :test (function eq))
         (push token stage-reversed)
         (setf pending-pipe nil))
        (t
         (%sexp-reader-command-error
          "A process-substitution command cannot contain a sequence separator."
          (list (token-start token) (token-end token))))))
    (when (null stage-reversed)
      (%sexp-reader-command-error
       "A pipeline separator requires a command on its right."
       (if pending-pipe
           (list (length (%sexp-reader-state-source *sexp-reader-state*))
                 (length (%sexp-reader-state-source *sexp-reader-state*)))
           (list 0 0))))
    (push (%sexp-reader-bare-command-from-tokens
           (nreverse stage-reversed) process-substitution-p)
          commands-reversed)
    (let* ((commands (nreverse commands-reversed))
           (edges (nreverse edges-reversed)))
      (if (rest commands)
          (make-pipeline-node
           commands
           (list (first (ast-node-span (first commands)))
                 (second (ast-node-span (car (last commands)))))
           edges)
          (first commands)))))
(defun %sexp-reader-bare-unquoted-word-p (token)
  (let ((fragments (token-fragments token))
        (source (%sexp-reader-state-source *sexp-reader-state*)))
    (and (eq (token-type token) :word)
         (= (length fragments) 1)
         (null (command-fragment-quote-style (first fragments)))
         (null (command-fragment-escaped-positions (first fragments)))
         (string= (token-value token)
                  (subseq source (token-start token) (token-end token))))))
(defun %sexp-reader-bare-assignment-count (tokens)
  (let ((count
          (loop for token in tokens
                while (and (%sexp-reader-bare-unquoted-word-p token)
                           (shell-assignment-word-p (token-value token)))
                count t)))
    (if (= count (length tokens)) 0 count)))
(defun %sexp-reader-bare-command-head (token)
  (let* ((fragments (copy-list (token-fragments token)))
         (first-fragment (first fragments))
         (escaped-positions
           (and first-fragment
                (command-fragment-escaped-positions first-fragment)))
         (force-external-p
           (and first-fragment
                (null (command-fragment-quote-style first-fragment))
                (plusp (length (command-fragment-value first-fragment)))
                (char= (char (command-fragment-value first-fragment) 0) #\^)
                (not (member 0 escaped-positions))))
         (command (token-value token)))
    (when force-external-p
      (setf command (subseq command 1)
            fragments
            (append
             (let* ((value (command-fragment-value first-fragment))
                    (trimmed (subseq value 1))
                    (remaining-escaped-positions
                      (loop for position in escaped-positions
                            when (plusp position)
                              collect (1- position))))
               (when (plusp (length trimmed))
                 (list (make-command-fragment trimmed nil
                                              remaining-escaped-positions))))
             (rest fragments))))
    (unless (plusp (length command))
      (%sexp-reader-command-error
       "The ^ marker requires an adjacent command name."
       (list (token-start token) (token-end token))))
    (values command
            force-external-p
            (token-quote-style token)
            fragments)))
(defun %sexp-reader-bare-process-substitution-p (token)
  (let* ((start (token-start token))
         (end (token-end token))
         (source (%sexp-reader-state-source *sexp-reader-state*)))
    (and (eq (token-type token) :word)
         (<= (+ start 3) end)
         (member (char source start) '(#\< #\>))
         (char= (char source (1+ start)) #\()
         (char= (char source (1- end)) #\))))) (defun %sexp-reader-bare-process-substitution (token nested-p)
  (when (%sexp-reader-bare-process-substitution-p token)
    (when nested-p
      (%sexp-reader-command-error
       "Nested process substitutions are not supported."
       (list (token-start token) (token-end token))))
    (let* ((source (%sexp-reader-state-source *sexp-reader-state*))
           (start (token-start token))
           (end (token-end token))
           (inner-start (+ start 2))
           (inner-end (1- end))
           (inner-source (subseq source inner-start inner-end))
           (tokens (%sexp-reader-bare-tokenize inner-source inner-start))
           (form (%sexp-reader-bare-pipeline-from-tokens tokens t)))
      (values (if (char= (char source start) #\<) :input :output)
              form
              (list start end))))
) (defun %sexp-reader-bare-inline-fd-target (operator span)
  (let ((separator (or (search "<&" operator :from-end t)
                       (search ">&" operator :from-end t))))
    (when separator
      (let ((target-start (+ separator 2)))
        (when (< target-start (length operator))
          (let ((target (subseq operator target-start)))
            (cond
              ((string= target "-")
               (values (make-redirect-fd-close-target) t))
              ((and (plusp (length target))
                    (every #'digit-char-p target))
               (values (make-redirect-fd-target (parse-integer target)) t))
              (t
               (%sexp-reader-command-error
                "Descriptor duplication requires a decimal descriptor or -."
                span))))))))
) (defun %sexp-reader-bare-heredoc-target (token kind)
  (let* ((source (%sexp-reader-state-source *sexp-reader-state*))
         (span (list (token-start token) (token-end token)))
         (raw (%sexp-reader-source-slice (first span) (second span)))
         (delimiter-tokens (tokenization-result-tokens (tokenize raw)))
         (delimiter-token (first delimiter-tokens)))
    (unless (and (= (length delimiter-tokens) 1)
                 (eq (token-type delimiter-token) :word))
      (%sexp-reader-command-error
       "A here-document requires one word delimiter."
       span))
    (let* ((delimiter (token-value delimiter-token))
           (strip-tabs-p (eq kind :here-document-strip-tabs))
           (quoted-p
             (or (token-quote-style delimiter-token)
                 (some #'command-fragment-escaped-positions
                       (token-fragments delimiter-token))))
           (header-newline (position #\Newline source :start (second span))))
      (unless header-newline
        (%sexp-reader-command-error
         "A here-document delimiter requires a following body."
         span))
      (let* ((body-start (1+ header-newline))
             (body-result
               (%consume-here-doc-body source body-start
                                       (cons delimiter strip-tabs-p)))
             (terminator-start
               (loop with line-start = body-start
                     for line-end = (%line-end-position source line-start)
                     for line = (subseq source line-start line-end)
                     for normalized-line =
                       (if strip-tabs-p
                           (string-left-trim '(#\Tab) line)
                           line)
                     when (string= normalized-line delimiter)
                       return line-start
                     when (= line-end (length source))
                       return nil
                     do (setf line-start (1+ line-end)))))
        (when (%here-doc-body-missing-delimiter-p body-result)
          (%sexp-reader-command-error
           "A here-document delimiter was not found."
           (list (length source) (length source))))
        (unless terminator-start
          (%sexp-reader-command-error
           "A here-document delimiter was not found."
           (list (length source) (length source))))
        (let* ((terminator-end (%here-doc-body-next-position body-result))
               (delimiter-argument
                 (make-command-arg
                  delimiter
                  (token-quote-style delimiter-token)
                  quoted-p
                  (token-fragments delimiter-token)
                  span
                  nil
                  nil)))
          (values (make-redirect-heredoc-target
                   delimiter-argument
                   (subseq source body-start terminator-start)
                   (not quoted-p)
                   strip-tabs-p
                   (list body-start terminator-start))
                  terminator-end)))))
) (defun %sexp-reader-bare-fd-target (token span)
  (unless (eq (token-type token) :word)
    (%sexp-reader-command-error
     "A descriptor redirect requires a word target."
     span))
  (let ((value (token-value token)))
    (cond
      ((string= value "-")
       (make-redirect-fd-close-target))
      ((and (plusp (length value))
            (every #'digit-char-p value))
       (make-redirect-fd-target (parse-integer value)))
      (t
       (%sexp-reader-command-error
        "Descriptor duplication requires a decimal descriptor or -."
        (list (token-start token) (token-end token))))))
) (defun %sexp-reader-bare-redirect-entry
    (tokens index source-order process-substitution-p)
  (let* ((operator-token (nth index tokens))
         (operator (token-value operator-token))
         (operator-span (list (token-start operator-token)
                              (token-end operator-token))))
    (multiple-value-bind (kind descriptor)
        (%sexp-reader-command-redirect-spec operator t)
      (unless kind
        (%sexp-reader-command-error "Unsupported redirect operator."
                                    operator-span))
      (multiple-value-bind (inline-target inline-p)
          (%sexp-reader-bare-inline-fd-target operator operator-span)
        (when (and inline-p
                   (not (member kind
                                '(:duplicate-input-fd :duplicate-output-fd))))
          (%sexp-reader-command-error
           "Only descriptor redirects accept inline targets."
           operator-span))
        (if inline-p
            (values
             (make-ast-redirect-entry kind descriptor inline-target
                                      operator-span source-order)
             (1+ index)
             (token-end operator-token))
            (let ((target-index (1+ index)))
              (when (>= target-index (length tokens))
                (%sexp-reader-command-error
                 "A redirect requires a target."
                 operator-span))
              (let* ((target-token (nth target-index tokens))
                     (target-span (list (token-start target-token)
                                        (token-end target-token)))
                     (redirect-span (list (token-start operator-token)
                                          (token-end target-token)))
                     (target nil)
                     (covered-end (token-end target-token)))
                (unless (eq (token-type target-token) :word)
                  (%sexp-reader-command-error
                   "A redirect requires a word target."
                   target-span))
                (cond
                  ((member kind
                           '(:here-document :here-document-strip-tabs))
                   (multiple-value-setq (target covered-end)
                     (%sexp-reader-bare-heredoc-target target-token kind)))
                  ((member kind '(:duplicate-input-fd :duplicate-output-fd))
                   (setf target
                         (%sexp-reader-bare-fd-target target-token target-span)))
                  (t
                   (multiple-value-bind (direction process-form process-span)
                       (%sexp-reader-bare-process-substitution
                        target-token process-substitution-p)
                     (if direction
                         (progn
                           (unless
                               (or (and (eq kind :input-file)
                                        (eq direction :input))
                                   (and
                                    (member kind
                                     '(:output-file :append-output-file
                                       :force-output-file :error-file
                                       :append-error-file :both-output-files
                                       :append-both-output-files))
                                    (eq direction :output)))
                             (%sexp-reader-command-error
                              "Process-substitution direction does not match the redirect."
                              process-span))
                           (setf target
                                 (make-redirect-procsub-target
                                  direction process-form)))
                         (setf target
                               (%sexp-reader-bare-argument target-token)))
                     (unless (command-arg-p target)
                       (%sexp-reader-command-error
                        "A redirect target must be a source token."
                        target-span)))))
                (values
                 (make-ast-redirect-entry kind descriptor target
                                          redirect-span source-order)
                 (1+ target-index)
                 covered-end)))))))) (defun %sexp-reader-bare-command-from-tokens
    (tokens &optional process-substitution-p)
  (unless (and tokens (eq (token-type (first tokens)) :word))
    (%sexp-reader-command-error
     "A bare-line command requires a word command head."
     (if tokens
         (list (token-start (first tokens)) (token-end (first tokens)))
         (list 0 0))))
  (let* ((assignment-candidate-count
           (%sexp-reader-bare-assignment-count tokens))
         (assignment-count
           (if (and (plusp assignment-candidate-count)
                    (< assignment-candidate-count (length tokens))
                    (eq (token-type (nth assignment-candidate-count tokens))
                        :word))
               assignment-candidate-count
               0))
         (command-token (nth assignment-count tokens)))
    (unless (and command-token (eq (token-type command-token) :word))
      (%sexp-reader-command-error
       "Environment assignments must precede a word command head."
       (if command-token
           (list (token-start command-token) (token-end command-token))
           (list 0 0))))
    (when (%sexp-reader-bare-process-substitution-p command-token)
      (%sexp-reader-command-error
       "A process substitution cannot be a command head."
       (list (token-start command-token) (token-end command-token))))
    (multiple-value-bind (command force-external-p command-quote-style
                         command-fragments)
        (%sexp-reader-bare-command-head command-token)
      (let ((arguments nil)
            (argument-forms nil)
            (environment-assignments nil)
            (redirects nil)
            (redirect-order 0)
            (command-start
              (token-start (if (plusp assignment-count)
                               (first tokens)
                               command-token)))
            (command-end (token-end command-token))
            (index (1+ assignment-count)))
        (loop for token in (subseq tokens 0 assignment-count)
              do (push (make-command-arg
                        (token-value token)
                        (token-quote-style token)
                        nil
                        (token-fragments token)
                        (list (token-start token) (token-end token))
                        nil
                        nil)
                       environment-assignments))
        (setf environment-assignments (nreverse environment-assignments))
        (loop while (< index (length tokens))
              for token = (nth index tokens)
              for next-index = (1+ index)
              do (cond
                   ((eq (token-type token) :redirect)
                    (multiple-value-bind (entry following-index covered-end)
                        (%sexp-reader-bare-redirect-entry
                         tokens index redirect-order process-substitution-p)
                      (push entry redirects)
                      (incf redirect-order)
                      (setf next-index following-index
                            command-end (max command-end covered-end))))
                   ((eq (token-type token) :word)
                    (multiple-value-bind (direction form source-span)
                        (%sexp-reader-bare-process-substitution
                         token process-substitution-p)
                      (if direction
                          (let* ((value (%sexp-reader-source-slice
                                         (first source-span)
                                         (second source-span)))
                                 (argument
                                   (make-command-arg value nil nil nil
                                                     source-span nil nil))
                                 (kind
                                   (if (eq direction :input)
                                       :process-substitution-input
                                       :process-substitution-output)))
                            (push argument argument-forms)
                            (push argument arguments)
                            (push (make-ast-redirect-entry
                                   kind nil
                                   (make-redirect-procsub-target direction form)
                                   source-span redirect-order)
                                  redirects)
                            (incf redirect-order)
                            (setf command-end (max command-end
                                                   (second source-span))))
                          (let ((argument (%sexp-reader-bare-argument token)))
                            (push argument argument-forms)
                            (when (command-arg-p argument)
                              (push argument arguments))
                            (setf command-end
                                  (max command-end (token-end token)))))))
                   (t
                    (%sexp-reader-command-error
                     "Unexpected token in a bare-line command."
                     (list (token-start token) (token-end token)))))
                 (setf index next-index))
        (make-command-node
         command
         (nreverse arguments)
         (list command-start command-end)
         command-quote-style
         command-fragments
         (nreverse redirects)
         force-external-p
         (nreverse argument-forms)
         environment-assignments))))
) (defun %sexp-reader-read-bare-line (source)
  (let ((tokens (%sexp-reader-bare-tokenize source))
        (segment-reversed nil)
        (commands-reversed nil)
        (separators-reversed nil)
        (last-separator-end nil)
        (background-semicolon-allowed-p nil))
    (labels ((finish-segment (separator)
               (when (null segment-reversed)
                 (%sexp-reader-command-error
                  "A bare-line separator requires a command on its left."
                  (list 0 0)))
               (push (%sexp-reader-bare-pipeline-from-tokens
                      (nreverse segment-reversed))
                     commands-reversed)
               (setf segment-reversed nil)
               (when separator
                 (push separator separators-reversed)))
             (last-segment-token ()
               (first segment-reversed))
             (continuation-newline-p ()
               (let ((token (last-segment-token)))
                 (and token
                      (or (eq (token-type token) :pipe)
                          (and (eq (token-type token) :redirect)
                               (not (%redirect-targetless-p
                                     (token-value token))))))))
             (separator-error (token message)
               (%sexp-reader-command-error
                message
                (list (token-start token) (token-end token))))
             (record-separator (token separator)
               (unless segment-reversed
                 (separator-error
                  token
                  "A bare-line separator requires a command on its left."))
               (finish-segment separator)
               (setf background-semicolon-allowed-p nil last-separator-end (token-end token))))
      (dolist (token tokens)
        (case (token-type token)
          ((:word :redirect :pipe)
           (setf background-semicolon-allowed-p nil)
           (push token segment-reversed))
          (:newline
           (setf background-semicolon-allowed-p nil)
           (unless (or (null segment-reversed)
                       (continuation-newline-p))
             (finish-segment :semi)))
          (:semicolon
           (if (and (null segment-reversed)
                    background-semicolon-allowed-p)
               (setf background-semicolon-allowed-p nil
                     last-separator-end (token-end token))
               (record-separator token :semi)))
          (:and
           (record-separator token :and))
          (:or
           (record-separator token :or))
          (:ampersand
           (record-separator token :amp)
           (setf background-semicolon-allowed-p t))
          (otherwise
           (separator-error token "Unsupported bare-line token."))))
      (when segment-reversed
        (finish-segment nil)))
    (let ((commands (nreverse commands-reversed))
          (separators (nreverse separators-reversed)))
      (when (and commands
                 (= (length separators) (length commands))
                 (eq (car (last separators)) :semi))
        (setf separators (butlast separators)))
      (when (and separators
                 (= (length separators) (length commands))
                 (member (car (last separators)) '(:and :or) :test #'eq))
        (%sexp-reader-command-error
         "A trailing && or || requires a command on its right."
         (list (length source) (length source))))
      (unless (or (= (length separators) (length commands))
                  (= (length separators) (1- (length commands))))
        (%sexp-reader-command-error
         "Invalid bare-line sequence separators."
         (list (length source) (length source))))
      (cond
        ((null commands)
         (values nil nil))
        ((null separators)
         (let ((node (first commands)))
           (values node (ast-node-span node))))
        (t
         (let* ((terminal-background-p
                  (and (= (length separators) (length commands))
                       (eq (car (last separators)) :amp)))
                (span
                  (list (first (ast-node-span (first commands)))
                        (if terminal-background-p
                            last-separator-end
                            (second
                             (ast-node-span (car (last commands)))))))
                (node (make-sequence-node commands separators span)))
           (values node span))))))
)
