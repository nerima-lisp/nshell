(in-package #:nshell.domain.completion)

(defun %path-separator-p (char)
  (or (char= char #\/) #+windows (char= char #\\) #-windows nil))

(defgeneric completion-filesystem-fns (source)
  (:documentation "Return filesystem adapter functions used by completion."))

(defstruct (%filesystem-candidate-set
    (:constructor %make-filesystem-candidate-set (seen candidates))
    (:conc-name %filesystem-candidate-set-)) (seen (make-hash-table :test #'equal) :read-only t)
  (candidates nil :type list))

(defun %make-empty-filesystem-candidate-set ()
  (%make-filesystem-candidate-set (make-hash-table :test #'equal) nil))

(defun %filesystem-candidate-set-add (set candidate)
  (when candidate
    (let ((text (candidate-text candidate))
          (seen (%filesystem-candidate-set-seen set)))
      (unless (gethash text seen)
        (setf (gethash text seen) t
              (%filesystem-candidate-set-candidates set) (cons candidate (%filesystem-candidate-set-candidates set))))))
  set)
