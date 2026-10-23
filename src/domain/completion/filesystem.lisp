(in-package #:nshell.domain.completion)

(defun %path-separator-p (char)
  (or (char= char #\/) #+windows (char= char #\\) #-windows nil))

(defstruct (%filesystem-candidate-set
             (:constructor %make-filesystem-candidate-set (seen candidates))
             (:conc-name %filesystem-candidate-set-)
             (:copier nil)
             (:predicate nil))
  (seen nil :type hash-table)
  (candidates nil :type list))

(defun %make-empty-filesystem-candidate-set ()
  (%make-filesystem-candidate-set
   (make-hash-table :test (function equal))
   nil))
(defun %filesystem-candidate-set-contains-p (set text)
  (nth-value 1
    (gethash text (%filesystem-candidate-set-seen set))))

(defun %filesystem-candidate-set-add (set candidate)
  (if candidate
      (let* ((text (candidate-text candidate))
             (seen (%filesystem-candidate-set-seen set)))
        (unless (%filesystem-candidate-set-contains-p set text)
          (setf (gethash text seen) t
                (%filesystem-candidate-set-candidates set)
                (cons candidate
                      (%filesystem-candidate-set-candidates set))))
        set)
      set))
