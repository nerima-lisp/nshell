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
             (nshell.domain.environment:make-default-environment)))))

(defun executable-path-p (path)
  (handler-case
      (zerop (sb-posix:access (namestring path) sb-posix:x-ok))
    (error () nil)))

(defun configure-completion-filesystem ()
  (setf nshell.domain.completion:*path-command-directory-files-fn*
        (lambda (dir) (uiop:directory-files dir)))
  (setf nshell.domain.completion:*path-command-executable-p-fn*
        #'executable-path-p)
  (setf nshell.domain.completion:*file-completion-directory-files-fn*
        (lambda (dir) (uiop:directory-files dir)))
  (setf nshell.domain.completion:*file-completion-subdirectories-fn*
        (lambda (dir) (uiop:subdirectories dir))))

(defun install-expansion-filesystem ()
  (setf nshell.domain.expansion:*glob-directory-files-fn*
        (lambda (dir) (uiop:directory-files dir)))
  (setf nshell.domain.expansion:*glob-subdirectories-fn*
        (lambda (dir) (uiop:subdirectories dir))))
