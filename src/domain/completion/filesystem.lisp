(in-package #:nshell.domain.completion)

(defvar *path-command-executable-p-fn* nil
  "Function called with a candidate pathname to decide whether it is executable.")

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

(defun pathname-last-directory-component (path)
  "Return the last directory component of PATH, if PATH names a directory."
  (let ((directory (pathname-directory path)))
    (when (consp directory)
      (let ((tail (car (last directory))))
        (when (and tail (not (keywordp tail)))
          (princ-to-string tail))))))

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

(defun split-file-completion-prefix (prefix)
  "Split PREFIX into a directory prefix and basename prefix."
  (let ((separator (position-if #'path-separator-p prefix :from-end t)))
    (if separator
        (values (subseq prefix 0 (1+ separator))
                (subseq prefix (1+ separator)))
        (values "" prefix))))

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

(defun command-candidates-from-path (path prefix)
  "Return executable command candidates from PATH that start with PREFIX."
  (if (or (null *path-command-directory-files-fn*)
          (null path)
          (command-prefix-has-directory-p prefix))
      nil
      (let ((seen (make-hash-table :test #'equal))
            (candidates nil))
        (dolist (directory (split-path path))
          (handler-case
              (dolist (entry (funcall *path-command-directory-files-fn*
                                      (pathname (if (string= directory "")
                                                    "./"
                                                    directory))))
                (let ((name (entry-command-name entry)))
                  (when (and name
                             (starts-with-p prefix name)
                             (executable-candidate-p entry)
                             (not (gethash name seen)))
                    (setf (gethash name seen) t)
                    (push (make-candidate name :kind :command) candidates))))
            (error () nil)))
        (sort candidates #'string< :key #'candidate-text))))

(defun file-candidates-from-directory (prefix &key (include-files t) (include-directories t))
  "Return filesystem completion candidates matching PREFIX."
  (multiple-value-bind (directory-prefix name-prefix)
      (split-file-completion-prefix prefix)
    (let* ((directory (file-completion-directory-pathname directory-prefix))
           (seen (make-hash-table :test #'equal))
           (candidates nil))
      (labels ((maybe-add (entry kind score description)
                 (let ((name (entry-path-name entry)))
                   (when (and name
                              (not (string= name ""))
                              (starts-with-p name-prefix name))
                     (let* ((raw-text (concatenate 'string directory-prefix name))
                            (text (if (eq kind :directory)
                                      (ensure-directory-candidate-suffix raw-text)
                                      raw-text)))
                       (unless (gethash text seen)
                         (setf (gethash text seen) t)
                         (push (make-candidate text
                                               :kind kind
                                               :score score
                                               :description description)
                               candidates)))))))
        (when include-directories
          (dolist (entry (safe-file-completion-list *file-completion-subdirectories-fn*
                                                    directory))
            (maybe-add entry :directory 70 "directory")))
        (when include-files
          (dolist (entry (safe-file-completion-list *file-completion-directory-files-fn*
                                                    directory))
            (maybe-add entry :file 60 "file")))
        candidates))))

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
