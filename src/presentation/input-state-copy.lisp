; Input state copy-with-overrides: the public COPY-INPUT-STATE-WITH API.
;
; COPY-INPUT-STATE-WITH resolves each overridable field against STATE (see
; input-state-copy-plist) and rebuilds a fresh input-state.  The per-group
; builders return MAKE-INPUT-STATE initarg plists, which are appended to the
; buffer/cursor initargs and applied in one call.
(in-package #:nshell.presentation)

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
                                       (mouse-selection-anchor nil
                                                               mouse-selection-anchor-supplied-p)
                                       (mouse-selection-end nil
                                                            mouse-selection-end-supplied-p)
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
                                   new-buffer)))
    (apply #'make-input-state
           (append
            (list :buffer new-buffer :cursor-pos new-cursor)
            (%copy-input-state-completion-initargs
             state
             completion-index-supplied-p completion-index
             completion-base-supplied-p completion-base-buffer
             completion-base-cursor-supplied-p completion-base-cursor
             last-candidates-supplied-p last-candidates
             suggestion-supplied-p suggestion)
            (%copy-input-state-transient-initargs
             state new-buffer mode
             vi-count-supplied-p vi-count
             vi-visual-anchor-supplied-p vi-visual-anchor
             mouse-selection-anchor-supplied-p mouse-selection-anchor
             mouse-selection-end-supplied-p mouse-selection-end
             abbreviation-expander kill-ring
             last-yank-start-supplied-p last-yank-start
             last-yank-end-supplied-p last-yank-end
             last-yank-index-supplied-p last-yank-index
             last-argument-start-supplied-p last-argument-start
             last-argument-end-supplied-p last-argument-end
             last-argument-index-supplied-p last-argument-index)
            (%copy-input-state-session-initargs
             state
             search-query search-original-buffer search-original-cursor
             search-index-supplied-p search-index
             undo-stack-supplied-p undo-stack
             redo-stack-supplied-p redo-stack)))))

(defun normalize-input-state (state)
  (copy-input-state-with
   state
   :buffer (input-state-buffer state)
   :cursor-pos (clamp-cursor (input-state-cursor-pos state)
                             (input-state-buffer state))))
