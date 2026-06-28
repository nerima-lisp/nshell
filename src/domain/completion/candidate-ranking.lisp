(in-package #:nshell.domain.completion)

(defun candidate-description-present-p (candidate)
  (< 0 (length (candidate-description candidate))))

(defun case-sensitive-prefix-p (prefix text)
  (and (<= (length prefix) (length text))
       (string= prefix text :end2 (length prefix))))

(defun completion-rank-score (prefix candidate)
  (let ((text (candidate-text candidate)))
    (+ (candidate-score candidate)
       (if (string-equal prefix text) 100000 0)
       (if (case-sensitive-prefix-p prefix text) 10000 0)
       (if (candidate-description-present-p candidate) 1000 0))))

(defun completion-candidate< (prefix left right)
  (let ((left-score (completion-rank-score prefix left))
        (right-score (completion-rank-score prefix right))
        (left-text (candidate-text left))
        (right-text (candidate-text right)))
    (cond
      ((/= left-score right-score)
       (> left-score right-score))
      (t
       (string< left-text right-text)))))

(defun better-duplicate-candidate-p (candidate current)
  (cond
    ((> (candidate-score candidate) (candidate-score current)) t)
    ((< (candidate-score candidate) (candidate-score current)) nil)
    ((and (candidate-description-present-p candidate)
          (not (candidate-description-present-p current)))
     t)
    ((and (not (candidate-description-present-p candidate))
          (candidate-description-present-p current))
     nil)
    (t nil)))

(defun rank-candidates (prefix candidates)
  (stable-sort (copy-list candidates)
               (lambda (left right)
                 (completion-candidate< prefix left right))))

(defun merge-candidates (&rest candidate-lists)
  (let ((cells-by-text (make-hash-table :test #'equal))
        (results nil))
    (dolist (candidates candidate-lists)
      (dolist (candidate candidates)
        (let ((text (candidate-text candidate)))
          (let ((cell (gethash text cells-by-text)))
            (cond
              ((null cell)
               (push candidate results))
              ((better-duplicate-candidate-p candidate (car cell))
               (setf (car cell) candidate)))
            (unless cell
              (setf (gethash text cells-by-text) results))))))
    results))
