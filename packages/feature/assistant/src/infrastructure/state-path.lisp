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
    (labels ((ensure-directory (directory)
               (let ((parent
                       (uiop:pathname-parent-directory-pathname directory)))
                 (unless (equal parent directory)
                   (ensure-directory parent))
                 (unless (probe-file directory)
                   (handler-case
                       (sb-posix:mkdir (namestring directory) #o700)
                     (sb-posix:syscall-error (condition)
                       (unless (probe-file directory)
                         (error condition))))))))
      (ensure-directory directory)
      (let ((fd (sb-posix:open (namestring directory)
                               sb-posix:o-rdonly)))
        (unwind-protect
             (sb-posix:fchmod fd #o700)
          (sb-posix:close fd)))))
  path)

(defun %assistant-open-state-output-stream (path flags)
  (let ((fd (sb-posix:open (namestring path)
                           (logior flags sb-posix:o-wronly
                                   sb-posix:o-creat)
                           #o600)))
    (handler-case
        (progn
          (sb-posix:fchmod fd #o600)
          (sb-sys:make-fd-stream fd
                                 :output t
                                 :element-type 'character
                                 :external-format :utf-8
                                 :auto-close t
                                 :pathname path))
      (error (condition)
        (sb-posix:close fd)
        (error condition)))))

(defun assistant-state-file-path (name)
  (merge-pathnames name (assistant-state-directory-path)))
