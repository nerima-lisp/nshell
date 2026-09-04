;;; Shell expansion engine
(in-package #:nshell.domain.expansion)

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

(defun %tilde-user-home (input env)
  "Expand only a current-user ~NAME prefix using HOME from ENV.
Unknown users and incomplete environment data remain literal."
  (let* ((home (nshell.domain.environment:env-get env "HOME"))
         (user (nshell.domain.environment:env-get env "USER"))
         (slash (position #\/ input))
         (name-end (or slash (length input)))
         (name (subseq input 1 name-end)))
    (if (and home user (string= user name))
        (concatenate 'string home
                     (if slash (subseq input slash) ""))
        input)))

(defun expand-tilde (input env)
  "Expand leading ~ using HOME, or the current-user ~NAME using ENV."
  (cond
    ((string= input "~") (or (nshell.domain.environment:env-get env "HOME") "~"))
    ((string-prefix-p "~/" input)
     (concatenate 'string (or (nshell.domain.environment:env-get env "HOME") "~")
                  (subseq input 1)))
    ((and (> (length input) 1) (char= (char input 0) #\~))
     (%tilde-user-home input env))
    (t input)))

(defun expand-glob (pattern &optional filesystem)
  "Expand PATTERN containing *, ?, [abc], or ** into matching path strings.
Returns a one-element list containing PATTERN when it has no glob syntax or no matches."
  (unless (glob-pattern-p pattern)
    (return-from expand-glob (list pattern)))
  (let* ((root (glob-root pattern))
         (files (%glob-candidate-files pattern root filesystem))
         (matches nil))
    (dolist (file files)
      (let ((candidate (%glob-file-candidate pattern root file)))
        (when (glob-match-p pattern candidate)
          (push candidate matches))))
    (if matches
        (sort matches #'string<)
        (list pattern))))

(defun %glob-candidate-files (pattern root filesystem)
  "Return filesystem candidates for PATTERN from ROOT using the glob recursion policy."
  (if (search "**" pattern)
      (recursive-directory-files root filesystem)
      (immediate-directory-files root filesystem)))

(defun %glob-file-candidate (pattern root file)
  "Return the normalized candidate string for FILE under ROOT -- the same string
tested against PATTERN and, on a match, handed back to the caller, so the result
can never diverge from what the match was judged against (e.g. a raw \"./\"-prefixed
namestring surviving into output after matching stripped it)."
  (%glob-match-subject-candidate (%glob-file-match-subject pattern root file)))

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

(defun %expand-glob-with-prefix (pattern &optional filesystem)
  "Expand assignment-like compound words such as label=*.txt as label=file.txt."
  (multiple-value-bind (prefix suffix)
      (%glob-assignment-prefix-parts pattern)
    (unless prefix
      (return-from %expand-glob-with-prefix
        (expand-glob pattern filesystem)))
    (let ((expanded (expand-glob suffix filesystem)))
      (if (and (= 1 (length expanded))
               (string= suffix (first expanded)))
          (list pattern)
          (mapcar (lambda (entry)
                    (concatenate 'string prefix entry))
                  expanded)))))
