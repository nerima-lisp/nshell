;;; nshell presentation package definitions -- see package.lisp for the split's rationale.

(eval-when (:compile-toplevel :load-toplevel :execute)
;; -- Presentation packages ----------------------------------
(defpackage #:nshell.presentation
  (:documentation
   "Presentation: everything the user sees and types at. Holds the line editor's
input state and the reducer that advances it one key event at a time -- emacs
and vi bindings, kill ring, undo, incremental history search, completion cycling
-- plus syntax highlighting, autosuggestion, prompt drawing, and the REPL itself
in its interactive, batch, and script forms.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:input-state #:input-state-p #:make-input-state
            #:input-state-buffer #:input-state-cursor-pos
            #:input-state-completion-index
            #:input-state-completion-base-buffer
            #:input-state-completion-base-cursor
            #:input-state-last-candidates
            #:input-state-suggestion #:input-state-mode
            #:input-state-vi-visual-anchor
            #:input-state-abbreviation-expander
            #:input-state-kill-ring
            #:input-state-last-argument-start
            #:input-state-last-argument-end
            #:input-state-last-argument-index
            #:input-state-search-query
            #:input-state-search-original-buffer
            #:input-state-search-original-cursor
            #:input-state-search-index
            #:with-normalized-input-state
            #:apply-history-search-results-to-input-state
            #:reduce-input-state #:insert-newline-at-cursor
            #:output-event
            #:exported-environment-strings
            #:run-repl #:run-repl-batch #:run-repl-script
            #:trampoline #:render-prompt
            #:compute-suggestion #:accept-suggestion
             #:render-completions #:apply-completion
             #:highlight-line
             #:highlight-span-start #:highlight-span-end
             #:highlight-span-role
             #:highlight->ansi #:theme-color->ansi #:segment-kind->role))
)
