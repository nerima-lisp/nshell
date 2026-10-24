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
variables to offer, the directory git-aware sources probe, the home directory
`~' expands to, and the process IDs available to kill completion."
  (let ((process-ids nil)
        (registry *proc-registry*))
    (when (hash-table-p registry)
      (maphash
       (lambda (job-id processes)
         (declare (ignore job-id))
         (dolist (process (if (listp processes) processes (list processes)))
           (let ((pid (ignore-errors
                        (nshell.infrastructure.acl:process-pid process))))
             (when (and (integerp pid) (plusp pid))
               (push (princ-to-string pid) process-ids)))))
       registry))
    (list :variable-names
          (mapcar (lambda (binding)
                    (cons (nshell.domain.environment:env-binding-name binding)
                          (nshell.domain.environment:env-binding-value binding)))
                  (nshell.domain.environment:env-bindings (ensure-environment)))
          :directory (boundary-current-directory)
          :home-directory (nshell.domain.environment:env-get (ensure-environment) "HOME")
          :process-ids (remove-duplicates process-ids :test #'string=))))

