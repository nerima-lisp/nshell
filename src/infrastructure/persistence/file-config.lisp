(in-package #:nshell.infrastructure.persistence)


(defun config-file-path () (merge-pathnames ".nshellrc" (user-homedir-pathname)))
(defun load-config ()
  (let ((path (config-file-path)))
    (when (probe-file path)
      (with-open-file (f path :direction :input)
        (let ((lines '()))
          (loop for line = (read-line f nil nil)
                while line
                do (push line lines))
          (nreverse lines))))))
(defun save-config (config)
  (with-open-file (f (config-file-path) :direction :output
                     :if-exists :supersede :if-does-not-exist :create)
    (format f ";; nshell configuration~%")
    (when config
      (dolist (line config)
        (format f "~a~%" line))))
  t)
