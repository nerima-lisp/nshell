;;; Shell configuration entity
(in-package #:nshell.domain.configuration)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (config
              (:constructor %allocate-config (theme))
              (:conc-name %config-)
              (:predicate %config-p)
              (:copier nil))
    "Shell configuration aggregating all settings."
    (theme (default-theme) :type theme :read-only t)))

(defun make-config (&key (theme (default-theme)))
  (check-type theme theme)
  (%allocate-config theme))

(defun config-p (object)
  "Return true when OBJECT is a configuration aggregate."
  (%config-p object))

(defun config-theme (config)
  "Return CONFIG's theme."
  (%config-theme config))

(defun default-config ()
  (make-config :theme (default-theme)))
