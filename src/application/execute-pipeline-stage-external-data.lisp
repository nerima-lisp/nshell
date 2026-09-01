(in-package #:nshell.application)

(defstruct (%external-process-redirect-plan
            (:constructor %make-external-process-redirect-plan
                (stdout-target stdout-mode stderr-target stderr-mode
                 stdout-endpoint stderr-endpoint merge-stderr-p))
            (:copier nil)
            (:conc-name %external-process-redirect-plan-))
  (stdout-target nil :read-only t)
  (stdout-mode nil :read-only t)
  (stderr-target nil :read-only t)
  (stderr-mode nil :read-only t)
  (stdout-endpoint nil :read-only t)
  (stderr-endpoint nil :read-only t)
  (merge-stderr-p nil :read-only t))

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
