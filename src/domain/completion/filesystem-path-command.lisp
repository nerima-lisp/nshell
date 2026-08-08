(in-package #:nshell.domain.completion)

(defun %command-prefix-has-directory-p (prefix)
  (position-if #'%path-separator-p prefix))

(defun %split-path (path)
  (let ((start 0)
        (parts nil))
    (loop for pos = (position #\: path :start start)
          do (push (subseq path start pos) parts)
          while pos
          do (setf start (1+ pos)))
    (nreverse parts)))

(defun %join-directory-command (directory command &key (empty-directory directory))
  (let ((dir (if (string= directory "") empty-directory directory)))
    (cond
      ((string= dir "") command)
      ((%path-separator-p (char dir (1- (length dir))))
       (concatenate 'string dir command))
      (t (concatenate 'string dir "/" command)))))

(defun command-path-candidates (command path executable-p &key (empty-directory ""))
  "Return executable path candidates for COMMAND projected through PATH."
  (if (%command-prefix-has-directory-p command)
      (when (funcall executable-p command)
        (list command))
      (loop for directory in (%split-path (or path ""))
            for candidate = (%join-directory-command
                             directory command :empty-directory empty-directory)
            when (funcall executable-p candidate)
              collect candidate)))

(defun %entry-command-name (entry)
  (let ((name (if (pathnamep entry)
                  (file-namestring entry)
                  (let* ((text (princ-to-string entry))
                         (slash (position-if #'%path-separator-p text :from-end t)))
                    (if slash (subseq text (1+ slash)) text)))))
    (and (< 0 (length name)) name)))

(defvar *path-command-directory-files-fn* nil
  "Function called with a PATH directory pathname to list command candidates.")

(defvar *path-command-executable-p-fn* nil
  "Function called with a candidate pathname to decide whether it is executable.")

(defun %executable-candidate-p (entry)
  (ignore-errors
      (or (null *path-command-executable-p-fn*)
          (funcall *path-command-executable-p-fn* entry))))

(defstruct (%path-command-query
            (:constructor %make-path-command-query (path prefix))
            (:conc-name %path-command-query-))
  (path nil :type (or null string) :read-only t)
  (prefix "" :type string :read-only t))

(defun %path-command-query-active-p (query)
  (and *path-command-directory-files-fn*
       (%path-command-query-path query)
       (not (%command-prefix-has-directory-p
             (%path-command-query-prefix query)))))

(defun %path-command-directory-pathname (directory)
  (pathname (if (string= directory "")
                "./"
                directory)))

(defun %list-path-command-directory (directory)
  (funcall *path-command-directory-files-fn*
           (%path-command-directory-pathname directory)))

(defun %path-command-entry-candidate (entry prefix)
  (let ((name (%entry-command-name entry)))
    (when (and name
               (%starts-with-p prefix name)
               (%executable-candidate-p entry))
      (make-candidate name :kind :command))))

(defun %add-path-command-directory-candidates (directory prefix candidates)
  (handler-case
      (dolist (entry (%list-path-command-directory directory) candidates)
        (%filesystem-candidate-set-add
         candidates
         (%path-command-entry-candidate entry prefix)))
    (error () candidates)))

(defun %command-candidates-from-path (path prefix)
  "Return executable command candidates from PATH that start with PREFIX."
  (let ((query (%make-path-command-query path prefix)))
    (if (not (%path-command-query-active-p query))
        nil
        (let ((candidates (%make-empty-filesystem-candidate-set)))
          (dolist (directory (%split-path (%path-command-query-path query)))
            (%add-path-command-directory-candidates
             directory
             (%path-command-query-prefix query)
             candidates))
          (sort (%filesystem-candidate-set-candidates candidates)
                #'string<
                :key #'candidate-text)))))
