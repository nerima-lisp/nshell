(in-package #:nshell.feature.assistant)

(defvar *assistant-state-directory-path-override* nil)

(defun %assistant-default-state-directory-path ()
  (let ((xdg-state-home (uiop:getenv "XDG_STATE_HOME")))
    (if (and xdg-state-home (plusp (length xdg-state-home)))
        (merge-pathnames "nshell/"
                         (uiop:ensure-directory-pathname
                          (pathname xdg-state-home)))
        (merge-pathnames ".nshell/" (user-homedir-pathname)))))

(defun assistant-state-directory-path ()
  (uiop:ensure-directory-pathname
   (or *assistant-state-directory-path-override*
       (%assistant-default-state-directory-path))))

(defun %assistant-ensure-secure-state-directory (path)
  (let ((directory
          (make-pathname :name nil :type nil :defaults (pathname path))))
    (ensure-directories-exist directory)
    (sb-posix:chmod (namestring directory) #o700))
  path)

(defun %assistant-secure-state-file (path)
  (sb-posix:chmod (namestring path) #o600)
  path)

(defun assistant-state-file-path (name)
  (merge-pathnames name (assistant-state-directory-path)))
