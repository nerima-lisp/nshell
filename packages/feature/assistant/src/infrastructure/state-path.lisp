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

(defun assistant-state-file-path (name)
  (merge-pathnames name (assistant-state-directory-path)))
