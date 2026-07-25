(in-package #:nshell.domain.completion)

(define-value-struct %completion-candidate
    ((text "" :type string)
     (kind :command :type keyword)
     (description "" :type string)
     (score 0 :type integer))
  :accessor-prefix candidate)

(defun %candidate-description-value (description)
  (etypecase description
    (null "")
    (string description)))

(defun %candidate-score-value (score)
  (etypecase score
    (null 0)
    (integer score)))

(defun %candidate-kind-value (kind)
  (check-type kind keyword)
  kind)

(defun make-candidate (text &key (kind :command) description score)
  (check-type text string)
  (%make-completion-candidate
   text
   (%candidate-kind-value kind)
   (%candidate-description-value description)
   (%candidate-score-value score)))
