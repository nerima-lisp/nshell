(in-package #:nshell.domain.completion)

(defun %path-separator-p (char)
  (or (char= char #\/) #+windows (char= char #\\) #-windows nil))

(nshell.util:define-value-struct %filesystem-candidate-set
    ((seen nil :type list :copy :list)
     (candidates nil :type list :copy :list))
  :constructor %make-filesystem-candidate-set
  :predicate nil
  :public-accessors nil)

(defun %make-empty-filesystem-candidate-set ()
  (%make-filesystem-candidate-set nil nil))

(defun %filesystem-candidate-set-add (set candidate)
  (if (or (null candidate)
          (member (candidate-text candidate)
                  (%filesystem-candidate-set-seen set)
                  :test #'string=))
      set
      (%make-filesystem-candidate-set
       (cons (candidate-text candidate)
             (%filesystem-candidate-set-seen set))
       (cons candidate (%filesystem-candidate-set-candidates set)))))
