(in-package #:nshell.domain.expansion)

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

(defun %parse-substring-integer (text)
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text)))
    (when (plusp (length trimmed))
      (ignore-errors (parse-integer trimmed :junk-allowed nil)))))

(defun %substring-index (length index)
  (max 0 (min length (if (minusp index)
                         (+ length index)
                         index))))

(defun %substring-end (length start count)
  (if count
      (let ((end (if (minusp count)
                     (+ length count)
                     (+ start count))))
        (max start (min length end)))
      length))

(defun %parameter-substring-spec (rest)
  "Return substring OFFSET and optional COUNT when REST is :offset[:count]."
  (when (and (plusp (length rest)) (char= (char rest 0) #\:))
    (let* ((body (subseq rest 1))
           (separator (position #\: body))
           (offset-text (if separator (subseq body 0 separator) body))
           (count-text (and separator (subseq body (1+ separator))))
           (offset (%parse-substring-integer offset-text))
           (count (and separator (%parse-substring-integer count-text))))
      (when (and offset
                 (or (null separator) count)
                 (not (member (and (> (length body) 0) (char body 0))
                              '(#\- #\+ #\? #\=))))
        (values offset count t)))))

(defun %expand-parameter-substring (value rest)
  (multiple-value-bind (offset count parsed-p)
      (%parameter-substring-spec rest)
    (when parsed-p
      (let* ((length (length value))
             (start (%substring-index length offset))
             (end (%substring-end length start count)))
        (subseq value start end)))))

(defun %expand-parameter-length (content env)
  "Return the string length of ${#NAME} when CONTENT starts with # followed by a bare name.
Returns NIL when CONTENT is not a length expansion."
  (when (and (plusp (length content))
             (char= (char content 0) #\#)
             (every #'variable-name-char-p (subseq content 1)))
    (let ((value (nshell.domain.environment:env-get env (subseq content 1))))
      (princ-to-string (length (or value ""))))))

(defun %parameter-binding (name env)
  (let ((raw (nshell.domain.environment:env-get env name)))
    (%make-parameter-binding name raw (not (null raw)) (or raw ""))))

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

(defun %parameter-required-message (operator word)
  (if (plusp (length word))
      word
      (if (parameter-operator-colon-p operator)
          "parameter null or not set"
          "parameter not set")))

(defun %signal-parameter-required-error (binding operator word)
  (error 'parameter-expansion-error
         :name (parameter-binding-name binding)
         :message (%parameter-required-message operator word)))

(defun %apply-parameter-operator (binding operator word rest env)
  (let* ((name (parameter-binding-name binding))
         (value (parameter-binding-value binding))
         (word-text (parameter-operator-word-text operator))
         (apply-default-p (%parameter-default-applicable-p binding operator)))
    (case (parameter-operator-op operator)
      (#\- (if apply-default-p word value))
      (#\= (if apply-default-p (%assign-parameter-default env name word) value))
      (#\+ (if apply-default-p "" word))
      (#\? (if apply-default-p
               (%signal-parameter-required-error binding operator word)
               value))
      (#\# (%param-strip-prefix value word-text env))
      (#\% (%param-strip-suffix value word-text env))
      (#\/ (%param-substitute value word-text env))
      (t   (concatenate 'string value rest)))))

(defun %expand-braced-parameter-by-name (name rest env)
  (let* ((binding (%parameter-binding name env))
         (value (parameter-binding-value binding)))
    (or (and (plusp (length rest))
             (%expand-parameter-substring value rest))
        (if (zerop (length rest))
            value
            (let* ((operator (%parameter-operator-parts rest))
                   (word-text (parameter-operator-word-text operator))
                   (word (expand-variables word-text env)))
              (%apply-parameter-operator binding operator word rest env))))))

(defun %expand-braced-parameter (content env)
  "Expand the CONTENT of a ${...} parameter expansion.
Supports plain ${NAME}, length ${#NAME}, the POSIX default/alternate operators
${NAME:-word} / := / :+ / :? (a leading colon makes the test fire on unset
OR empty), prefix/suffix stripping ${NAME#pat} / ## / % / %% (glob patterns),
and substitution ${NAME/pat/rep} / // (literal patterns). WORD/patterns are
themselves variable-expanded. The := operator assigns the expanded word back to
the shell environment when it fires."
  (or (%expand-parameter-length content env)
      (let ((op-pos (%parameter-name-end content)))
        (%expand-braced-parameter-by-name
         (subseq content 0 op-pos)
         (subseq content op-pos)
         env))))
