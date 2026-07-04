(in-package #:nshell.domain.completion)
(defstruct (completion-candidate
            (:constructor %make-candidate (text &key kind description score)))
  (text "" :type string :read-only t)
  (kind :command :type keyword :read-only t)
  (description "" :type string :read-only t)
  (score 0 :type integer :read-only t))

(defun candidate-description-value (description)
  (or description ""))

(defun candidate-score-value (score)
  (or score 0))

(defun make-candidate (text &key (kind :command) description score)
  (%make-candidate text
                   :kind kind
                   :description (candidate-description-value description)
                   :score (candidate-score-value score)))

(defun candidate-text (c) (completion-candidate-text c))
(defun candidate-kind (c) (completion-candidate-kind c))
(defun candidate-description (c) (completion-candidate-description c))
(defun candidate-score (c) (completion-candidate-score c))
