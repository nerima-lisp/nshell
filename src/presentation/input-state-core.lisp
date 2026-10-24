;;; Core data model for the pure REPL input reducer.

(in-package #:nshell.presentation)
(progn
  (defvar *repl-new-reader-route-enabled-p* nil)
  (declaim (ftype function
                  %repl-new-reader-route-enabled-p
                  %repl-reader-context-for-source
                  %repl-input-scan-result))
  (defun %repl-new-reader-route-enabled-p ()
    (or *repl-new-reader-route-enabled-p*
        (equal "sexp" (uiop:getenv "NSHELL_READER")))))
(defconstant +editor-indent-width+ 2)

(defmacro define-input-state-constructor (fields)
  (let ((lambda-list '())
        (constructor-arguments '()))
    (dolist (field fields)
      (destructuring-bind (name default) field
        (push (if (null default) name `(,name ,default)) lambda-list)
        (push (intern (symbol-name name) :keyword) constructor-arguments)
        (push name constructor-arguments)))
    `(defun make-input-state (&key ,@(nreverse lambda-list))
       (%make-input-state ,@(nreverse constructor-arguments)))))

(define-input-state-constructor
  ((buffer "")
   (cursor-pos 0)
   (preferred-visual-column nil)
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
   (ask-original-buffer "")
   (ask-original-cursor nil)
   (undo-stack nil)
   (redo-stack nil)
   (vi-session nil)))
