(in-package #:nshell.domain.filesystem)

(nshell.util:define-value-struct filesystem
    ((directory-files nil)
     (subdirectories nil)
     (executable-p nil)
     (directory-map nil))
  :constructor %allocate-filesystem)

(defun make-filesystem (&key directory-files subdirectories executable-p
                              (directory-map #'mapcar))
  (check-type directory-files function)
  (check-type subdirectories function)
  (check-type executable-p function)
  (check-type directory-map function)
  (%allocate-filesystem directory-files subdirectories executable-p directory-map))
