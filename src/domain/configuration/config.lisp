;;; Shell configuration entity
(in-package #:nshell.domain.configuration)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (config
              (:constructor %allocate-config (theme prompt-format))
              (:conc-name %config-)
              (:predicate %config-p)
              (:copier nil))
    "Shell configuration aggregating all settings."
    (theme (default-theme) :type theme :read-only t)
    (prompt-format "[%u@%h %w]> " :type string :read-only t)))

(defun make-config (&key (theme (default-theme)) (prompt-format "[%u@%h %w]> "))
  (check-type theme theme)
  (check-type prompt-format string)
  (%allocate-config theme prompt-format))

(defun config-p (object)
  "Return true when OBJECT is a configuration aggregate."
  (%config-p object))

(defun config-theme (config)
  "Return CONFIG's theme."
  (%config-theme config))

(defun config-prompt (config)
  "Return CONFIG's prompt format."
  (%config-prompt-format config))

(defun default-config ()
  (make-config :theme (default-theme)))
