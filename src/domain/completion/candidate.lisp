(in-package #:nshell.domain.completion)
(defstruct (%completion-candidate
            (:constructor %allocate-completion-candidate
                (text kind description score))
            (:copier nil)
            (:conc-name %completion-candidate-))
  (text "" :type string :read-only t)
  (kind :command :type keyword :read-only t)
  (description "" :type string :read-only t)
  (score 0 :type integer :read-only t))

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

(defun %make-completion-candidate (text &key (kind :command) description score)
  (check-type text string)
  (%allocate-completion-candidate
   text
   (%candidate-kind-value kind)
   (%candidate-description-value description)
   (%candidate-score-value score)))

(defun make-candidate (text &key (kind :command) description score)
  (%make-completion-candidate
   text
   :kind kind
   :description description
   :score score))

(defun candidate-text (c) (%completion-candidate-text c))
(defun candidate-kind (c) (%completion-candidate-kind c))
(defun candidate-description (c) (%completion-candidate-description c))
(defun candidate-score (c) (%completion-candidate-score c))
