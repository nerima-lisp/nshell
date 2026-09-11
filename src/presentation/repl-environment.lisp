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

(defun repl-completion-environment-arguments ()
  "The session-derived keyword arguments every completion call needs: the
variables to offer, the directory git-aware sources probe, and the home
directory `~' expands to."
  (list :variable-names
        (mapcar (lambda (binding)
                  (cons (nshell.domain.environment:env-binding-name binding)
                        (nshell.domain.environment:env-binding-value binding)))
                (nshell.domain.environment:env-bindings (ensure-environment)))
        :directory (boundary-current-directory)
        :home-directory (nshell.domain.environment:env-get (ensure-environment) "HOME")))
