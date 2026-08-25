(in-package #:nshell.infrastructure.acl)

(defvar *exported-environment* nil
  "List of \"KEY=VALUE\" strings for exported environment variables.
Set by the REPL from the current shell environment.")

(defparameter +fallback-environment-names+
  '("HOME" "PATH" "USER" "SHELL" "TERM")
  "Environment names available on implementations without POSIX environ access.")

(defun current-environment-entries ()
  "Return the current process environment as \"KEY=VALUE\" strings."
  #+sbcl
  (copy-list (sb-ext:posix-environ))
  #-sbcl
  (remove nil
          (mapcar (lambda (name)
                    (let ((value (host-kit:getenv name)))
                      (when value
                        (format nil "~a=~a" name value))))
                  +fallback-environment-names+)))

(defun current-environment-value (name)
  "Return the current process value of environment variable NAME."
  (check-type name string)
  (host-kit:getenv name))

(defun current-working-directory ()
  "Return the current process working directory as a pathname or string."
  (host-kit:getcwd))

(defun %get-environment ()
  "Return the environment list for subprocess execution. When the shell has
exported variables, use them; otherwise inherit the real process environment so
child processes still receive a PATH (and can be found via :search)."
  (or *exported-environment*
      (current-environment-entries)))
