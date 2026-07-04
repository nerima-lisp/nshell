(in-package #:nshell.domain.expansion)

(defvar *positional-args* nil
  "List of function arguments used to expand the fish-style $argv and $argv[N].
Bound dynamically by the function-call machinery for the duration of a function
body; NIL at top level.")

(defun %parse-argv-index (text &optional default)
  (if (string= text "")
      default
      (ignore-errors (parse-integer text :junk-allowed nil))))

(defstruct (list-selection-spec
            (:constructor %make-list-selection-spec (kind start-index end-index)))
  (kind :index :type keyword :read-only t)
  (start-index nil :read-only t)
  (end-index nil :read-only t))

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
         (start (%argv-normalized-index start-index count))
         (end (%argv-normalized-index end-index count)))
    (when (and start end)
      (let ((step (if (<= start end) 1 -1))
            (result nil))
        (loop for index = start then (+ index step)
              do (when (and (<= 0 index) (< index count))
                   (push (nth index fields) result))
              until (= index end))
        (nreverse result)))))

(defun %list-selection-spec-fields (fields selection)
  (case (list-selection-spec-kind selection)
    (:range (%list-range-fields fields
                                (list-selection-spec-start-index selection)
                                (list-selection-spec-end-index selection)))
    (:index (%list-index-field fields
                               (list-selection-spec-start-index selection)))
    (otherwise nil)))

(defun %list-spec-fields (fields spec)
  (%list-selection-spec-fields fields (%list-selection-spec spec)))

(defun %argv-spec-fields (spec)
  (%list-spec-fields *positional-args* spec))

(defun %variable-list-fields (name env)
  (if (string= name "argv")
      (copy-list *positional-args*)
      (nshell.domain.environment:env-get-values env name)))

(defun %variable-spec-fields (name spec env)
  (%list-spec-fields (%variable-list-fields name env) spec))

(defun %join-fields (fields)
  (format nil "~{~a~^ ~}" fields))

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

(defstruct (variable-reference-syntax
            (:constructor %make-variable-reference-syntax
                (name name-end bracket-spec bracket-next bracket-status)))
  (name "" :type string :read-only t)
  (name-end 0 :type fixnum :read-only t)
  (bracket-spec nil :read-only t)
  (bracket-next nil :read-only t)
  (bracket-status nil :read-only t))

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
    (if (%variable-reference-indexed-p reference)
        (values (%join-fields
                 (%argv-spec-fields
                  (variable-reference-syntax-bracket-spec reference)))
                (%variable-reference-next-index reference))
        (values (%join-fields *positional-args*)
                (%variable-reference-next-index reference)))))

(defun %variable-expansion-after-name (input name env name-end len)
  "Return (values expansion next-index) for a scanned normal variable reference."
  (let ((reference (%variable-reference-syntax-after-name name input name-end len)))
    (if (%variable-reference-indexed-p reference)
         (values (%join-fields
                  (%variable-spec-fields
                   name
                   (variable-reference-syntax-bracket-spec reference)
                   env))
                (%variable-reference-next-index reference))
        (values (or (nshell.domain.environment:env-get env name) "")
                (%variable-reference-next-index reference)))))

(defun %argv-reference-fields-for-syntax (reference)
  "Return list-reference values for a parsed $argv syntax object."
  (unless (%variable-reference-unbalanced-p reference)
    (if (%variable-reference-indexed-p reference)
        (values (%argv-spec-fields
                 (variable-reference-syntax-bracket-spec reference))
                (%variable-reference-next-index reference)
                t)
        (values (copy-list *positional-args*)
                (%variable-reference-next-index reference)
                t))))

(defun %argv-reference-at (input start len)
  "Return (values fields next-index recognized-p) for a $argv reference at START."
  (let ((reference (%variable-reference-syntax-at input start len)))
    (when (and reference
               (string= (variable-reference-syntax-name reference) "argv"))
      (%argv-reference-fields-for-syntax reference))))

(defun %variable-reference-at (input start len env)
  "Return (values fields next-index recognized-p) for a list variable reference."
  (let ((reference (%variable-reference-syntax-at input start len)))
    (when reference
      (let ((name (variable-reference-syntax-name reference)))
        (cond
          ((string= name "argv")
           (%argv-reference-fields-for-syntax reference))
          ((%variable-reference-unbalanced-p reference)
           nil)
          ((%variable-reference-indexed-p reference)
           (values (%variable-spec-fields
                    name
                    (variable-reference-syntax-bracket-spec reference)
                    env)
                   (%variable-reference-next-index reference)
                   t))
           (t
            (let ((fields (nshell.domain.environment:env-get-values env name)))
              (when fields
                (values fields
                        (%variable-reference-next-index reference)
                        t)))))))))

(defun %expand-variable-reference (input start len env)
  "Return (values expansion next-index) for a bare variable reference at START."
  (let ((reference (%variable-reference-syntax-at input start len)))
    (when reference
      (let ((name (variable-reference-syntax-name reference)))
        (if (string= name "argv")
            (%argv-expansion-after-name
             input
             (variable-reference-syntax-name-end reference)
             len)
            (%variable-expansion-after-name
             input
             name
             env
             (variable-reference-syntax-name-end reference)
             len))))))

(defun expand-variables (input env)
  "Expand $VAR and ${VAR} occurrences in INPUT using ENV. Also expands the
fish-style argument list $argv and indexed $argv[N] from *POSITIONAL-ARGS*
\(bare $argv joins with spaces here; a bare unquoted $argv is split into separate
words by the argument expander). POSIX positional $1..$9 are NOT special and stay
literal, matching fish. Undefined variables expand to the empty string."
  (with-output-to-string (out)
    (loop with len = (length input)
          for i from 0 below len
          for ch = (char input i)
          do (cond
               ((char/= ch #\$) (write-char ch out))
               ((>= (1+ i) len) (write-char ch out))
               ((char= (char input (1+ i)) #\{)
                (let ((end (position #\} input :start (+ i 2))))
                  (if end
                      (progn
                        (write-string
                         (%expand-braced-parameter (subseq input (+ i 2) end) env)
                         out)
                        (setf i end))
                      (write-char ch out))))
               ((variable-name-start-p (char input (1+ i)))
                (multiple-value-bind (element next)
                    (%expand-variable-reference input i len env)
                  (if element
                      (progn
                        (write-string element out)
                        (setf i (1- next)))
                      (write-char ch out))))
               (t (write-char ch out))))))

(defun %string-replace (value old new global)
  "Replace OLD (a literal substring) with NEW in VALUE, the first occurrence only
unless GLOBAL is true."
  (if (zerop (length old))
      value
      (with-output-to-string (out)
        (loop with start = 0
              for pos = (search old value :start2 start)
              while pos
              do (write-string (subseq value start pos) out)
                 (write-string new out)
                 (setf start (+ pos (length old)))
                 (unless global
                   (write-string (subseq value start) out)
                   (return))
              finally (write-string (subseq value start) out)))))

(defun %param-strip-prefix (value rest env)
  "Strip a glob-matching prefix from VALUE. REST is the text after the first #;
a further leading # selects the longest match instead of the shortest."
  (let* ((longest (and (plusp (length rest)) (char= (char rest 0) #\#)))
         (pattern (expand-variables (subseq rest (if longest 1 0)) env)))
    (if (zerop (length pattern))
        value
        (dolist (i (if longest
                       (loop for i from (length value) downto 0 collect i)
                       (loop for i from 0 to (length value) collect i))
                   value)
          (when (glob-match-p pattern (subseq value 0 i))
            (return (subseq value i)))))))

(defun %param-strip-suffix (value rest env)
  "Strip a glob-matching suffix from VALUE. REST is the text after the first %;
a further leading % selects the longest match instead of the shortest."
  (let* ((longest (and (plusp (length rest)) (char= (char rest 0) #\%)))
         (pattern (expand-variables (subseq rest (if longest 1 0)) env))
         (len (length value)))
    (if (zerop (length pattern))
        value
        (dolist (i (if longest
                       (loop for i from 0 to len collect i)
                       (loop for i from len downto 0 collect i))
                   value)
          (when (glob-match-p pattern (subseq value i))
            (return (subseq value 0 i)))))))

(defun %param-substitute (value rest env)
  "Substitute within VALUE for ${VAR/pat/rep}. REST is the text after the first
/; a further leading / replaces all occurrences. PAT is matched literally."
  (let* ((global (and (plusp (length rest)) (char= (char rest 0) #\/)))
         (body (subseq rest (if global 1 0)))
         (slash (position #\/ body))
         (pat (expand-variables (if slash (subseq body 0 slash) body) env))
         (rep (expand-variables (if slash (subseq body (1+ slash)) "") env)))
    (%string-replace value pat rep global)))

(defun %assign-parameter-default (env name value)
  "Assign VALUE to NAME in ENV for ${NAME:=word}, preserving export state."
  (nshell.domain.environment:env-assign-default! env name value))

(defun %expand-parameter-length (content env)
  "Return the string length of ${#NAME} when CONTENT starts with # followed by a bare name.
Returns NIL when CONTENT is not a length expansion."
  (when (and (plusp (length content))
             (char= (char content 0) #\#)
             (every #'variable-name-char-p (subseq content 1)))
    (let ((value (nshell.domain.environment:env-get env (subseq content 1))))
      (princ-to-string (length (or value ""))))))

(defstruct (parameter-binding
            (:constructor %make-parameter-binding (name raw set-p value)))
  (name "" :type string :read-only t)
  (raw nil :read-only t)
  (set-p nil :read-only t)
  (value "" :type string :read-only t))

(defun %parameter-binding (name env)
  (let ((raw (nshell.domain.environment:env-get env name)))
    (%make-parameter-binding name raw (not (null raw)) (or raw ""))))

(defstruct (parameter-operator
            (:constructor %make-parameter-operator (op word-text colon-p)))
  (op nil :read-only t)
  (word-text "" :type string :read-only t)
  (colon-p nil :read-only t))

(defun %parameter-operator-parts (rest)
  "Parse REST into a braced parameter operator value."
  (let* ((colon-p (and (plusp (length rest)) (char= (char rest 0) #\:)))
         (op-index (if colon-p 1 0))
         (op (and (< op-index (length rest)) (char rest op-index)))
         (word-start (min (length rest) (1+ op-index)))
         (word-text (subseq rest word-start)))
    (%make-parameter-operator op word-text colon-p)))

(defun %parameter-default-applicable-p (binding operator)
  (if (parameter-operator-colon-p operator)
      (or (not (parameter-binding-set-p binding))
          (zerop (length (parameter-binding-value binding))))
      (not (parameter-binding-set-p binding))))

(defun %apply-parameter-operator (binding operator word rest env)
  (let* ((name (parameter-binding-name binding))
         (value (parameter-binding-value binding))
         (word-text (parameter-operator-word-text operator))
         (apply-default-p (%parameter-default-applicable-p binding operator)))
    (case (parameter-operator-op operator)
      (#\- (if apply-default-p word value))
      (#\= (if apply-default-p (%assign-parameter-default env name word) value))
      (#\+ (if apply-default-p "" word))
      (#\? (if apply-default-p word value))
      (#\# (%param-strip-prefix value word-text env))
      (#\% (%param-strip-suffix value word-text env))
      (#\/ (%param-substitute value word-text env))
      (t   (concatenate 'string value rest)))))

(defun %expand-braced-parameter (content env)
  "Expand the CONTENT of a ${...} parameter expansion.
Supports plain ${NAME}, length ${#NAME}, the POSIX default/alternate operators
${NAME:-word} / := / :+ / :? (a leading colon makes the test fire on unset
OR empty), prefix/suffix stripping ${NAME#pat} / ## / % / %% (glob patterns),
and substitution ${NAME/pat/rep} / // (literal patterns). WORD/patterns are
themselves variable-expanded. The := operator assigns the expanded word back to
the shell environment when it fires."
  (or (%expand-parameter-length content env)
      (let* ((op-pos (%parameter-name-end content))
             (name  (subseq content 0 op-pos))
             (rest  (subseq content op-pos))
             (binding (%parameter-binding name env))
             (value (parameter-binding-value binding)))
        (if (zerop (length rest))
            value
            (let* ((operator (%parameter-operator-parts rest))
                   (word-text (parameter-operator-word-text operator))
                   (word (expand-variables word-text env)))
              (%apply-parameter-operator binding operator word rest env))))))
