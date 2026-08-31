;;; Shell configuration entity
(in-package #:nshell.domain.configuration)

(define-value-struct config
    ((theme (default-theme) :type theme))
  :documentation "Shell configuration aggregating all settings."
  :constructor %allocate-config
  :predicate %config-p)

(defun make-config (&key (theme (default-theme)))
  (check-type theme theme)
  (%allocate-config theme))

(defun config-p (object)
  "Return true when OBJECT is a configuration aggregate."
  (%config-p object))

(defun default-config ()
  (make-config :theme (default-theme)))
