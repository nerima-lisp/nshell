(in-package #:nshell.domain.parsing)

(define-value-struct %redirect-spec-entry
  ((text nil)
   (kind nil)))

(defparameter +redirect-specs+ nil)

(defparameter +redirect-fd-dup-specs+ nil "Redirect specs that duplicate a descriptor and so take no file target.")

(define-value-struct redirect-fd-dup-target
  ((source nil)
   (target nil)
   (operator :output :optional t))
  :constructor make-redirect-fd-dup-target)

(define-value-struct %redirect-facts
  ((text nil)
   (kind nil)
   (fd-dup-p nil)
   (fd-dup-target nil :optional t)))

(define-value-struct %redirect-target-policy
  ((kind nil)
   (target-required-p nil)))

(define-value-struct %redirect-kind-facts
  ((kind nil)
   (input-p nil)
   (output-p nil)
   (stderr-p nil)
   (append-p nil)))

(define-value-struct %redirect-kind-fact-spec
  ((kind nil)
   (input-p nil)
   (output-p nil)
   (stderr-p nil)
   (append-p nil)))

(define-value-struct %redirect-entry
  ((kind nil)
   (target nil)))

(define-value-struct %redirect-output-destination-state
  ((stdout-target nil)
   (stdout-mode :supersede)
   (stderr-target nil)
   (stderr-mode :supersede)
   (stdout-endpoint :stdout :optional t)
   (stderr-endpoint :stderr :optional t)))

(define-value-struct redirect-output-destinations
  ((stdout-target nil)
   (stdout-mode :supersede)
   (stderr-target nil)
   (stderr-mode :supersede)
   (stdout-endpoint :stdout :optional t)
   (stderr-endpoint :stderr :optional t)))

(defparameter +redirect-kind-fact-specs+ nil)

(defmacro define-redirect-data (specs fd-dup-kinds kind-facts)
  `(progn
     (setf +redirect-specs+
           (list ,@specs))
     (setf +redirect-fd-dup-specs+
           ',fd-dup-kinds)
     (setf +redirect-kind-fact-specs+
           (list ,@kind-facts))))
