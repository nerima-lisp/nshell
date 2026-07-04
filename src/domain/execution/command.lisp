(in-package #:nshell.domain.execution)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (command (:constructor %make-command (name-str args-list))
                      (:conc-name command-))
    (name-str "" :type string :read-only t)
    (args-list nil :type list :read-only t)))

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

(defun make-command (name &optional args)
  (%make-command (%command-string-value name)
                 (%command-argument-list args)))

(defun command-name (cmd)
  (%command-string-value (%command-name cmd)))

(defun command-args (cmd)
  (%command-argument-list (%command-args cmd)))

(defun command-to-list (cmd)
  (cons (command-name cmd) (command-args cmd)))
