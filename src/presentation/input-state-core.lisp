;;; Core data model for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun make-input-state (&key (buffer "")
                              (cursor-pos 0)
                              (completion-index -1)
                              (completion-base-buffer nil)
                              (completion-base-cursor nil)
                              (last-candidates nil)
                              suggestion
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
                              (redo-stack nil))
  (%make-input-state
   :buffer buffer
   :cursor-pos cursor-pos
   :completion-index completion-index
   :completion-base-buffer completion-base-buffer
   :completion-base-cursor completion-base-cursor
   :last-candidates last-candidates
   :suggestion suggestion
   :mode mode
   :vi-count vi-count
   :vi-visual-anchor vi-visual-anchor
   :mouse-selection-anchor mouse-selection-anchor
   :mouse-selection-end mouse-selection-end
   :abbreviation-expander abbreviation-expander
   :kill-ring kill-ring
   :last-yank-start last-yank-start
   :last-yank-end last-yank-end
   :last-yank-index last-yank-index
   :last-argument-start last-argument-start
   :last-argument-end last-argument-end
   :last-argument-index last-argument-index
   :search-query search-query
   :search-original-buffer search-original-buffer
   :search-original-cursor search-original-cursor
   :search-index search-index
   :undo-stack undo-stack
   :redo-stack redo-stack))
