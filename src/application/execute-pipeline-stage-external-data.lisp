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
