(in-package #:nshell.infrastructure.acl)

(defun make-host-filesystem ()
  (nshell.domain.filesystem:make-filesystem
   :directory-files #'host-kit:directory-files
   :subdirectories #'host-kit:subdirectories
   :executable-p #'executable-file-p
   :directory-map #'map-path-command-directories))
