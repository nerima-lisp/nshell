(in-package #:nshell.domain.filesystem)

(progn
  (nshell.util:define-value-struct filesystem-completion-entry
      ((name "" :type string)
       (kind :unknown :type keyword)
       (target-kind :unknown :type keyword))
    :documentation "A basename and abstract filesystem kind for file completion."
    :constructor make-filesystem-completion-entry
    :keyword-constructor t)

  (nshell.util:define-value-struct filesystem
      ((directory-files nil)
       (subdirectories nil)
       (completion-entries nil)
       (executable-p nil)
       (directory-map nil))
    :constructor %allocate-filesystem))

(defun make-filesystem (&key directory-files subdirectories completion-entries executable-p
                              (directory-map #'mapcar))
  (check-type directory-files function)
  (check-type subdirectories function)
  (check-type completion-entries (or null function))
  (check-type executable-p function)
  (check-type directory-map function)
  (%allocate-filesystem directory-files subdirectories completion-entries
                        executable-p directory-map))
