(in-package #:nshell.domain.completion)

(defconstant +%exact-match-rank-bonus+ 100000)
(defconstant +%case-sensitive-prefix-rank-bonus+ 10000)
(defconstant +%described-candidate-rank-bonus+ 1000)

(defun %candidate-description-present-p (candidate)
  (plusp (length (candidate-description candidate))))

(defun %exact-match-rank-bonus (prefix text)
  (if (string-equal prefix text) +%exact-match-rank-bonus+ 0))

(defun %case-sensitive-prefix-rank-bonus (prefix text)
  (if (string-prefix-p prefix text)
      +%case-sensitive-prefix-rank-bonus+
      0))

(defun %described-candidate-rank-bonus (candidate)
  (if (%candidate-description-present-p candidate)
      +%described-candidate-rank-bonus+
      0))

(defun %candidate-rank-bonus (prefix candidate)
  (let ((text (candidate-text candidate)))
    (+ (%exact-match-rank-bonus prefix text)
       (%case-sensitive-prefix-rank-bonus prefix text)
       (%described-candidate-rank-bonus candidate))))

(defun %completion-rank-score (prefix candidate)
  (+ (candidate-score candidate)
     (%candidate-rank-bonus prefix candidate)))

(defun %candidate-ranking< (prefix left right)
  (let ((left-score (%completion-rank-score prefix left))
        (right-score (%completion-rank-score prefix right)))
    (cond
      ((/= left-score right-score)
       (> left-score right-score))
      (t
       (string< (candidate-text left)
                (candidate-text right))))))

(defun %completion-candidate< (prefix left right)
  (%candidate-ranking< prefix left right))

(defun %better-duplicate-candidate-p (candidate current)
  (let ((candidate-score (candidate-score candidate))
        (current-score (candidate-score current)))
    (cond
      ((> candidate-score current-score)
       t)
      ((< candidate-score current-score)
       nil)
      (t
       (and (%candidate-description-present-p candidate)
            (not (%candidate-description-present-p current)))))))

(defun %merge-candidates (&rest candidate-lists)
  (let ((cells-by-text (make-hash-table :test #'equal))
        (results nil))
    (labels ((merge-candidate (candidate)
               (let* ((text (candidate-text candidate))
                      (results-cell (gethash text cells-by-text)))
                 (cond
                   ((null results-cell)
                    (let ((new-results-cell (cons candidate results)))
                      (setf (gethash text cells-by-text) new-results-cell
                            results new-results-cell)))
                   ((%better-duplicate-candidate-p candidate
                                                    (car results-cell))
                    (setf (car results-cell) candidate))))))
      (dolist (candidates candidate-lists)
        (dolist (candidate candidates)
          (merge-candidate candidate)))
      results)))

(defun %rank-candidates (prefix candidates)
  (stable-sort (copy-list candidates)
               (lambda (left right)
                 (%completion-candidate< prefix left right))))
