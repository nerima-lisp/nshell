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

(defun glob-char-p (ch)
  "True when CH is a shell glob metacharacter (*, ?, or [)."
  (member ch '(#\* #\? #\[) :test #'char=))

(defun glob-root (pattern)
  (let ((wild (position-if #'glob-char-p pattern)))
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

(defun %walk-directory-files (dir continuation)
  "Apply CONTINUATION to every file reachable from DIR, descending into each
subdirectory depth-first.  Written in continuation-passing style so the
traversal here stays free of any accumulator: what to do with each file is the
caller's CONTINUATION, keeping the walk (data) separate from its use (logic)."
  (dolist (file (funcall *glob-directory-files-fn* dir))
    (funcall continuation file))
  (dolist (subdir (funcall *glob-subdirectories-fn* dir))
    (%walk-directory-files subdir continuation)))

(defun recursive-directory-files (root)
  (unless *glob-directory-files-fn* (return-from recursive-directory-files nil))
  (handler-case
      (let ((files '()))
        (%walk-directory-files (pathname root)
                               (lambda (file) (push file files)))
        files)
    (error () nil)))

(defun immediate-directory-files (root)
  (unless *glob-directory-files-fn* (return-from immediate-directory-files nil))
  (handler-case (funcall *glob-directory-files-fn* (pathname root))
    (error () nil)))

(defun enough-path (file root)
  (namestring (enough-namestring file (pathname root))))

(define-value-struct %glob-match-subject
    ((pattern "" :type string)
     (root "./")
     (file #p"" :type pathname)))

(defun %glob-file-match-subject (pattern root file)
  (%make-glob-match-subject pattern root file))

(defun %glob-match-subject-candidate (subject)
  (let* ((root (glob-match-subject-root subject))
         (relative (enough-path (glob-match-subject-file subject) root)))
    (if (string= root "./")
        relative
        (concatenate 'string root relative))))

;;; Shell glob expansion helpers

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

(defun glob-match-p (pattern text)
  "Return true when TEXT matches shell-style PATTERN.

The matcher recurses over two cursors -- PIDX into PATTERN and TIDX into TEXT --
while PATTERN, TEXT, and their lengths stay fixed.  Closing over the invariants
in MATCH keeps every recursive call down to the two cursors that actually move,
so each branch reads as the glob rule it implements."
  (let ((pattern-length (length pattern))
        (text-length (length text)))
    (labels ((match (pidx tidx)
               (cond
                 ((= pidx pattern-length) (= tidx text-length))
                 ;; `**' matches across path separators: consume the group, or
                 ;; extend the run by one text char.
                 ((and (< (1+ pidx) pattern-length)
                       (char= (char pattern pidx) #\*)
                       (char= (char pattern (1+ pidx)) #\*))
                  (or (match (+ pidx 2) tidx)
                      (and (< tidx text-length)
                           (match pidx (1+ tidx)))))
                 ;; `*' matches within a single path segment (never a #\/).
                 ((char= (char pattern pidx) #\*)
                  (or (match (1+ pidx) tidx)
                      (and (< tidx text-length)
                           (char/= (char text tidx) #\/)
                           (match pidx (1+ tidx)))))
                 ;; `?' matches exactly one non-separator char.
                 ((char= (char pattern pidx) #\?)
                  (and (< tidx text-length)
                       (char/= (char text tidx) #\/)
                       (match (1+ pidx) (1+ tidx))))
                 ;; `[...]' character class, or a literal `[' when unparsable.
                 ((char= (char pattern pidx) #\[)
                  (and (< tidx text-length)
                       (multiple-value-bind (ok next-pidx parsed-p)
                           (bracket-match-p pidx pattern (char text tidx))
                         (if parsed-p
                             (and ok (match next-pidx (1+ tidx)))
                             (and (char= (char text tidx) #\[)
                                  (match (1+ pidx) (1+ tidx)))))))
                 (t (and (< tidx text-length)
                         (char= (char pattern pidx) (char text tidx))
                         (match (1+ pidx) (1+ tidx)))))))
      (match 0 0))))

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

(defun %tilde-user-home (input)
  "Expand a ~USER prefix in INPUT to /home/USER, preserving any path that
follows the first slash. Pure string layout, kept out of EXPAND-TILDE's dispatch."
  (let ((slash (position #\/ input)))
    (if slash
        (concatenate 'string "/home/" (subseq input 1 slash) (subseq input slash))
        (concatenate 'string "/home/" (subseq input 1)))))

(defun expand-tilde (input env)
  "Expand leading ~ to HOME and ~USER to /home/USER."
  (cond
    ((string= input "~") (or (nshell.domain.environment:env-get env "HOME") "~"))
    ((string-prefix-p "~/" input)
     (concatenate 'string (or (nshell.domain.environment:env-get env "HOME") "~")
                  (subseq input 1)))
    ((and (> (length input) 1) (char= (char input 0) #\~))
     (%tilde-user-home input))
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
