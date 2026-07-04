(in-package #:nshell.domain.completion)

(defconstant +exact-match-rank-bonus+ 100000)
(defconstant +case-sensitive-prefix-rank-bonus+ 10000)
(defconstant +described-candidate-rank-bonus+ 1000)

(defstruct (candidate-ranking
            (:constructor %make-candidate-ranking (score text)))
  score
  text)

(defstruct (duplicate-candidate-quality
            (:constructor %make-duplicate-candidate-quality (score described-p)))
  score
  described-p)

(defstruct (%candidate-merge-slot
            (:constructor %make-candidate-merge-slot (results-cell))
            (:conc-name %candidate-merge-slot-))
  results-cell)

(defstruct (%candidate-merge-slot-projection
            (:constructor %make-candidate-merge-slot-projection
                (current-candidate results-cell))
            (:conc-name %candidate-merge-slot-projection-))
  current-candidate
  results-cell)

(defun %project-candidate-merge-slot (slot)
  (let ((results-cell (%candidate-merge-slot-results-cell slot)))
    (%make-candidate-merge-slot-projection
     (first results-cell)
     results-cell)))

(defun %candidate-merge-slot-candidate (slot)
  (%candidate-merge-slot-projection-current-candidate
   (%project-candidate-merge-slot slot)))

(defun %candidate-merge-slot-replace-candidate (slot candidate)
  (let ((projection (%project-candidate-merge-slot slot)))
    (setf (first (%candidate-merge-slot-projection-results-cell projection))
          candidate))
  slot)

(defstruct (%candidate-merge-state
            (:constructor %make-candidate-merge-state (cells-by-text results))
            (:conc-name %candidate-merge-state-))
  cells-by-text
  results)

(defun %make-empty-candidate-merge-state ()
  (%make-candidate-merge-state (make-hash-table :test #'equal) nil))

(defun candidate-description-present-p (candidate)
  (< 0 (length (candidate-description candidate))))

(defun case-sensitive-prefix-p (prefix text)
  (and (<= (length prefix) (length text))
       (string= prefix text :end2 (length prefix))))

(defun exact-match-rank-bonus (prefix text)
  (if (string-equal prefix text) +exact-match-rank-bonus+ 0))

(defun case-sensitive-prefix-rank-bonus (prefix text)
  (if (case-sensitive-prefix-p prefix text)
      +case-sensitive-prefix-rank-bonus+
      0))

(defun described-candidate-rank-bonus (candidate)
  (if (candidate-description-present-p candidate)
      +described-candidate-rank-bonus+
      0))

(defun candidate-rank-bonus (prefix candidate)
  (let ((text (candidate-text candidate)))
    (+ (exact-match-rank-bonus prefix text)
       (case-sensitive-prefix-rank-bonus prefix text)
       (described-candidate-rank-bonus candidate))))

(defun completion-rank-score (prefix candidate)
  (+ (candidate-score candidate)
     (candidate-rank-bonus prefix candidate)))

(defun candidate-ranking-for (prefix candidate)
  (%make-candidate-ranking (completion-rank-score prefix candidate)
                           (candidate-text candidate)))

(defun candidate-ranking< (left right)
  (cond
    ((/= (candidate-ranking-score left)
         (candidate-ranking-score right))
     (> (candidate-ranking-score left)
        (candidate-ranking-score right)))
    (t
     (string< (candidate-ranking-text left)
              (candidate-ranking-text right)))))

(defun completion-candidate< (prefix left right)
  (candidate-ranking< (candidate-ranking-for prefix left)
                      (candidate-ranking-for prefix right)))

(defun duplicate-candidate-quality (candidate)
  (%make-duplicate-candidate-quality
   (candidate-score candidate)
   (candidate-description-present-p candidate)))

(defun duplicate-candidate-quality> (candidate current)
  (cond
    ((> (duplicate-candidate-quality-score candidate)
        (duplicate-candidate-quality-score current))
     t)
    ((< (duplicate-candidate-quality-score candidate)
        (duplicate-candidate-quality-score current))
     nil)
    ((and (duplicate-candidate-quality-described-p candidate)
          (not (duplicate-candidate-quality-described-p current)))
     t)
    (t nil)))

(defun better-duplicate-candidate-p (candidate current)
  (duplicate-candidate-quality> (duplicate-candidate-quality candidate)
                                (duplicate-candidate-quality current)))

(defun %candidate-merge-state-add (state candidate)
  (let* ((text (candidate-text candidate))
         (cells-by-text (%candidate-merge-state-cells-by-text state))
         (slot (gethash text cells-by-text)))
    (cond
      ((null slot)
       (let ((new-results (cons candidate (%candidate-merge-state-results state))))
         (setf (gethash text cells-by-text) (%make-candidate-merge-slot new-results)
               (%candidate-merge-state-results state) new-results)
         state))
      ((better-duplicate-candidate-p candidate
                                     (%candidate-merge-slot-candidate slot))
       (%candidate-merge-slot-replace-candidate slot candidate)
       state)
      (t
       state))))

(defun %merge-candidate (candidate state)
  (%candidate-merge-state-add state candidate))

(defun rank-candidates (prefix candidates)
  (stable-sort (copy-list candidates)
               (lambda (left right)
                 (completion-candidate< prefix left right))))

(defun merge-candidates (&rest candidate-lists)
  (let ((state (%make-empty-candidate-merge-state)))
    (dolist (candidates candidate-lists)
      (dolist (candidate candidates)
        (%merge-candidate candidate state)))
    (%candidate-merge-state-results state)))
