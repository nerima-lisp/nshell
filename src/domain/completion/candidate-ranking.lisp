(in-package #:nshell.domain.completion)

(defconstant +%exact-match-rank-bonus+ 100000)
(defconstant +%case-sensitive-prefix-rank-bonus+ 10000)
(defconstant +%case-insensitive-prefix-rank-bonus+ 5000)
(defconstant +%described-candidate-rank-bonus+ 1000)

(defun %case-insensitive-prefix-match-p (prefix text)
  (%starts-with-p prefix text))

(defun %case-insensitive-substring-match-p (prefix text)
  (and (plusp (length prefix)) (search prefix text :test #'char-equal) t))

(defun %case-insensitive-subsequence-match-p (prefix text)
  (let ((text-position 0))
    (loop for character across prefix
          for match-position = (position character text
                                          :start text-position
                                          :test #'char-equal)
          do (unless match-position
               (return-from %case-insensitive-subsequence-match-p nil))
             (setf text-position (1+ match-position)))
    t))

(defun %candidate-match-stage (prefix text)
  (cond
    ((> (length prefix) (length text)) nil)
    ((string-prefix-p prefix text) 0)
    ((%case-insensitive-prefix-match-p prefix text) 1)
    ((%case-insensitive-substring-match-p prefix text) 2)
    ((%case-insensitive-subsequence-match-p prefix text) 3)))

(defun candidate-prefix-match-p (prefix candidate)
  "Return true for case-sensitive or case-insensitive prefix matches.
Autosuggestions use prefixes only because they insert text the user did not type."
  (let ((stage (%candidate-match-stage prefix (candidate-text candidate))))
    (and stage (< stage 2))))

(defun %candidate-description-present-p (candidate)
  (plusp (length (candidate-description candidate))))

(defun %exact-match-rank-bonus (prefix text)
  (if (string-equal prefix text) +%exact-match-rank-bonus+ 0))

(defun %case-sensitive-prefix-rank-bonus (prefix text)
  (if (string-prefix-p prefix text)
      +%case-sensitive-prefix-rank-bonus+
      0))

(defun %case-insensitive-prefix-rank-bonus (prefix text)
  (if (and (not (string-prefix-p prefix text))
           (%case-insensitive-prefix-match-p prefix text))
      +%case-insensitive-prefix-rank-bonus+
      0))

(defun %described-candidate-rank-bonus (candidate)
  (if (%candidate-description-present-p candidate)
      +%described-candidate-rank-bonus+
      0))

(defun %candidate-rank-bonus (prefix candidate)
  (let ((text (candidate-text candidate)))
    (+ (%exact-match-rank-bonus prefix text)
       (%case-sensitive-prefix-rank-bonus prefix text)
       (%case-insensitive-prefix-rank-bonus prefix text)
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
  (let ((best-stage nil)
        (best-candidates nil))
    (dolist (candidate candidates)
      (let ((stage (%candidate-match-stage prefix (candidate-text candidate))))
        (when stage
          (cond
            ((or (null best-stage)
                 (< stage best-stage))
             (setf best-stage stage
                   best-candidates (list candidate)))
            ((= stage best-stage)
             (push candidate best-candidates))))))
    (stable-sort (nreverse best-candidates)
                 (lambda (left right)
                   (%completion-candidate< prefix left right)))))
