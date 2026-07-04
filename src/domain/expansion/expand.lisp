;;; Shell expansion engine
(in-package #:nshell.domain.expansion)

(defun pathname-directory-string (path)
  (let ((dir (pathname-directory (pathname path))))
    (cond
      ((and dir (member :absolute dir))
       (format nil "/~{~a/~}" (remove :absolute dir)))
      ((and dir (member :relative dir))
       (format nil "~{~a/~}" (remove :relative dir)))
      (t ""))))

(defun glob-root (pattern)
  (let ((wild (position-if (lambda (ch)
                             (member ch '(#\* #\? #\[) :test #'char=))
                           pattern)))
    (if wild
        (let* ((prefix (subseq pattern 0 wild))
               (slash (position #\/ prefix :from-end t)))
          (if slash
              (subseq prefix 0 (1+ slash))
              "./"))
        (pathname-directory-string pattern))))

;; Dynamic variable for filesystem operations (DDD: domain should not call uiop directly)
(defvar *glob-directory-files-fn* nil
  "Function to list files in a directory. Set to (lambda (dir) (uiop:directory-files dir)) by infrastructure.
   If NIL, glob expansion always returns the pattern unchanged.")

(defvar *glob-subdirectories-fn* nil
  "Function to list subdirectories. Set by infrastructure layer.")

(defun %recursive-directory-files-visit (dir files)
  (dolist (file (funcall *glob-directory-files-fn* dir) files)
    (push file files))
  (dolist (subdir (funcall *glob-subdirectories-fn* dir) files)
    (setf files (%recursive-directory-files-visit subdir files))))

(defun recursive-directory-files (root)
  (unless *glob-directory-files-fn* (return-from recursive-directory-files nil))
  (handler-case (%recursive-directory-files-visit (pathname root) nil)
    (error () nil)))

(defun immediate-directory-files (root)
  (unless *glob-directory-files-fn* (return-from immediate-directory-files nil))
  (handler-case (funcall *glob-directory-files-fn* (pathname root))
    (error () nil)))

(defun enough-path (file root)
  (namestring (enough-namestring file (pathname root))))

(defstruct (glob-match-subject
            (:constructor %make-glob-match-subject (pattern root file)))
  (pattern "" :type string :read-only t)
  (root "./" :read-only t)
  (file #p"" :type pathname :read-only t))

(defun %glob-file-match-subject (pattern root file)
  (%make-glob-match-subject pattern root file))

(defun %glob-match-subject-candidate (subject)
  (let* ((root (glob-match-subject-root subject))
         (relative (enough-path (glob-match-subject-file subject) root)))
    (if (string= root "./")
        relative
        (concatenate 'string root relative))))

;;; Shell glob expansion helpers

(defun glob-char-p (ch)
  (member ch '(#\* #\? #\[) :test #'char=))

(defun glob-pattern-p (pattern)
  (some #'glob-char-p pattern))

(defun bracket-negation-p (pattern start end)
  (and (< start end)
       (member (char pattern start) '(#\! #\^) :test #'char=)))

(defun bracket-range-member-p (pattern start end ch)
  (loop with index = start
        while (< index end)
        thereis (let ((left (char pattern index)))
                  (cond
                    ((and (< (+ index 2) end)
                          (char= (char pattern (1+ index)) #\-))
                     (let ((right (char pattern (+ index 2))))
                       (incf index 3)
                       (char<= left ch right)))
                    (t
                     (incf index)
                     (char= left ch))))))

(defun bracket-match-p (pattern-index pattern ch)
  (let ((end (position #\] pattern :start (1+ pattern-index))))
    (if end
        (let* ((content-start (1+ pattern-index))
               (negated-p (bracket-negation-p pattern content-start end))
               (match-start (if negated-p (1+ content-start) content-start))
               (matched-p (bracket-range-member-p pattern match-start end ch)))
          (values (if negated-p (not matched-p) matched-p)
                  (1+ end)
                  t))
        (values nil (1+ pattern-index) nil))))

(defun %glob-match-p-at (pattern pattern-length text text-length pidx tidx)
  (cond
    ((= pidx pattern-length) (= tidx text-length))
    ((and (< (1+ pidx) pattern-length)
          (char= (char pattern pidx) #\*)
          (char= (char pattern (1+ pidx)) #\*))
     (or (%glob-match-p-at pattern pattern-length text text-length (+ pidx 2) tidx)
         (and (< tidx text-length)
              (%glob-match-p-at pattern pattern-length text text-length pidx
                                (1+ tidx)))))
    ((char= (char pattern pidx) #\*)
     (or (%glob-match-p-at pattern pattern-length text text-length (1+ pidx) tidx)
         (and (< tidx text-length)
              (char/= (char text tidx) #\/)
              (%glob-match-p-at pattern pattern-length text text-length pidx
                                (1+ tidx)))))
    ((char= (char pattern pidx) #\?)
     (and (< tidx text-length)
          (char/= (char text tidx) #\/)
          (%glob-match-p-at pattern pattern-length text text-length (1+ pidx)
                            (1+ tidx))))
    ((char= (char pattern pidx) #\[)
     (and (< tidx text-length)
          (multiple-value-bind (ok next-pidx parsed-p)
              (bracket-match-p pidx pattern (char text tidx))
            (if parsed-p
                (and ok (%glob-match-p-at pattern pattern-length text text-length
                                          next-pidx (1+ tidx)))
                (and (char= (char text tidx) #\[)
                     (%glob-match-p-at pattern pattern-length text text-length
                                       (1+ pidx) (1+ tidx)))))))
    (t (and (< tidx text-length)
            (char= (char pattern pidx) (char text tidx))
            (%glob-match-p-at pattern pattern-length text text-length (1+ pidx)
                              (1+ tidx))))))

(defun glob-match-p (pattern text)
  "Return true when TEXT matches shell-style PATTERN."
  (%glob-match-p-at pattern (length pattern) text (length text) 0 0))

(defun variable-name-char-p (ch)
  (or (alphanumericp ch) (char= ch #\_)))

(defun variable-name-start-p (ch)
  (or (alpha-char-p ch) (char= ch #\_)))

(defun %parameter-name-end (content)
  "Return the index in CONTENT where the parameter name ends (i.e. the start of
an operator such as :-, :=, :+, :?), or the length of CONTENT when it is a plain
name."
  (or (position-if-not #'variable-name-char-p content)
      (length content)))

(defun starts-with-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun expand-tilde (input env)
  "Expand leading ~ to HOME and ~USER to /home/USER."
  (cond
    ((string= input "~") (or (nshell.domain.environment:env-get env "HOME") "~"))
    ((starts-with-p "~/" input)
     (concatenate 'string (or (nshell.domain.environment:env-get env "HOME") "~")
                  (subseq input 1)))
    ((and (> (length input) 1) (char= (char input 0) #\~))
     (let ((slash (position #\/ input)))
       (if slash
           (concatenate 'string "/home/" (subseq input 1 slash) (subseq input slash))
           (concatenate 'string "/home/" (subseq input 1)))))
    (t input)))

(defun expand-glob (pattern)
  "Expand PATTERN containing *, ?, [abc], or ** into matching path strings.
Returns a one-element list containing PATTERN when it has no glob syntax or no matches."
  (if (not (glob-pattern-p pattern))
      (list pattern)
      (let* ((root (glob-root pattern))
             (files (%glob-candidate-files pattern root))
             (matches nil))
        (dolist (file files)
          (when (%glob-match-file-p pattern root file)
            (push (namestring file) matches)))
        (if matches
            (sort matches #'string<)
            (list pattern)))))

(defun %glob-candidate-files (pattern root)
  "Return filesystem candidates for PATTERN from ROOT using the glob recursion policy."
  (if (search "**" pattern)
      (recursive-directory-files root)
      (immediate-directory-files root)))

(defun %glob-candidate (root file)
  (%glob-match-subject-candidate (%glob-file-match-subject "" root file)))

(defun %glob-match-file-p (pattern root file)
  (let ((subject (%glob-file-match-subject pattern root file)))
    (glob-match-p (glob-match-subject-pattern subject)
                  (%glob-match-subject-candidate subject))))

(defun %first-glob-index (pattern)
  (position-if #'glob-char-p pattern))

(defun %glob-assignment-prefix-parts (pattern)
  "Return PREFIX and glob SUFFIX for assignment-like compound PATTERN, or NIL."
  (let* ((glob-index (%first-glob-index pattern))
         (equals (and glob-index
                      (position #\= pattern :end glob-index :from-end t)))
         (path-equals (and equals
                           (position #\/ pattern :end equals :from-end t))))
    (when (and equals (null path-equals))
      (values (subseq pattern 0 (1+ equals))
              (subseq pattern (1+ equals))))))

(defun %expand-glob-with-prefix (pattern)
  "Expand assignment-like compound words such as label=*.txt as label=file.txt."
  (multiple-value-bind (prefix suffix)
      (%glob-assignment-prefix-parts pattern)
    (if (null prefix)
        (expand-glob pattern)
        (let ((expanded (expand-glob suffix)))
          (if (and (= 1 (length expanded))
                   (string= suffix (first expanded)))
              (list pattern)
              (mapcar (lambda (entry)
                        (concatenate 'string prefix entry))
                      expanded))))))

(defun %find-matching-brace (string start)
  "Return the index of the #\} matching the #\{ at START, or NIL if unbalanced."
  (loop with depth = 0
        for i from start below (length string)
        for ch = (char string i)
        do (cond ((char= ch #\{) (incf depth))
                 ((char= ch #\}) (decf depth) (when (zerop depth) (return i))))))

(defun %split-top-level-commas (string)
  "Split STRING on commas that are not nested inside braces."
  (let ((parts '()) (depth 0) (start 0))
    (loop for i from 0 below (length string)
          for ch = (char string i)
          do (cond ((char= ch #\{) (incf depth))
                   ((char= ch #\}) (decf depth))
                   ((and (char= ch #\,) (zerop depth))
                    (push (subseq string start i) parts)
                    (setf start (1+ i)))))
    (push (subseq string start) parts)
    (nreverse parts)))

(defun %brace-range-expansion (content)
  "Return the list of expansions for a numeric (1..5) or single-character (a..e)
range CONTENT, or NIL when CONTENT is not a valid range."
  (let ((dots (search ".." content)))
    (when dots
      (let ((lo (subseq content 0 dots))
            (hi (subseq content (+ dots 2))))
        (cond
          ((and (plusp (length lo)) (every #'digit-char-p lo)
                (plusp (length hi)) (every #'digit-char-p hi))
           (let ((a (parse-integer lo)) (b (parse-integer hi)))
             (if (<= a b)
                 (loop for n from a to b collect (princ-to-string n))
                 (loop for n from a downto b collect (princ-to-string n)))))
          ((and (= 1 (length lo)) (alpha-char-p (char lo 0))
                (= 1 (length hi)) (alpha-char-p (char hi 0)))
           (let ((a (char-code (char lo 0))) (b (char-code (char hi 0))))
             (if (<= a b)
                 (loop for c from a to b collect (string (code-char c)))
                 (loop for c from a downto b collect (string (code-char c))))))
          (t nil))))))

(defun %brace-expansion-options (content)
  "Return expansion options for one brace group CONTENT, or NIL when literal."
  (or (%brace-range-expansion content)
      (let ((parts (%split-top-level-commas content)))
        (when (> (length parts) 1) parts))))

(defstruct (brace-expansion-frame
            (:constructor %make-brace-expansion-frame
                (input open close prefix content suffix options)))
  (input "" :type string :read-only t)
  (open 0 :type fixnum :read-only t)
  (close 0 :type fixnum :read-only t)
  (prefix "" :type string :read-only t)
  (content "" :type string :read-only t)
  (suffix "" :type string :read-only t)
  (options nil :read-only t))

(defun %brace-expansion-frame (input open close)
  "Create the domain frame for the first matched brace group in INPUT."
  (let ((content (subseq input (1+ open) close)))
    (%make-brace-expansion-frame
     input
     open
     close
     (subseq input 0 open)
     content
     (subseq input (1+ close))
     (%brace-expansion-options content))))

(defun %brace-expansion-frame-literal (frame)
  "Return FRAME's literal brace text including the preserved prefix."
  (concatenate 'string
               (brace-expansion-frame-prefix frame)
               "{"
               (brace-expansion-frame-content frame)
               "}"))

(defun expand-braces (input)
  "Expand brace patterns {a,b,c} and ranges {1..5}/{a..e} in INPUT, returning a
list of strings (always at least one). A brace group with no top-level comma and
no valid range is left literal, matching shell behavior."
  (let ((open (position #\{ input)))
    (if (null open)
        (list input)
        (let ((close (%find-matching-brace input open)))
          (if (null close)
              (list input)
              (let ((frame (%brace-expansion-frame input open close)))
                (if (null (brace-expansion-frame-options frame))
                    (mapcar (lambda (s)
                              (concatenate 'string
                                           (%brace-expansion-frame-literal frame)
                                           s))
                            (expand-braces (brace-expansion-frame-suffix frame)))
                    (let ((suffix-expansions
                            (expand-braces (brace-expansion-frame-suffix frame))))
                      (loop for opt in (brace-expansion-frame-options frame)
                            append (loop for opt-exp in (expand-braces opt)
                                         append (loop for suf in suffix-expansions
                                                      collect (concatenate
                                                               'string
                                                               (brace-expansion-frame-prefix frame)
                                                               opt-exp
                                                               suf))))))))))))
