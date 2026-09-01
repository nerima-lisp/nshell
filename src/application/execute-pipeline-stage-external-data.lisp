(in-package #:nshell.application)

(defstruct (%external-process-redirect-plan
            (:constructor %make-external-process-redirect-plan
                (stdout-target stdout-mode stderr-target stderr-mode
                 stdout-endpoint stderr-endpoint merge-stderr-p))
            (:conc-name %external-process-redirect-plan-))
  stdout-target
  stdout-mode
  stderr-target
  stderr-mode
  stdout-endpoint
  stderr-endpoint
  merge-stderr-p)
