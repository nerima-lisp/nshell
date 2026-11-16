;;; The shell knowledge base (proposal/06): built-in rule data and the
;;; bounded evaluator that answers classify/4 and diagnose/4 queries.
(in-package #:cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.feature.kb
    (:documentation
     "The shell knowledge base's public boundary.
Built-in rules are compiled into the image; user rules are injected through
*USER-CLASSIFY-RULEBASE* and can raise a level no higher than confirm.")
    (:use #:cl)
    (:export
     #:*classify-max-inferences*
     #:*classify-deadline-seconds*
     #:*user-classify-rulebase*
     #:make-user-classify-rulebase
     #:classify-subject
     #:subject-effects
     #:diagnose-typo)))
