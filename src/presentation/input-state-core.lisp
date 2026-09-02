;;; Core data model for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defmacro define-input-state-constructor (fields)
  `(defun make-input-state (&key ,@(mapcar (lambda (field)
                                             (destructuring-bind (name default) field
                                               (if (null default)
                                                   name
                                                   `(,name ,default))))
                                           fields))
     (%make-input-state
      ,@(mapcan (lambda (field)
                  (let ((name (first field)))
                    (list (intern (symbol-name name) :keyword) name)))
                fields))))

(define-input-state-constructor
  ((buffer "")
   (cursor-pos 0)
   (completion-index -1)
   (completion-base-buffer nil)
   (completion-base-cursor nil)
   (last-candidates nil)
   (suggestion nil)
   (mode :insert)
   (vi-count nil)
   (vi-visual-anchor nil)
   (mouse-selection-anchor nil)
   (mouse-selection-end nil)
   (abbreviation-expander nil)
   (kill-ring nil)
   (last-yank-start nil)
   (last-yank-end nil)
   (last-yank-index nil)
   (last-argument-start nil)
   (last-argument-end nil)
   (last-argument-index nil)
   (search-query "")
   (search-original-buffer "")
   (search-original-cursor nil)
   (search-index 0)
   (undo-stack nil)
   (redo-stack nil)))
