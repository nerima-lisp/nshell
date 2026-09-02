(in-package #:nshell.application)

(define-value-struct %external-process-redirect-plan
    ((stdout-target nil)
     (stdout-mode nil)
     (stderr-target nil)
     (stderr-mode nil)
     (stdout-endpoint nil)
     (stderr-endpoint nil)
     (merge-stderr-p nil :type boolean))
  :constructor %make-external-process-redirect-plan
  :public-accessors nil)

(defmacro %with-external-process-redirect-plan
    ((plan &key stdout-target stdout-mode stderr-target stderr-mode
            stdout-endpoint stderr-endpoint merge-stderr-p)
     &body body)
  `(let ((,stdout-target (%external-process-redirect-plan-stdout-target ,plan))
         (,stdout-mode (%external-process-redirect-plan-stdout-mode ,plan))
         (,stderr-target (%external-process-redirect-plan-stderr-target ,plan))
         (,stderr-mode (%external-process-redirect-plan-stderr-mode ,plan))
         (,stdout-endpoint (%external-process-redirect-plan-stdout-endpoint ,plan))
         (,stderr-endpoint (%external-process-redirect-plan-stderr-endpoint ,plan))
         (,merge-stderr-p (%external-process-redirect-plan-merge-stderr-p ,plan)))
     ,@body))
