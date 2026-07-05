; Input state copy-with-overrides: per-group value builders for completion, transient, and session fields.
(in-package #:nshell.presentation)

(defun clamp-cursor (position buffer)
  (max 0 (min position (length buffer))))

(defstruct (%input-state-copy-override
            (:constructor %make-input-state-copy-override (kind value))
            (:conc-name %input-state-copy-override-))
  kind
  value)

(defun input-state-copy-override-kind (override)
  (%input-state-copy-override-kind override))

(defun input-state-copy-override-value (override)
  (%input-state-copy-override-value override))

(defun input-state-copy-override-for (supplied-p value)
  (cond
    ((not supplied-p) (%make-input-state-copy-override :current nil))
    ((eq value :clear) (%make-input-state-copy-override :clear nil))
    (t (%make-input-state-copy-override :value value))))

(defun input-state-copy-optional-value-override (value)
  (cond
    ((eq value :clear) (%make-input-state-copy-override :clear nil))
    (value (%make-input-state-copy-override :value value))
    (t (%make-input-state-copy-override :current nil))))

(defun input-state-copy-override-resolve (override current-value
                                          &key (clear-value nil) acceptp)
  (case (input-state-copy-override-kind override)
    (:current current-value)
    (:clear clear-value)
    (:value (let ((value (input-state-copy-override-value override)))
              (if (or (null acceptp)
                      (funcall acceptp value))
                  value
                  current-value)))))

(defun input-state-copy-anchor-override-resolve (override current-value buffer)
  (let ((anchor (input-state-copy-override-resolve override current-value)))
    (and anchor (clamp-cursor anchor buffer))))

(defstruct (%input-state-completion-copy
            (:constructor %make-input-state-completion-copy
                (&key completion-index completion-base-buffer
                      completion-base-cursor last-candidates suggestion))
            (:conc-name %input-state-completion-copy-))
  completion-index
  completion-base-buffer
  completion-base-cursor
  last-candidates
  suggestion)

(defstruct (%input-state-transient-copy
            (:constructor %make-input-state-transient-copy
                (&key mode vi-count vi-visual-anchor abbreviation-expander
                      kill-ring last-yank-start last-yank-end last-yank-index
                      last-argument-start last-argument-end last-argument-index))
            (:conc-name %input-state-transient-copy-))
  mode
  vi-count
  vi-visual-anchor
  abbreviation-expander
  kill-ring
  last-yank-start
  last-yank-end
  last-yank-index
  last-argument-start
  last-argument-end
  last-argument-index)

(defstruct (%input-state-session-copy
            (:constructor %make-input-state-session-copy
                (&key search-query search-original-buffer search-original-cursor
                      search-index undo-stack redo-stack))
            (:conc-name %input-state-session-copy-))
  search-query
  search-original-buffer
  search-original-cursor
  search-index
  undo-stack
  redo-stack)

(defun %copy-input-state-completion-values (state
                                            completion-index-supplied-p
                                            completion-index
                                            completion-base-supplied-p
                                            completion-base-buffer
                                            completion-base-cursor-supplied-p
                                            completion-base-cursor
                                            last-candidates-supplied-p
                                            last-candidates
                                            suggestion-supplied-p
                                            suggestion)
  (%make-input-state-completion-copy
   :completion-index (if completion-index-supplied-p
                         completion-index
                         (input-state-completion-index state))
   :completion-base-buffer (if (and completion-index-supplied-p
                                    (= completion-index -1))
                               nil
                               (input-state-copy-override-resolve
                                (input-state-copy-override-for
                                 completion-base-supplied-p
                                 completion-base-buffer)
                                (input-state-completion-base-buffer state)
                                :acceptp #'stringp))
   :completion-base-cursor (if (and completion-index-supplied-p
                                    (= completion-index -1))
                               nil
                               (input-state-copy-override-resolve
                                (input-state-copy-override-for
                                 completion-base-cursor-supplied-p
                                 completion-base-cursor)
                                (input-state-completion-base-cursor state)
                                :acceptp #'integerp))
   :last-candidates (input-state-copy-override-resolve
                     (input-state-copy-override-for
                      last-candidates-supplied-p
                      last-candidates)
                     (input-state-last-candidates state))
   :suggestion (input-state-copy-override-resolve
                (input-state-copy-override-for
                 suggestion-supplied-p
                 suggestion)
                (input-state-suggestion state))))

(defun %copy-input-state-transient-values (state
                                           buffer
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
                                           last-argument-index)
  (%make-input-state-transient-copy
   :mode (or mode (input-state-mode state))
   :vi-count (input-state-copy-override-resolve
              (input-state-copy-override-for
               vi-count-supplied-p
               vi-count)
              (input-state-vi-count state))
   :vi-visual-anchor (input-state-copy-anchor-override-resolve
                      (input-state-copy-override-for
                       vi-visual-anchor-supplied-p
                       vi-visual-anchor)
                      (input-state-vi-visual-anchor state)
                      buffer)
   :abbreviation-expander (or abbreviation-expander
                               (input-state-abbreviation-expander state))
   :kill-ring (input-state-copy-override-resolve
               (input-state-copy-optional-value-override kill-ring)
               (input-state-kill-ring state))
   :last-yank-start (input-state-copy-override-resolve
                     (input-state-copy-override-for
                      last-yank-start-supplied-p
                      last-yank-start)
                     (input-state-last-yank-start state))
   :last-yank-end (input-state-copy-override-resolve
                   (input-state-copy-override-for
                    last-yank-end-supplied-p
                    last-yank-end)
                   (input-state-last-yank-end state))
   :last-yank-index (input-state-copy-override-resolve
                     (input-state-copy-override-for
                      last-yank-index-supplied-p
                      last-yank-index)
                     (input-state-last-yank-index state))
   :last-argument-start (input-state-copy-override-resolve
                         (input-state-copy-override-for
                          last-argument-start-supplied-p
                          last-argument-start)
                         (input-state-last-argument-start state))
   :last-argument-end (input-state-copy-override-resolve
                       (input-state-copy-override-for
                        last-argument-end-supplied-p
                        last-argument-end)
                       (input-state-last-argument-end state))
   :last-argument-index (input-state-copy-override-resolve
                         (input-state-copy-override-for
                          last-argument-index-supplied-p
                          last-argument-index)
                         (input-state-last-argument-index state))))

(defun %copy-input-state-session-values (state
                                         search-query
                                         search-original-buffer
                                         search-original-cursor
                                         search-index-supplied-p
                                         search-index
                                         undo-stack-supplied-p
                                         undo-stack
                                         redo-stack-supplied-p
                                         redo-stack)
  (%make-input-state-session-copy
   :search-query (input-state-copy-override-resolve
                  (input-state-copy-optional-value-override search-query)
                  (input-state-search-query state)
                  :clear-value "")
   :search-original-buffer (input-state-copy-override-resolve
                            (input-state-copy-optional-value-override
                             search-original-buffer)
                            (input-state-search-original-buffer state)
                            :clear-value "")
   :search-original-cursor (input-state-copy-override-resolve
                            (input-state-copy-optional-value-override
                             search-original-cursor)
                            (input-state-search-original-cursor state))
   :search-index (if search-index-supplied-p
                     search-index
                     (input-state-search-index state))
   :undo-stack (if undo-stack-supplied-p
                   undo-stack
                   (input-state-undo-stack state))
   :redo-stack (if redo-stack-supplied-p
                   redo-stack
                   (input-state-redo-stack state))))

(defun %copy-input-state-completion-initargs (values)
  (list :completion-index
        (%input-state-completion-copy-completion-index values)
        :completion-base-buffer
        (%input-state-completion-copy-completion-base-buffer values)
        :completion-base-cursor
        (%input-state-completion-copy-completion-base-cursor values)
        :last-candidates
        (%input-state-completion-copy-last-candidates values)
        :suggestion
        (%input-state-completion-copy-suggestion values)))

(defun %copy-input-state-transient-initargs (values)
  (list :mode
        (%input-state-transient-copy-mode values)
        :vi-count
        (%input-state-transient-copy-vi-count values)
        :vi-visual-anchor
        (%input-state-transient-copy-vi-visual-anchor values)
        :abbreviation-expander
        (%input-state-transient-copy-abbreviation-expander values)
        :kill-ring
        (%input-state-transient-copy-kill-ring values)
        :last-yank-start
        (%input-state-transient-copy-last-yank-start values)
        :last-yank-end
        (%input-state-transient-copy-last-yank-end values)
        :last-yank-index
        (%input-state-transient-copy-last-yank-index values)
        :last-argument-start
        (%input-state-transient-copy-last-argument-start values)
        :last-argument-end
        (%input-state-transient-copy-last-argument-end values)
        :last-argument-index
        (%input-state-transient-copy-last-argument-index values)))

(defun %copy-input-state-session-initargs (values)
  (list :search-query
        (%input-state-session-copy-search-query values)
        :search-original-buffer
        (%input-state-session-copy-search-original-buffer values)
        :search-original-cursor
        (%input-state-session-copy-search-original-cursor values)
        :search-index
        (%input-state-session-copy-search-index values)
        :undo-stack
        (%input-state-session-copy-undo-stack values)
        :redo-stack
        (%input-state-session-copy-redo-stack values)))
