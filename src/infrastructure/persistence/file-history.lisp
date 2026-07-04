(in-package #:nshell.infrastructure.persistence)
(defvar *history-file-path-override* nil
  "When non-nil, overrides the default history file path. Used for testing.")

(defun %default-history-file-path ()
  (merge-pathnames ".nshell_history" (user-homedir-pathname)))

(defun history-file-path ()
  "Return the path used to persist command history."
  (or *history-file-path-override* (%default-history-file-path)))

(defun %read-history-lines (stream)
  (loop for line = (read-line stream nil nil)
        while line
        collect line))

(defun %append-history-line (stream text)
  (format stream "~a~%" text))

(defun load-history-file ()
  (handler-case
      (let ((path (history-file-path)))
        (when (probe-file path)
          (with-open-file (f path :direction :input :if-does-not-exist nil)
            (%read-history-lines f))))
    (error () nil)))

(defun append-history-entry (text)
  (handler-case
      (progn
        (ensure-directories-exist (history-file-path))
        (with-open-file (f (history-file-path) :direction :output
                           :if-exists :append :if-does-not-exist :create)
          (%append-history-line f text)))
    (error () nil)))
