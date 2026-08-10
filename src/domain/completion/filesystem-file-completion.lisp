(in-package #:nshell.domain.completion)

(defun %trim-trailing-path-separators (text)
  "Return TEXT without trailing path separators, unless it is only separators."
  (let ((end (length text)))
    (loop while (and (> end 1)
                     (%path-separator-p (char text (1- end))))
          do (decf end))
    (subseq text 0 end)))

(defun %pathname-directory-tail-component (path)
  "Return the final raw directory component carried by PATH."
  (let ((directory (pathname-directory path)))
    (when (consp directory)
      (loop for component in directory
            finally (return component)))))

(defun %pathname-last-directory-component (path)
  "Return the last directory component of PATH, if PATH names a directory."
  (let ((tail (%pathname-directory-tail-component path)))
    (when (and tail (not (keywordp tail)))
      (princ-to-string tail))))

(defun %pathname-file-component-name (path)
  "Return a raw file component name for PATH without pathname syntax escaping."
  (let ((name (pathname-name path))
        (type (pathname-type path)))
    (when (and name (not (keywordp name)))
      (let ((base (princ-to-string name)))
        (when (< 0 (length base))
          (if (and type (not (eq type :unspecific)) (not (keywordp type)))
              (concatenate 'string base "." (princ-to-string type))
              base))))))

(defun %entry-path-name (entry)
  "Return a display basename for a pathname or string ENTRY."
  (cond
    ((pathnamep entry)
     (or (%pathname-file-component-name entry)
         (%pathname-last-directory-component entry)))
    ((stringp entry)
     (let* ((trimmed (%trim-trailing-path-separators entry))
            (separator (position-if #'%path-separator-p trimmed :from-end t)))
       (if separator
           (subseq trimmed (1+ separator))
           trimmed)))
    (t nil)))

(defstruct (%file-completion-prefix-projection
            (:constructor %make-file-completion-prefix-projection
                (directory-prefix file-prefix))
            (:conc-name %file-completion-prefix-projection-))
  (directory-prefix "" :type string :read-only t)
  (file-prefix "" :type string :read-only t))

(defun %project-file-completion-prefix (prefix)
  "Project a raw file completion PREFIX into directory and file-prefix parts."
  (let ((separator (position-if #'%path-separator-p prefix :from-end t)))
    (if separator
        (%make-file-completion-prefix-projection
         (subseq prefix 0 (1+ separator))
         (subseq prefix (1+ separator)))
        (%make-file-completion-prefix-projection "" prefix))))

(defun %split-file-completion-prefix (prefix)
  "Split PREFIX into a directory prefix and basename prefix."
  (let ((projection (%project-file-completion-prefix prefix)))
    (values
     (%file-completion-prefix-projection-directory-prefix projection)
     (%file-completion-prefix-projection-file-prefix projection))))

(defun %file-completion-directory-pathname (directory-prefix)
  "Return a pathname suitable for listing DIRECTORY-PREFIX."
  (pathname (if (string= directory-prefix "")
                "./"
                directory-prefix)))

(defun %safe-file-completion-list (fn directory)
  "Call completion filesystem adapter FN for DIRECTORY, returning NIL on failure."
  (when fn
    (ignore-errors (funcall fn directory))))

(defun %ensure-directory-candidate-suffix (text)
  "Return TEXT with a trailing slash for directory candidates."
  (if (or (string= text "")
          (%path-separator-p (char text (1- (length text)))))
      text
      (concatenate 'string text "/")))

(defvar *file-completion-directory-files-fn* nil
  "Function called with a directory pathname to list file completion candidates.")

(defvar *file-completion-subdirectories-fn* nil
  "Function called with a directory pathname to list directory completion candidates.")

(defstruct (%file-completion-query
            (:constructor %make-file-completion-query
                (directory-prefix name-prefix directory include-files include-directories))
            (:conc-name %file-completion-query-))
  (directory-prefix "" :type string :read-only t)
  (name-prefix "" :type string :read-only t)
  (directory #p"./" :type pathname :read-only t)
  (include-files t :type boolean :read-only t)
  (include-directories t :type boolean :read-only t))

(defun %file-completion-query-from-prefix (prefix include-files include-directories)
  (multiple-value-bind (directory-prefix name-prefix)
      (%split-file-completion-prefix prefix)
    (%make-file-completion-query
     directory-prefix
     name-prefix
     (%file-completion-directory-pathname directory-prefix)
     include-files
     include-directories)))

(defun %file-completion-entry-candidate (entry kind query)
  (let ((name (%entry-path-name entry)))
    (when (and name
               (not (string= name ""))
               (%starts-with-p (%file-completion-query-name-prefix query) name))
      (let* ((raw-text (concatenate 'string
                                    (%file-completion-query-directory-prefix query)
                                    name))
             (text (if (eq kind :directory)
                       (%ensure-directory-candidate-suffix raw-text)
                       raw-text)))
        (make-candidate text
                        :kind kind
                        :score (if (eq kind :directory) 70 60)
                        :description (if (eq kind :directory)
                                         "directory"
                                         "file"))))))

(defun %add-file-completion-entries (entries kind query candidates)
  (dolist (entry entries candidates)
    (%filesystem-candidate-set-add
     candidates
     (%file-completion-entry-candidate entry kind query))))

(defun %file-candidates-from-directory (prefix &key (include-files t) (include-directories t))
  "Return filesystem completion candidates matching PREFIX."
  (let ((query (%file-completion-query-from-prefix
                prefix
                include-files
                include-directories))
        (candidates (%make-empty-filesystem-candidate-set)))
    (when (%file-completion-query-include-directories query)
      (%add-file-completion-entries
       (%safe-file-completion-list *file-completion-subdirectories-fn*
                                   (%file-completion-query-directory query))
       :directory
       query
       candidates))
    (when (%file-completion-query-include-files query)
      (%add-file-completion-entries
       (%safe-file-completion-list *file-completion-directory-files-fn*
                                   (%file-completion-query-directory query))
       :file
       query
       candidates))
    (%filesystem-candidate-set-candidates candidates)))

(defun %path-like-completion-prefix-p (prefix)
  "Return true when PREFIX syntactically denotes a filesystem path."
  (or (position-if #'%path-separator-p prefix)
      (and (plusp (length prefix))
           (find (char prefix 0) '(#\. #\~) :test #'char=))))

(defun completion-filesystem-mode (context)
  "Return the filesystem completion mode implied by CONTEXT."
  (cond
    ((completion-context-redirection-target-p context) :files-and-directories)
    ((completion-context-command-position-p context) nil)
    ((string= (completion-context-command context) "cd") :directories)
    ((member (completion-context-command context) '("source" ".") :test #'string=)
     :files-and-directories)
    ((%path-like-completion-prefix-p
      (completion-context-argument-prefix context))
     :files-and-directories)
    (t nil)))

(progn
  (defun filesystem-candidates-for-mode (mode prefix)
    "Return filesystem candidates for MODE and PREFIX."
    (ecase mode
      (:directories
       (%file-candidates-from-directory prefix
                                        :include-files nil
                                        :include-directories t))
      (:files-and-directories
       (%file-candidates-from-directory prefix
                                        :include-files t
                                        :include-directories t))))
  (defun filesystem-candidates-for-value-kind (kind prefix)
    "Return filesystem candidates matching the value kind implied by an option."
    (ecase kind
      (:directory
       (%file-candidates-from-directory prefix
                                        :include-files nil
                                        :include-directories t))
      (:file
       (%file-candidates-from-directory prefix
                                        :include-files t
                                        :include-directories t)))))
