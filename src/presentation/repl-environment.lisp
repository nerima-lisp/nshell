;;; REPL environment
(in-package #:nshell.presentation)

(defun exported-environment-strings ()
  (mapcar (lambda (entry)
            (format nil "~a=~a"
                    (nshell.domain.environment:env-entry-name entry)
                    (nshell.domain.environment:env-entry-value entry)))
          (nshell.domain.environment:env-list *environment*)))

(defun sync-exported-environment ()
  (setf nshell.infrastructure.acl:*exported-environment*
        (exported-environment-strings)))

(defun ensure-environment ()
  (or *environment*
      (setf *environment*
            (nshell.domain.environment:inject-os-environment
             (nshell.domain.environment:make-default-environment)
             (nshell.infrastructure.acl:current-environment-entries)
             #'nshell.infrastructure.acl:current-working-directory))))
