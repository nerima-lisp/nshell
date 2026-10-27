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

(define-value-struct %file-completion-prefix-projection
  ((directory-prefix "" :type string)
   (file-prefix "" :type string))
  :public-accessors nil
  :constructor %make-file-completion-prefix-projection)

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

(defun %file-completion-directory-string (directory-prefix)
  "Return a directory string suitable for listing DIRECTORY-PREFIX."
  (if (string= directory-prefix "")
      "./"
      directory-prefix))

(defun %safe-file-completion-list (fn directory)
  "Call filesystem capability FN for DIRECTORY, returning NIL on failure."
  (when (functionp fn)
    (ignore-errors (funcall fn directory))))

(defun %ensure-directory-candidate-suffix (text)
  "Return TEXT with a trailing slash for directory candidates."
  (if (or (string= text "")
          (%path-separator-p (char text (1- (length text)))))
      text
      (concatenate 'string text "/")))

(define-value-struct %file-completion-query
  ((directory-prefix "" :type string)
   (name-prefix "" :type string)
   (directory "./" :type string)
   (include-files t :type boolean)
   (include-directories t :type boolean))
  :public-accessors nil
  :constructor %make-file-completion-query)

(defun %tilde-prefixed-directory-p (directory-prefix)
  "Return true when DIRECTORY-PREFIX names a path relative to the home
directory, i.e. it starts with ~."
  (and (plusp (length directory-prefix))
       (char= (char directory-prefix 0) #\~)))

(defun %expand-tilde-directory-prefix (directory-prefix home-directory)
  "Return the directory DIRECTORY-PREFIX names for LISTING purposes, with a
leading ~ expanded against HOME-DIRECTORY. DIRECTORY-PREFIX itself is left
untouched elsewhere so a completed candidate's text keeps the ~/ the user
typed, the same convention a directory candidate already relies on by
carrying its own trailing slash (%ENSURE-DIRECTORY-CANDIDATE-SUFFIX)."
  (if (and (%tilde-prefixed-directory-p directory-prefix)
           (stringp home-directory)
           (plusp (length home-directory)))
      (concatenate 'string
                   (%trim-trailing-path-separators home-directory)
                   (subseq directory-prefix 1))
      directory-prefix))

(defun %file-completion-query-from-prefix
    (prefix include-files include-directories &key home-directory)
  (multiple-value-bind (directory-prefix name-prefix)
      (%split-file-completion-prefix prefix)
    (%make-file-completion-query
     directory-prefix
     name-prefix
     (%file-completion-directory-string
      (%expand-tilde-directory-prefix directory-prefix home-directory))
     include-files
     include-directories)))

(progn
  (defun %file-completion-name-candidate (name kind query)
    (let ((name-prefix (%file-completion-query-name-prefix query)))
      (when (and name
                 (not (string= name ""))
                 (or (and (plusp (length name-prefix))
                          (char= (char name-prefix 0) #\.))
                     (char/= (char name 0) #\.))
                 (%candidate-match-stage name-prefix name))
        (let* ((directory-prefix
                 (%file-completion-query-directory-prefix query))
               (raw-text
                 (if (and (eq kind :file)
                          (string= directory-prefix ""))
                     name
                     (concatenate 'string directory-prefix name)))
               (text (if (eq kind :directory)
                         (%ensure-directory-candidate-suffix raw-text)
                         raw-text)))
          (make-candidate text
                          :kind kind
                          :score (if (eq kind :directory) 70 60)
                          :description (if (eq kind :directory)
                                           "directory"
                                           "file"))))))

  (defun %file-completion-entry-candidate (entry kind query)
    (%file-completion-name-candidate (%entry-path-name entry) kind query)))

(defun %add-file-completion-entries (entries kind query candidates)
  (dolist (entry entries candidates)
    (setf candidates
          (%filesystem-candidate-set-add
           candidates
           (%file-completion-entry-candidate entry kind query)))))

(progn
  (defun %file-completion-entry-candidate-kind (entry)
    (case (nshell.domain.filesystem:filesystem-completion-entry-kind entry)
      (:regular-file :file)
      (:directory :directory)
      (:symbolic-link
       (case (nshell.domain.filesystem:filesystem-completion-entry-target-kind entry)
         (:directory :directory)
         ((:regular-file :missing) :file)))
      (otherwise nil)))

  (defun %add-file-completion-port-entries (entries query candidates)
    ;; The adapter keeps directories before files, matching the legacy callback order.
    (dolist (entry entries candidates)
      (let ((kind (%file-completion-entry-candidate-kind entry)))
        (when (and kind
                   (or (and (eq kind :directory)
                            (%file-completion-query-include-directories query))
                       (and (eq kind :file)
                            (%file-completion-query-include-files query))))
          (setf candidates
                (%filesystem-candidate-set-add
                 candidates
                 (%file-completion-name-candidate
                  (nshell.domain.filesystem:filesystem-completion-entry-name entry)
                  kind
                  query)))))))

  (defun %file-candidates-from-directory
      (filesystem prefix &key (include-files t) (include-directories t) home-directory)
    "Return filesystem completion candidates matching PREFIX."
    (let* ((directory-files-fn
            (and (nshell.domain.filesystem:filesystem-p filesystem)
                 (nshell.domain.filesystem:filesystem-directory-files filesystem)))
           (subdirectories-fn
            (and (nshell.domain.filesystem:filesystem-p filesystem)
                 (nshell.domain.filesystem:filesystem-subdirectories filesystem)))
           (completion-entries-fn
            (and (nshell.domain.filesystem:filesystem-p filesystem)
                 (nshell.domain.filesystem:filesystem-completion-entries filesystem)))
           (query (%file-completion-query-from-prefix
                   prefix
                   include-files
                   include-directories
                   :home-directory home-directory))
           (legacy-directory
            (unless (functionp completion-entries-fn)
              (pathname (%file-completion-query-directory query))))
           (candidates (%make-empty-filesystem-candidate-set)))
      (if (functionp completion-entries-fn)
          (setf candidates
                (%add-file-completion-port-entries
                 (%safe-file-completion-list
                  completion-entries-fn
                  (%file-completion-query-directory query))
                 query
                 candidates))
        (progn
          (when (%file-completion-query-include-directories query)
            (setf candidates
                  (%add-file-completion-entries
                   (%safe-file-completion-list
                    subdirectories-fn
                    legacy-directory)
                   :directory query candidates)))
          (when (%file-completion-query-include-files query)
            (setf candidates
                  (%add-file-completion-entries
                   (%safe-file-completion-list
                    directory-files-fn
                    legacy-directory)
                   :file query candidates)))))
      (%filesystem-candidate-set-candidates candidates))))

(defun %path-like-completion-prefix-p (prefix)
  "Return true when PREFIX syntactically denotes a filesystem path."
  (plusp (length prefix)))

(defparameter +directory-only-completion-commands+ '("cd" "pushd" "popd" "rmdir")
  "Commands whose path argument may only name a directory.")

(defun completion-filesystem-mode (context)
  "Return the filesystem completion mode implied by CONTEXT."
  (cond
    ((completion-context-redirection-target-p context) :files-and-directories)
    ((completion-context-command-position-p context) nil)
    ((member (completion-context-command context) +directory-only-completion-commands+
             :test #'string=)
     :directories)
    ((member (completion-context-command context) '("source" ".") :test #'string=)
     :files-and-directories)
    ((%path-like-completion-prefix-p
      (completion-context-argument-prefix context))
     :files-and-directories)
    (t nil)))

(progn
  (defun filesystem-candidates-for-mode (mode prefix filesystem &key home-directory)
    "Return filesystem candidates for MODE and PREFIX."
    (ecase mode
      (:directories
       (%file-candidates-from-directory filesystem prefix
                                        :include-files nil
                                        :include-directories t
                                        :home-directory home-directory))
      (:files-and-directories
       (%file-candidates-from-directory filesystem prefix
                                        :include-files t
                                        :include-directories t
                                        :home-directory home-directory))))
  (defun filesystem-candidates-for-value-kind (kind prefix filesystem &key home-directory)
    "Return filesystem candidates matching the value kind implied by an option."
    (ecase kind
      (:directory
       (%file-candidates-from-directory filesystem prefix
                                        :include-files nil
                                        :include-directories t
                                        :home-directory home-directory))
      (:file
       (%file-candidates-from-directory filesystem prefix
                                        :include-files t
                                        :include-directories nil
                                        :home-directory home-directory)))))
