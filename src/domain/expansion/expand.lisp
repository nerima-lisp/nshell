;;; Shell expansion engine
(in-package #:nshell.domain.expansion)

(defvar *fragment-escape-context* nil)

(defstruct (fragment-escape-context (:constructor %make-fragment-escape-context))
  (encoded (make-hash-table :test #'eql))
  (decoded (make-hash-table :test #'eql))
  (next #xf0000))

(defun %encode-fragment-data (value)
  ;; Encode data at insertion boundaries, never already encoded expansion text.
  ;; One character per token keeps parser indices and substring lengths intact.
  (if (null *fragment-escape-context*)
      value
      (map 'string
           (lambda (character)
             (let ((code (char-code character))
                   (context *fragment-escape-context*))
               (if (or (<= #xe100 code #xe1ff) (<= #xf0000 code #xffffd))
                   (or (gethash character (fragment-escape-context-encoded context))
                       (let ((next (fragment-escape-context-next context)))
                         (when (> next #xffffd)
                           (error "Fragment provenance token space exhausted"))
                         (let ((token (code-char next)))
                           (incf (fragment-escape-context-next context))
                           (setf (gethash character (fragment-escape-context-encoded context)) token
                                 (gethash token (fragment-escape-context-decoded context)) character)
                           token)))
                   character)))
           value)))

(defun %decode-fragment-character (character)
  (if (null *fragment-escape-context*)
      character
      (or (gethash character
                   (fragment-escape-context-decoded *fragment-escape-context*))
          (let ((code (char-code character)))
            (if (<= #xe100 code #xe1ff)
                (code-char (- code #xe100))
                character)))))

(defun %decode-fragment-data (value)
  (if *fragment-escape-context*
      (map 'string #'%decode-fragment-character value)
      value))

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
        (concatenate 'string (%encode-fragment-data home)
                     (if slash (subseq input slash) ""))
        input)))

(defun expand-tilde (input env)
  "Expand leading ~ using HOME, or the current-user ~NAME using ENV."
  (cond
    ((string= input "~") (%encode-fragment-data (or (nshell.domain.environment:env-get env "HOME") "~")))
    ((string-prefix-p "~/" input)
     (concatenate 'string (%encode-fragment-data (or (nshell.domain.environment:env-get env "HOME") "~"))
                  (subseq input 1)))
    ((and (> (length input) 1) (char= (char input 0) #\~))
     (%tilde-user-home input env))
    (t input)))

(defun expand-glob (pattern &optional filesystem)
  "Expand PATTERN containing *, ?, [abc], or ** into matching path strings.
Returns a one-element list containing PATTERN when it has no glob syntax or no matches."
  (labels ((matches-path-p (candidate)
             (let* ((pattern-components (%glob-path-components pattern))
                    (candidate-components (%glob-path-components candidate)))
               (or (and (glob-match-p pattern candidate)
                        (or (notany (lambda (component)
                                      (%glob-hidden-component-p component))
                                    candidate-components)
                            (match-path-components pattern-components
                                                   candidate-components)))
                   (and (member "**" (butlast pattern-components)
                                :test (function string=))
                        (match-path-components pattern-components
                                               candidate-components)))))
           (match-path-components (pattern-components candidate-components)
             (cond
               ((null pattern-components) (null candidate-components))
               ((string= (first pattern-components) "**")
                (or (match-path-components (rest pattern-components) candidate-components)
                    (and candidate-components
                         (not (%glob-hidden-component-p (first candidate-components)))
                         (match-path-components pattern-components
                                                (rest candidate-components)))))
               ((null candidate-components) nil)
               ((and (%glob-hidden-component-p (first candidate-components))
                     (not (and (%glob-hidden-component-p (first pattern-components))
                               (glob-match-p (first pattern-components)
                                             (first candidate-components)))))
                nil)
               ((glob-match-p (first pattern-components)
                              (first candidate-components))
                (match-path-components (rest pattern-components)
                                       (rest candidate-components)))
               (t nil))))
    (unless (glob-pattern-p pattern)
      (return-from expand-glob (list pattern)))
    (let* ((root (%decode-fragment-data (glob-root pattern)))
           (files (%glob-candidate-files pattern root filesystem))
           (matches nil))
      (dolist (file files)
        (let ((candidate (%encode-fragment-data
                          (%glob-file-candidate pattern root file))))
          (when (matches-path-p candidate)
            (push candidate matches))))
      (if matches
          (sort matches #'string< :key #'%decode-fragment-data)
          (list pattern)))))

(defun %glob-candidate-files (pattern root filesystem)
  "Return filesystem candidates for PATTERN from ROOT using the glob recursion policy."
  (if (search "**" pattern)
      (if filesystem
          (ignore-errors
            (let* ((directory-files
                     (nshell.domain.filesystem:filesystem-directory-files filesystem))
                   (subdirectories
                     (nshell.domain.filesystem:filesystem-subdirectories filesystem))
                   (suffix (if (string= root "./")
                               pattern
                               (subseq pattern (length root))))
                   (dot-directory-patterns
                     (loop for component in
                               (butlast (%glob-path-components suffix))
                           when (%glob-hidden-component-p component)
                             collect component))
                   (filtered-filesystem
                     (nshell.domain.filesystem:make-filesystem
                      :directory-files directory-files
                      :subdirectories
                      (lambda (directory)
                        (remove-if
                         (lambda (subdirectory)
                           (let* ((components
                                    (pathname-directory (pathname subdirectory)))
                                  (name (find-if #'stringp (reverse components))))
                             (and (%glob-hidden-component-p name)
                                  (notany (lambda (component)
                                            (glob-match-p component name))
                                          dot-directory-patterns))))
                         (funcall subdirectories directory)))
                      :executable-p
                      (nshell.domain.filesystem:filesystem-executable-p filesystem)
                      :directory-map
                      (nshell.domain.filesystem:filesystem-directory-map filesystem))))
              (recursive-directory-files root filtered-filesystem)))
          nil)
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
(defun %glob-hidden-component-p (component)
  (and (stringp component)
       (> (length component) 0)
       (char= (%decode-fragment-character (char component 0)) #\.)))
(defun %glob-path-components (path)
  (let ((components nil)
        (start 0))
    (loop for slash = (position #\/ path :start start)
          do (push (subseq path start slash) components)
             (unless slash (return))
             (setf start (1+ slash)))
    (nreverse components)))
