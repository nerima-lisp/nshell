;;; Shell configuration entity
(in-package #:nshell.domain.configuration)

(defstruct (config (:constructor %make-config (&key theme prompt-format)))
  "Shell configuration aggregating all settings."
  (theme (default-theme) :type theme)
  (prompt-format "[%u@%h %w]> " :type string))

(defun make-config (&key (theme (default-theme)) (prompt-format "[%u@%h %w]> "))
  (%make-config :theme theme :prompt-format prompt-format))

;; config-theme is auto-generated as the accessor for the 'theme' slot
(defun config-prompt (config)
  (config-prompt-format config))

(defun default-config ()
  (make-config :theme (default-theme)))
