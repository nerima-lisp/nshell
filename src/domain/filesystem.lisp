(in-package #:nshell.domain.filesystem)

(defstruct (filesystem
            (:constructor %allocate-filesystem
                (directory-files subdirectories executable-p directory-map))
            (:copier nil))
  directory-files
  subdirectories
  executable-p
  directory-map)

(defun make-filesystem (&key directory-files subdirectories executable-p
                              (directory-map #'mapcar))
  (check-type directory-files function)
  (check-type subdirectories function)
  (check-type executable-p function)
  (check-type directory-map function)
  (%allocate-filesystem directory-files subdirectories executable-p directory-map))
