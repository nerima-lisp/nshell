(in-package #:nshell.domain.completion)

(defconstant +%exact-match-rank-bonus+ 100000)
(defconstant +%case-sensitive-prefix-rank-bonus+ 10000)
(defconstant +%case-insensitive-prefix-rank-bonus+ 5000)
(defconstant +%described-candidate-rank-bonus+ 1000)

(defun %smart-case-query-p (prefix)
  "True when PREFIX carries an uppercase letter. A query typed with an
uppercase letter pins completion matching to case-sensitive comparisons
(smart-case, as in Vim or fzf); an all-lowercase query stays case-blind."
  (some #'upper-case-p prefix))

(defun %case-insensitive-prefix-match-p (prefix text)
  (%starts-with-p prefix text))

(defun %case-sensitive-substring-match-p (prefix text)
  (and (plusp (length prefix)) (search prefix text :test #'char=) t))

(defun %case-insensitive-substring-match-p (prefix text)
  (and (plusp (length prefix)) (search prefix text :test #'char-equal) t))

(defun %candidate-matches-prefix-policy-p (prefix text)
  "Return true when TEXT is an admissible completion for PREFIX under the
smart-case policy: outside smart-case, a case-insensitive prefix or a
substring anywhere in TEXT qualifies; under smart-case, only a case-sensitive
prefix or substring does."
  (if (%smart-case-query-p prefix)
      (or (string-prefix-p prefix text)
          (%case-sensitive-substring-match-p prefix text))
      (or (%case-insensitive-prefix-match-p prefix text)
          (%case-insensitive-substring-match-p prefix text))))

(defun candidate-prefix-match-p (prefix candidate)
  "Return true when CANDIDATE's text is a genuine prefix match for PREFIX
(exact, case-sensitive, or -- outside smart-case -- case-insensitive), never
a substring-only match. Callers such as autosuggestion, which insert text
the user never explicitly typed, use this to keep a suggestion to what the
user actually prefixed."
  (let ((text (candidate-text candidate)))
    (if (%smart-case-query-p prefix)
        (string-prefix-p prefix text)
        (%case-insensitive-prefix-match-p prefix text))))

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
  (stable-sort
   (remove-if-not
    (lambda (candidate)
      (%candidate-matches-prefix-policy-p prefix (candidate-text candidate)))
    (copy-list candidates))
   (lambda (left right)
     (%completion-candidate< prefix left right))))
