(in-package #:nshell.infrastructure.persistence)


(defparameter *config-file-path-override* nil)

(defun %default-config-file-path ()
  (merge-pathnames ".nshellrc" (user-homedir-pathname)))

(defun %config-file-path ()
  (or *config-file-path-override*
      (%default-config-file-path)))

(defun %read-config-lines (path)
  (with-open-file (stream path :direction :input)
    (loop for line = (read-line stream nil nil)
          while line
          collect line)))

(defun %write-config-lines (path config)
  (with-open-file (stream path :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (line config)
      (write-line line stream)))
  t)

(defun load-config ()
  (let ((path (%config-file-path)))
    (when (probe-file path)
      (%read-config-lines path))))

(defun save-config (config)
  (%write-config-lines (%config-file-path) config))
