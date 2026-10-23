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

(defun load-config (&optional path)
  (let* ((explicit-p (or path *config-file-path-override*))
         (path (or path (config-file-path)))
         (legacy-path (merge-pathnames ".nshellrc" (user-homedir-pathname))))
    (when (and (not explicit-p) (probe-file legacy-path))
      (format *error-output*
              "nshell: legacy ~~/.nshellrc found and ignored; use ~a instead.~%"
              (map 'string
                   (lambda (character)
                     (if (or (< (char-code character) 32)
                             (= (char-code character) 127))
                         #\Space
                         character))
                   (namestring (pathname path)))))
    (when (probe-file path)
      (%read-config-lines path))))

(defun save-config (config &optional path)
  (%write-config-lines (or path (config-file-path)) config))
