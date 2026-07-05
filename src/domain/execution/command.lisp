(in-package #:nshell.domain.execution)

(defstruct (command (:constructor %allocate-command (name-str args-list))
                    (:predicate %command-p)
                    (:copier nil)
                    (:conc-name command-))
  (name-str "" :type string :read-only t)
  (args-list nil :type list :read-only t))

(defun %command-string-value (value)
  (copy-seq value))

(defun %command-argument-value (argument)
  (if (stringp argument)
      (%command-string-value argument)
      argument))

(defun %command-argument-list (args)
  (mapcar #'%command-argument-value args))

(defun %command-name (cmd)
  (command-name-str cmd))

(defun %command-args (cmd)
  (command-args-list cmd))

(defun %make-command-with-invariants (name args)
  (check-type name string)
  (check-type args list)
  (%allocate-command (%command-string-value name)
                     (%command-argument-list args)))

(defun make-command (name &optional args)
  (%make-command-with-invariants name args))

(defun command-name (cmd)
  (%command-string-value (%command-name cmd)))

(defun command-args (cmd)
  (%command-argument-list (%command-args cmd)))

(defun command-to-list (cmd)
  (cons (command-name cmd) (command-args cmd)))
