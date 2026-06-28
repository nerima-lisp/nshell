(in-package #:nshell.domain.expansion)

(defvar *positional-args* nil
  "List of function arguments used to expand the fish-style $argv and $argv[N].
Bound dynamically by the function-call machinery for the duration of a function
body; NIL at top level.")

(defun %parse-argv-index (text &optional default)
  (if (string= text "")
      default
      (ignore-errors (parse-integer text :junk-allowed nil))))

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

(defun %list-spec-fields (fields spec)
  (let ((range-pos (search ".." spec)))
    (if range-pos
        (let ((start-index (%parse-argv-index (subseq spec 0 range-pos) 1))
              (end-index (%parse-argv-index (subseq spec (+ range-pos 2)) -1)))
          (%list-range-fields fields start-index end-index))
        (%list-index-field fields (%parse-argv-index spec)))))

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

(defun %argv-index-ref (input end len)
  "If INPUT has an argv index immediately after a name ending at END, return
\(values field-string next-index); otherwise (values NIL END)."
  (if (and (< end len) (char= (char input end) #\[))
      (let ((close (position #\] input :start (1+ end))))
        (if close
            (values (%join-fields
                     (%argv-spec-fields (subseq input (1+ end) close)))
                    (1+ close))
            (values nil end)))
      (values nil end)))

(defun %variable-index-ref (input name env end len)
  "If INPUT has an index immediately after NAME, return the joined list fields."
  (if (and (< end len) (char= (char input end) #\[))
      (let ((close (position #\] input :start (1+ end))))
        (if close
            (values (%join-fields
                     (%variable-spec-fields name
                                            (subseq input (1+ end) close)
                                            env))
                    (1+ close))
            (values nil end)))
      (values nil end)))

(defun %argv-reference-at (input start len)
  "Return (values fields next-index recognized-p) for a $argv reference at START."
  (multiple-value-bind (name name-end recognized-p)
      (%scan-variable-reference-name input start len)
    (when (and recognized-p (string= name "argv"))
      (if (and (< name-end len) (char= (char input name-end) #\[))
          (let ((close (position #\] input :start (1+ name-end))))
            (when close
              (values (%argv-spec-fields (subseq input (1+ name-end) close))
                      (1+ close)
                      t)))
          (values (copy-list *positional-args*) name-end t)))))

(defun %variable-reference-at (input start len env)
  "Return (values fields next-index recognized-p) for a list variable reference."
  (multiple-value-bind (name name-end recognized-p)
      (%scan-variable-reference-name input start len)
    (when recognized-p
      (cond
        ((string= name "argv")
         (%argv-reference-at input start len))
        ((and (< name-end len) (char= (char input name-end) #\[))
         (let ((close (position #\] input :start (1+ name-end))))
           (when close
             (values (%variable-spec-fields name
                                            (subseq input (1+ name-end) close)
                                            env)
                     (1+ close)
                     t))))))))

(defun %expand-variable-reference (input start len env)
  "Return (values expansion next-index) for a bare variable reference at START."
  (multiple-value-bind (name name-end recognized-p)
      (%scan-variable-reference-name input start len)
    (when recognized-p
      (cond
        ((string= name "argv")
         (multiple-value-bind (element next) (%argv-index-ref input name-end len)
           (if element
               (values element next)
               (values (%join-fields *positional-args*) name-end))))
        (t
         (multiple-value-bind (element next)
             (%variable-index-ref input name env name-end len)
           (if element
               (values element next)
               (values (or (nshell.domain.environment:env-get env name) "")
                       name-end))))))))

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
  (let* ((vars (nshell.domain.environment:environment-vars env))
         (existing (gethash name vars))
         (exported (and existing
                        (nshell.domain.environment:env-var-exported-p existing))))
    (setf (gethash name vars)
          (nshell.domain.environment:make-env-var name (list value) exported)))
  value)

(defun %expand-braced-parameter (content env)
  "Expand the CONTENT of a ${...} parameter expansion.
Supports plain ${NAME}, length ${#NAME}, the POSIX default/alternate operators
${NAME:-word} / :- / := / :+ / :? (a leading colon makes the test fire on unset
OR empty), prefix/suffix stripping ${NAME#pat} / ## / % / %% (glob patterns),
and substitution ${NAME/pat/rep} / // (literal patterns). WORD/patterns are
themselves variable-expanded. The := operator assigns the expanded word back to
the shell environment when it fires."
  (cond
    ;; ${#NAME} -> length (only when # precedes a bare name, not ${NAME#pat}).
    ((and (plusp (length content)) (char= (char content 0) #\#)
          (every #'variable-name-char-p (subseq content 1)))
     (let ((value (nshell.domain.environment:env-get env (subseq content 1))))
       (princ-to-string (length (or value "")))))
    (t
     (let* ((op-pos (%parameter-name-end content))
            (name (subseq content 0 op-pos))
            (rest (subseq content op-pos))
            (raw (nshell.domain.environment:env-get env name))
            (set-p (not (null raw)))
            (value (or raw "")))
       (if (zerop (length rest))
           value
           (let* ((colon (char= (char rest 0) #\:))
                  (op-index (if colon 1 0))
                  (op (when (< op-index (length rest)) (char rest op-index)))
                  (word (expand-variables
                         (subseq rest (min (length rest) (1+ op-index))) env))
                  (fire (if colon
                            (or (not set-p) (zerop (length value)))
                            (not set-p))))
             (case op
               (#\- (if fire word value))
               (#\= (if fire
                        (%assign-parameter-default env name word)
                        value))
               (#\+ (if fire "" word))
               (#\? (if fire word value))
               (#\# (%param-strip-prefix value (subseq rest 1) env))
               (#\% (%param-strip-suffix value (subseq rest 1) env))
               (#\/ (%param-substitute value (subseq rest 1) env))
               (t (concatenate 'string value rest)))))))))
