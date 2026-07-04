(in-package #:nshell.domain.completion)

(defun path-separator-p (char)
  (or (char= char #\/)
      #+windows (char= char #\\)
      #-windows nil))

(defun command-prefix-has-directory-p (prefix)
  (position-if #'path-separator-p prefix))

(defun split-path (path)
  (let ((start 0)
        (parts nil))
    (loop for pos = (position #\: path :start start)
          do (push (subseq path start pos) parts)
          while pos
          do (setf start (1+ pos)))
    (nreverse parts)))

(defun entry-command-name (entry)
  (let ((name (if (pathnamep entry)
                  (file-namestring entry)
                  (let* ((text (princ-to-string entry))
                         (slash (position-if #'path-separator-p text :from-end t)))
                    (if slash (subseq text (1+ slash)) text)))))
    (and (< 0 (length name)) name)))

(defun executable-candidate-p (entry)
  (handler-case
      (or (null *path-command-executable-p-fn*)
          (funcall *path-command-executable-p-fn* entry))
    (error () nil)))

(defun trim-trailing-path-separators (text)
  "Return TEXT without trailing path separators, unless it is only separators."
  (let ((end (length text)))
    (loop while (and (> end 1)
                     (path-separator-p (char text (1- end))))
          do (decf end))
    (subseq text 0 end)))

(defun pathname-directory-tail-component (path)
  "Return the final raw directory component carried by PATH."
  (let ((directory (pathname-directory path)))
    (when (consp directory)
      (loop for component in directory
            finally (return component)))))

(defun pathname-last-directory-component (path)
  "Return the last directory component of PATH, if PATH names a directory."
  (let ((tail (pathname-directory-tail-component path)))
    (when (and tail (not (keywordp tail)))
      (princ-to-string tail))))

(defun pathname-file-component-name (path)
  "Return a raw file component name for PATH without pathname syntax escaping."
  (let ((name (pathname-name path))
        (type (pathname-type path)))
    (when (and name (not (keywordp name)))
      (let ((base (princ-to-string name)))
        (when (< 0 (length base))
          (if (and type (not (eq type :unspecific)) (not (keywordp type)))
              (concatenate 'string base "." (princ-to-string type))
              base))))))

(defun entry-path-name (entry)
  "Return a display basename for a pathname or string ENTRY."
  (cond
    ((pathnamep entry)
     (or (pathname-file-component-name entry)
         (pathname-last-directory-component entry)))
    ((stringp entry)
     (let* ((trimmed (trim-trailing-path-separators entry))
            (separator (position-if #'path-separator-p trimmed :from-end t)))
       (if separator
           (subseq trimmed (1+ separator))
           trimmed)))
    (t nil)))

(defstruct (file-completion-prefix-projection
            (:constructor %make-file-completion-prefix-projection
                (directory-prefix file-prefix)))
  (directory-prefix "" :type string :read-only t)
  (file-prefix "" :type string :read-only t))

(defun project-file-completion-prefix (prefix)
  "Project a raw file completion PREFIX into directory and file-prefix parts."
  (let ((separator (position-if #'path-separator-p prefix :from-end t)))
    (if separator
        (%make-file-completion-prefix-projection
         (subseq prefix 0 (1+ separator))
         (subseq prefix (1+ separator)))
        (%make-file-completion-prefix-projection "" prefix))))

(defun split-file-completion-prefix (prefix)
  "Split PREFIX into a directory prefix and basename prefix."
  (let ((projection (project-file-completion-prefix prefix)))
    (values
     (file-completion-prefix-projection-directory-prefix projection)
     (file-completion-prefix-projection-file-prefix projection))))

(defun file-completion-directory-pathname (directory-prefix)
  "Return a pathname suitable for listing DIRECTORY-PREFIX."
  (pathname (if (string= directory-prefix "")
                "./"
                directory-prefix)))

(defun safe-file-completion-list (fn directory)
  "Call completion filesystem adapter FN for DIRECTORY, returning NIL on failure."
  (when fn
    (handler-case
        (funcall fn directory)
      (error () nil))))

(defun ensure-directory-candidate-suffix (text)
  "Return TEXT with a trailing slash for directory candidates."
  (if (or (string= text "")
          (path-separator-p (char text (1- (length text)))))
      text
      (concatenate 'string text "/")))

(defgeneric completion-filesystem-fns (source)
  (:documentation "Return filesystem adapter functions used by completion."))

(defvar *path-command-directory-files-fn* nil
  "Function called with a PATH directory pathname to list command candidates.")

(defvar *path-command-executable-p-fn* nil
  "Function called with a candidate pathname to decide whether it is executable.")

(defvar *file-completion-directory-files-fn* nil
  "Function called with a directory pathname to list file completion candidates.")

(defvar *file-completion-subdirectories-fn* nil
  "Function called with a directory pathname to list directory completion candidates.")

(defstruct (path-command-query
            (:constructor %make-path-command-query (path prefix)))
  (path nil :type (or null string) :read-only t)
  (prefix "" :type string :read-only t))

(defstruct (file-completion-query
            (:constructor %make-file-completion-query
                (directory-prefix name-prefix directory include-files include-directories)))
  (directory-prefix "" :type string :read-only t)
  (name-prefix "" :type string :read-only t)
  (directory #p"./" :type pathname :read-only t)
  (include-files t :type boolean :read-only t)
  (include-directories t :type boolean :read-only t))

(defstruct (filesystem-candidate-set
            (:constructor %make-filesystem-candidate-set (seen candidates)))
  (seen (make-hash-table :test #'equal) :read-only t)
  (candidates nil :type list))

(defun make-filesystem-candidate-set ()
  (%make-filesystem-candidate-set (make-hash-table :test #'equal) nil))

(defun filesystem-candidate-set-add (set candidate)
  (when candidate
    (let ((text (candidate-text candidate))
          (seen (filesystem-candidate-set-seen set)))
      (unless (gethash text seen)
        (setf (gethash text seen) t
              (filesystem-candidate-set-candidates set)
              (cons candidate (filesystem-candidate-set-candidates set))))))
  set)

(defun path-command-query-active-p (query)
  (and *path-command-directory-files-fn*
       (path-command-query-path query)
       (not (command-prefix-has-directory-p
             (path-command-query-prefix query)))))

(defun path-command-directory-pathname (directory)
  (pathname (if (string= directory "")
                "./"
                directory)))

(defun list-path-command-directory (directory)
  (funcall *path-command-directory-files-fn*
           (path-command-directory-pathname directory)))

(defun path-command-entry-candidate (entry prefix)
  (let ((name (entry-command-name entry)))
    (when (and name
               (starts-with-p prefix name)
               (executable-candidate-p entry))
      (make-candidate name :kind :command))))

(defun add-path-command-directory-candidates (directory prefix candidates)
  (handler-case
      (dolist (entry (list-path-command-directory directory) candidates)
        (filesystem-candidate-set-add
         candidates
         (path-command-entry-candidate entry prefix)))
    (error () candidates)))

(defun command-candidates-from-path (path prefix)
  "Return executable command candidates from PATH that start with PREFIX."
  (let ((query (%make-path-command-query path prefix)))
    (if (not (path-command-query-active-p query))
        nil
        (let ((candidates (make-filesystem-candidate-set)))
          (dolist (directory (split-path (path-command-query-path query)))
            (add-path-command-directory-candidates
             directory
             (path-command-query-prefix query)
             candidates))
          (sort (filesystem-candidate-set-candidates candidates)
                #'string<
                :key #'candidate-text)))))

(defun file-completion-query-from-prefix (prefix include-files include-directories)
  (multiple-value-bind (directory-prefix name-prefix)
      (split-file-completion-prefix prefix)
    (%make-file-completion-query
     directory-prefix
     name-prefix
     (file-completion-directory-pathname directory-prefix)
     include-files
     include-directories)))

(defun file-completion-entry-candidate (entry kind query)
  (let ((name (entry-path-name entry)))
    (when (and name
               (not (string= name ""))
               (starts-with-p (file-completion-query-name-prefix query) name))
      (let* ((raw-text (concatenate 'string
                                    (file-completion-query-directory-prefix query)
                                    name))
             (text (if (eq kind :directory)
                       (ensure-directory-candidate-suffix raw-text)
                       raw-text)))
        (make-candidate text
                        :kind kind
                        :score (if (eq kind :directory) 70 60)
                        :description (if (eq kind :directory)
                                         "directory"
                                         "file"))))))

(defun add-file-completion-entries (entries kind query candidates)
  (dolist (entry entries candidates)
    (filesystem-candidate-set-add
     candidates
     (file-completion-entry-candidate entry kind query))))

(defun file-candidates-from-directory (prefix &key (include-files t) (include-directories t))
  "Return filesystem completion candidates matching PREFIX."
  (let ((query (file-completion-query-from-prefix
                prefix
                include-files
                include-directories))
        (candidates (make-filesystem-candidate-set)))
    (when (file-completion-query-include-directories query)
      (add-file-completion-entries
       (safe-file-completion-list *file-completion-subdirectories-fn*
                                  (file-completion-query-directory query))
       :directory
       query
       candidates))
    (when (file-completion-query-include-files query)
      (add-file-completion-entries
       (safe-file-completion-list *file-completion-directory-files-fn*
                                  (file-completion-query-directory query))
       :file
       query
       candidates))
    (filesystem-candidate-set-candidates candidates)))

(defun completion-filesystem-mode (context)
  "Return the filesystem completion mode implied by CONTEXT."
  (cond
    ((completion-context-redirection-target-p context) :files-and-directories)
    ((completion-context-command-position-p context) nil)
    ((string= (completion-context-command context) "cd") :directories)
    ((member (completion-context-command context) '("source" ".") :test #'string=)
     :files-and-directories)
    (t nil)))

(defun filesystem-candidates-for-mode (mode prefix)
  "Return filesystem candidates for MODE and PREFIX."
  (ecase mode
    (:directories
     (file-candidates-from-directory prefix
                                     :include-files nil
                                     :include-directories t))
    (:files-and-directories
     (file-candidates-from-directory prefix
                                     :include-files t
                                     :include-directories t))))
