(in-package #:nshell.domain.parsing)

(defstruct (%redirect-spec-entry
            (:constructor %make-redirect-spec-entry (text kind)))
  text
  kind)

(defparameter +redirect-specs+ nil)

(defparameter +redirect-fd-dup-specs+ nil "Redirect specs that duplicate a descriptor and so take no file target.")

(defstruct (redirect-fd-dup-target
            (:constructor make-redirect-fd-dup-target
                (source target &optional (operator :output))))
  source
  target
  operator)

(defstruct (%redirect-facts
            (:constructor %make-redirect-facts
                (text kind fd-dup-p &optional fd-dup-target)))
  text
  kind
  fd-dup-p
  fd-dup-target)

(defstruct (%redirect-target-policy
            (:constructor %make-redirect-target-policy
                (kind target-required-p)))
  kind
  target-required-p)

(defstruct (%redirect-kind-facts
            (:constructor %make-redirect-kind-facts
                (kind input-p output-p stderr-p append-p)))
  kind
  input-p
  output-p
  stderr-p
  append-p)

(defstruct (%redirect-kind-fact-spec
            (:constructor %make-redirect-kind-fact-spec
                (kind input-p output-p stderr-p append-p)))
  kind
  input-p
  output-p
  stderr-p
  append-p)

(defstruct (%redirect-entry
            (:constructor %make-redirect-entry (kind target)))
  kind
  target)

(defstruct (%redirect-output-destination-state
            (:constructor %make-redirect-output-destination-state
                (stdout-target stdout-mode stderr-target stderr-mode
                 &optional (stdout-endpoint :stdout) (stderr-endpoint :stderr))))
  stdout-target
  stdout-mode
  stderr-target
  stderr-mode
  stdout-endpoint
  stderr-endpoint)

(defparameter +redirect-kind-fact-specs+ nil)

(defmacro define-redirect-data (specs fd-dup-kinds kind-facts)
  `(progn
     (setf +redirect-specs+
           (list ,@specs))
     (setf +redirect-fd-dup-specs+
           ',fd-dup-kinds)
     (setf +redirect-kind-fact-specs+
           (list ,@kind-facts))))
