(in-package #:nshell.domain.completion)

(define-value-struct completion-query
  ((partial-input "" :type string)
   (context nil)
   (command "" :type string)
   (arg-prefix "" :type string)
   (argument-words nil :type list)
   (filesystem nil)
   (filesystem-candidates nil :type list))
  :constructor %make-completion-query)
