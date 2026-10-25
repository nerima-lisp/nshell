(in-package #:nshell.infrastructure.persistence)


(defparameter *config-file-path-override* nil)

(defun %default-config-file-path ()
  (let ((xdg
          (nshell.infrastructure.acl:current-environment-value
           "XDG_CONFIG_HOME")))
    (if (and xdg
             (plusp (length xdg))
             (eq :absolute
                 (first (pathname-directory (pathname xdg)))))
        (merge-pathnames #P"nshell/init.lisp"
                         (uiop:ensure-directory-pathname (pathname xdg)))
        (merge-pathnames #P".config/nshell/init.lisp"
                         (user-homedir-pathname)))))

(defun config-file-path ()
  "Return the selected config file path, including an explicit override."
  (or *config-file-path-override*
      (%default-config-file-path)))

(defun %read-config-lines (path)
  (with-open-file (stream path :direction :input)
    (loop for line = (read-line stream nil nil)
          while line
          collect line)))

(defun %write-config-lines (path config)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (line config)
      (write-line line stream)))
  t)

(defun save-config (config &optional path)
  (%write-config-lines (or path (config-file-path)) config))

(defun %load-config-file-sources (&optional path)
  (let* ((explicit-p (or path *config-file-path-override*))
         (path (or path (config-file-path)))
         (config-directory
           (make-pathname :name nil :type nil :defaults (pathname path)))
         (conf-directory (merge-pathnames #P"conf.d/" config-directory))
         (legacy-path (merge-pathnames ".nshellrc" (user-homedir-pathname)))
         (paths
           (if explicit-p
               (list path)
               (cons path
                     (sort
                      (remove-if
                       (lambda (candidate)
                         (or (uiop:directory-exists-p candidate)
                             (not (string= (or (pathname-type candidate) "")
                                           "lisp"))))
                       (directory
                        (merge-pathnames #P"*.lisp" conf-directory)))
                      (function string<)
                      :key (function namestring))))))
    (when (and (not explicit-p) (probe-file legacy-path))
      (format *error-output*
              "nshell: legacy ~~/.nshellrc found and ignored; use ~a instead.~%"
              (map (quote string)
                   (lambda (character)
                     (if (or (< (char-code character) 32) (= (char-code character) 127)) #\Space character))
                   (namestring (pathname path)))))
    (loop for source-path in paths
          when (probe-file source-path)
            collect (cons source-path (%read-config-lines source-path)))))
(defun load-config (&optional path)
  (loop for source in (%load-config-file-sources path)
        append (cdr source)))
(defun load-config-sources (&optional path)
  "Return ordered config sources as (PATH . LINES) entries.
The default config loads init.lisp first, then lexically sorted lowercase
*.lisp files from the sibling conf.d directory. An explicit path or override
loads only that file."
  (%load-config-file-sources path))
