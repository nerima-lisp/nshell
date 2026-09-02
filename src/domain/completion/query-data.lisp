(in-package #:nshell.domain.completion)

(defstruct (completion-query
            (:constructor
             %make-completion-query
             (partial-input context command arg-prefix argument-words
              filesystem filesystem-candidates)))
  (partial-input "" :type string :read-only t)
  (context nil :read-only t)
  (command "" :type string :read-only t)
  (arg-prefix "" :type string :read-only t)
  (argument-words nil :type list :read-only t)
  (filesystem nil :read-only t)
  (filesystem-candidates nil :type list :read-only t))
