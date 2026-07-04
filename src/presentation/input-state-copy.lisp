; Input state copy-with-overrides: initargs assembler and public copy-input-state-with API.
(in-package #:nshell.presentation)

(defstruct (%input-state-copy-spec
            (:constructor %make-input-state-copy-spec
                (&key buffer cursor-pos completion transient session))
            (:conc-name %input-state-copy-spec-))
  buffer
  cursor-pos
  completion
  transient
  session)

(defun %copy-input-state-initargs (spec)
  (append (list :buffer (%input-state-copy-spec-buffer spec)
                :cursor-pos (%input-state-copy-spec-cursor-pos spec))
            (%copy-input-state-completion-initargs
             (%input-state-copy-spec-completion spec))
            (%copy-input-state-transient-initargs
             (%input-state-copy-spec-transient spec))
            (%copy-input-state-session-initargs
             (%input-state-copy-spec-session spec))))

(defun copy-input-state-with (state &key buffer cursor-pos
                                      (completion-index nil
                                                        completion-index-supplied-p)
                                      (completion-base-buffer nil
                                                              completion-base-supplied-p)
                                      (completion-base-cursor nil
                                                              completion-base-cursor-supplied-p)
                                      (last-candidates nil
                                                       last-candidates-supplied-p)
                                       (suggestion nil suggestion-supplied-p)
                                       mode
                                       (vi-count nil vi-count-supplied-p)
                                       (vi-visual-anchor nil
                                                         vi-visual-anchor-supplied-p)
                                       abbreviation-expander kill-ring
                                      (last-yank-start nil
                                                       last-yank-start-supplied-p)
                                      (last-yank-end nil
                                                     last-yank-end-supplied-p)
                                      (last-yank-index nil
                                                       last-yank-index-supplied-p)
                                      (last-argument-start nil
                                                           last-argument-start-supplied-p)
                                      (last-argument-end nil
                                                         last-argument-end-supplied-p)
                                      (last-argument-index nil
                                                           last-argument-index-supplied-p)
                                      search-query search-original-buffer
                                      search-original-cursor
                                      (search-index nil search-index-supplied-p)
                                      (undo-stack nil undo-stack-supplied-p)
                                      (redo-stack nil redo-stack-supplied-p))
  (let* ((new-buffer (or buffer (input-state-buffer state)))
         (new-cursor (clamp-cursor (or cursor-pos (input-state-cursor-pos state))
                                   new-buffer))
         (completion-values
           (%copy-input-state-completion-values
            state
            completion-index-supplied-p
            completion-index
            completion-base-supplied-p
            completion-base-buffer
            completion-base-cursor-supplied-p
            completion-base-cursor
            last-candidates-supplied-p
            last-candidates
            suggestion-supplied-p
            suggestion))
         (transient-values
           (%copy-input-state-transient-values
            state
            new-buffer
            mode
            vi-count-supplied-p
            vi-count
            vi-visual-anchor-supplied-p
            vi-visual-anchor
            abbreviation-expander
            kill-ring
            last-yank-start-supplied-p
            last-yank-start
            last-yank-end-supplied-p
            last-yank-end
            last-yank-index-supplied-p
            last-yank-index
            last-argument-start-supplied-p
            last-argument-start
            last-argument-end-supplied-p
            last-argument-end
            last-argument-index-supplied-p
            last-argument-index))
         (session-values
           (%copy-input-state-session-values
            state
            search-query
            search-original-buffer
            search-original-cursor
            search-index-supplied-p
            search-index
            undo-stack-supplied-p
            undo-stack
            redo-stack-supplied-p
            redo-stack)))
    (apply #'make-input-state
           (%copy-input-state-initargs
            (%make-input-state-copy-spec
             :buffer new-buffer
             :cursor-pos new-cursor
             :completion completion-values
             :transient transient-values
             :session session-values)))))

(defun normalize-input-state (state)
  (copy-input-state-with
   state
   :buffer (input-state-buffer state)
   :cursor-pos (clamp-cursor (input-state-cursor-pos state)
                             (input-state-buffer state))))
