(in-package #:nshell.domain.expansion)

(defparameter +argv-reference-name+ "argv")

(defun %parse-argv-index (text &optional default)
  (if (string= text "")
      default
      (ignore-errors (parse-integer text :junk-allowed nil))))

(defun %list-selection-spec (spec)
  (let ((range-pos (search ".." spec)))
    (if range-pos
        (%make-list-selection-spec
         :range
         (%parse-argv-index (subseq spec 0 range-pos) 1)
         (%parse-argv-index (subseq spec (+ range-pos 2)) -1))
        (%make-list-selection-spec
         :index
         (%parse-argv-index spec)
         nil))))

(defun %argv-normalized-index (index count)
  (cond
    ((null index) nil)
    ((zerop index) nil)
    ((minusp index) (+ count index))
    (t (1- index))))

(defun %list-index-field (fields index)
  (let* ((count (length fields))
         (normalized (%argv-normalized-index index count)))
    (when (and normalized (<= 0 normalized) (< normalized count))
      (list (nth normalized fields)))))

(defun %list-range-fields (fields start-index end-index)
  (let* ((count (length fields))
         (raw-start (%argv-normalized-index start-index count))
         (raw-end (%argv-normalized-index end-index count)))
    (when (and (plusp count) raw-start raw-end)
      (flet ((valid-index-p (index)
               (and (<= 0 index) (< index count)))
             (clamp-index (index)
               (max 0 (min (1- count) index))))
        (let* ((same-sign-p
                 (or (and (plusp start-index) (plusp end-index))
                     (and (minusp start-index) (minusp end-index))))
               (start (if (valid-index-p raw-start)
                          raw-start
                          (and same-sign-p (clamp-index raw-start))))
               (end (if (valid-index-p raw-end)
                        raw-end
                        (and same-sign-p (clamp-index raw-end)))))
          (when (and start end)
            (let ((step (if (<= start end) 1 -1))
                  (result nil))
              (loop for index = start then (+ index step)
                    do (push (nth index fields) result)
                    until (= index end))
              (nreverse result))))))))

(defun %list-selection-spec-fields (fields selection)
  (case (list-selection-spec-kind selection)
    (:range (%list-range-fields fields
                                (list-selection-spec-start-index selection)
                                (list-selection-spec-end-index selection)))
    (:index (%list-index-field fields
                               (list-selection-spec-start-index selection)))
    (otherwise nil)))

(defun %list-spec-fields (fields spec)
  (let ((selection-specs (%split-whitespace-fields spec)))
    (if selection-specs
        (loop for selection-spec in selection-specs
              append (%list-selection-spec-fields
                      fields
                      (%list-selection-spec selection-spec)))
        (%list-selection-spec-fields fields (%list-selection-spec spec)))))

(defun %argv-spec-fields (spec)
  (%list-spec-fields *positional-args* spec))

(defun %variable-list-fields (name env)
  (if (string= name +argv-reference-name+)
      (copy-list *positional-args*)
      (nshell.domain.environment:env-get-values env name)))

(defun %variable-spec-fields (name spec env)
  (%list-spec-fields (%variable-list-fields name env) spec))

(defun %join-fields (fields)
  (format nil "~{~a~^ ~}" fields))

(defmacro %with-variable-reference-dispatch ((reference fields next
                                              indexed-form unindexed-form)
                                             &body body)
  (let ((reference-value (gensym "REFERENCE-")))
    `(let ((,reference-value ,reference))
       (unless (%variable-reference-unbalanced-p ,reference-value)
         (let ((,fields (if (%variable-reference-indexed-p ,reference-value)
                            ,indexed-form
                            ,unindexed-form))
               (,next (%variable-reference-next-index ,reference-value)))
           ,@body)))))

(defmacro %with-scanned-variable-reference ((reference input start len) &body body)
  `(let ((,reference (%variable-reference-syntax-at ,input ,start ,len)))
     (when ,reference
       ,@body)))

(defun %argv-reference-p (reference)
  (string= (variable-reference-syntax-name reference) +argv-reference-name+))

(defun %scan-variable-reference-name (input start len)
  "Return (values name name-end recognized-p) for the identifier after $ at START."
  (when (and (< (1+ start) len)
             (variable-name-start-p (char input (1+ start))))
    (let* ((name-start (1+ start))
           (name-end (loop for j from name-start below len
                           while (variable-name-char-p (char input j))
                           finally (return j)))
           (name (subseq input name-start name-end)))
      (values name name-end t))))

(defun %bracket-spec-after-name (input name-end len)
  "Return (values spec next-index status) for optional [SPEC] after NAME-END.
STATUS is :INDEXED for a balanced bracket, :UNBALANCED for '[' without ']',
or NIL when no bracket starts at NAME-END."
  (when (and (< name-end len) (char= (char input name-end) #\[))
    (let ((close (position #\] input :start (1+ name-end))))
      (if close
          (values (subseq input (1+ name-end) close)
                  (1+ close)
                  :indexed)
          (values nil name-end :unbalanced)))))

(defun %variable-reference-syntax-after-name (name input name-end len)
  "Project a scanned variable name and optional bracket into a reference value."
  (multiple-value-bind (spec next status)
      (%bracket-spec-after-name input name-end len)
    (%make-variable-reference-syntax name name-end spec next status)))

(defun %variable-reference-syntax-at (input start len)
  "Return a variable-reference-syntax for a recognized $NAME at START."
  (multiple-value-bind (name name-end recognized-p)
      (%scan-variable-reference-name input start len)
    (when recognized-p
      (%variable-reference-syntax-after-name name input name-end len))))

(defun %variable-reference-indexed-p (reference)
  (eq :indexed (variable-reference-syntax-bracket-status reference)))

(defun %variable-reference-unbalanced-p (reference)
  (eq :unbalanced (variable-reference-syntax-bracket-status reference)))

(defun %variable-reference-next-index (reference)
  (if (%variable-reference-indexed-p reference)
      (variable-reference-syntax-bracket-next reference)
      (variable-reference-syntax-name-end reference)))

(defmacro %reference-fields-for-syntax ((reference) indexed-form unindexed-form)
  `(%with-variable-reference-dispatch (,reference fields next
                                       ,indexed-form
                                       ,unindexed-form)
     (values fields next)))

(defun argv-reference-fields (value)
  "Return (values fields recognized-p) for an exact fish-style $argv reference.
$argv returns all positional arguments, $argv[N] returns one 1-based argument,
negative indexes count from the end, and $argv[A..B] returns an inclusive range."
  (cond
    ((string= value "$argv")
     (values (copy-list *positional-args*) t))
    ((and (> (length value) 7)
          (string= value "$argv[" :end1 6)
          (char= (char value (1- (length value))) #\]))
     (values (%argv-spec-fields (subseq value 6 (1- (length value)))) t))
    (t
     (values nil nil))))

(defun %argv-expansion-after-name (input name-end len)
  "Return (values expansion next-index) for a scanned $argv reference."
  (let ((reference (%variable-reference-syntax-after-name "argv" input name-end len)))
    (multiple-value-bind (fields next)
        (%reference-fields-for-syntax (reference)
          (%argv-spec-fields
           (variable-reference-syntax-bracket-spec reference))
          *positional-args*)
      (values (%join-fields fields) next))))

(defun %variable-expansion-after-name (input name env name-end len)
  "Return (values expansion next-index) for a scanned normal variable reference."
  (let ((reference (%variable-reference-syntax-after-name name input name-end len)))
    (multiple-value-bind (value next)
        (%reference-fields-for-syntax (reference)
          (%join-fields
           (%variable-spec-fields
            name
            (variable-reference-syntax-bracket-spec reference)
            env))
          (or (nshell.domain.environment:env-get env name) ""))
      (values value next))))

(defun %variable-reference-at (input start len env)
  "Return (values fields next-index recognized-p) for a list variable reference."
  (%with-scanned-variable-reference (reference input start len)
    (if (%argv-reference-p reference)
        (multiple-value-bind (fields next)
            (%reference-fields-for-syntax (reference)
              (%argv-spec-fields
               (variable-reference-syntax-bracket-spec reference))
              (copy-list *positional-args*))
          (values fields next t))
        (let ((name (variable-reference-syntax-name reference)))
          (multiple-value-bind (fields next)
              (%reference-fields-for-syntax (reference)
                (%variable-spec-fields
                 name
                 (variable-reference-syntax-bracket-spec reference)
                 env)
                (nshell.domain.environment:env-get-values env name))
            (values fields next t))))))

(defun %expand-variable-reference (input start len env)
  "Return (values expansion next-index) for a bare variable reference at START."
  (%with-scanned-variable-reference (reference input start len)
    (if (%argv-reference-p reference)
        (%argv-expansion-after-name
         input
         (variable-reference-syntax-name-end reference)
         len)
        (%variable-expansion-after-name
         input
         (variable-reference-syntax-name
          reference)
         env
         (variable-reference-syntax-name-end reference)
         len))))
