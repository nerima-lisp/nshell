; Input state copy-with-overrides: per-group MAKE-INPUT-STATE initarg builders
; for the completion, transient, and session fields.
;
; Each override field arrives as a (SUPPLIED-P VALUE) pair from
; COPY-INPUT-STATE-WITH and is resolved against the current STATE through
; INPUT-STATE-COPY-OVERRIDE-*.  The builders return plain MAKE-INPUT-STATE
; initarg plists directly, which COPY-INPUT-STATE-WITH appends together -- there
; is no intermediate record between the resolved values and MAKE-INPUT-STATE.
(in-package #:nshell.presentation)

(defun clamp-cursor (position buffer)
  (max 0 (min position (length buffer))))

(define-value-struct %input-state-copy-override
    ((kind nil)
     (value nil)))

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

(defmacro %input-state-copy-args (state &rest names)
  "Expand to a spliceable MAKE-INPUT-STATE initarg (LIST :NAME1 value1 ...), one
pair per symbol in NAMES, for the standard supplied-p/override copy pattern
shared by most INPUT-STATE slots: NAME's new value if supplied and accepted,
else STATE's current value. Each NAME must be bound in the caller's
lambda-list together with a NAME-SUPPLIED-P flag; STATE must evaluate to the
source INPUT-STATE. Fields needing a clamp (vi-visual-anchor), an acceptp
predicate, an unconditional override (mode), or an optional-value override
with no supplied-p (kill-ring) keep their own explicit form instead -- this
macro only ever emits the one shape all its callers share verbatim."
  `(list ,@(loop for name in names
                 for name-string = (string name)
                 for supplied-p = (intern (concatenate 'string name-string "-SUPPLIED-P"))
                 for accessor = (intern (concatenate 'string "INPUT-STATE-" name-string))
                 for keyword = (intern name-string :keyword)
                 append `(,keyword (input-state-copy-override-resolve
                                     (input-state-copy-override-for ,supplied-p ,name)
                                     (,accessor ,state))))))

(defmacro %input-state-copy-supplied-args (state &rest names)
  "Expand to a spliceable MAKE-INPUT-STATE initarg (LIST :NAME1 value1 ...), one
pair per symbol in NAMES, for the plain supplied-p-or-current pattern (no
override machinery: NAME's new value verbatim if supplied, else STATE's
current value). Same NAME/STATE contract as %INPUT-STATE-COPY-ARGS."
  `(list ,@(loop for name in names
                 for name-string = (string name)
                 for supplied-p = (intern (concatenate 'string name-string "-SUPPLIED-P"))
                 for accessor = (intern (concatenate 'string "INPUT-STATE-" name-string))
                 for keyword = (intern name-string :keyword)
                 append `(,keyword (if ,supplied-p ,name (,accessor ,state))))))

(defun %copy-input-state-completion-initargs (state
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
  ;; A fresh completion session (index -1) drops any carried base position.
  (let ((reset-base-p (and completion-index-supplied-p
                           (= completion-index -1))))
    (append
     (%input-state-copy-supplied-args state completion-index)
     (list
      :completion-base-buffer (if reset-base-p
                                  nil
                                  (input-state-copy-override-resolve
                                   (input-state-copy-override-for
                                    completion-base-supplied-p
                                    completion-base-buffer)
                                   (input-state-completion-base-buffer state)
                                   :acceptp #'stringp))
      :completion-base-cursor (if reset-base-p
                                  nil
                                  (input-state-copy-override-resolve
                                   (input-state-copy-override-for
                                    completion-base-cursor-supplied-p
                                    completion-base-cursor)
                                   (input-state-completion-base-cursor state)
                                   :acceptp #'integerp)))
     (%input-state-copy-args state last-candidates suggestion))))

(defun %copy-input-state-transient-initargs (state
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
  (append
   (list
    :mode (or mode (input-state-mode state))
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
                (input-state-kill-ring state)))
   (%input-state-copy-args state
     vi-count
     last-yank-start last-yank-end last-yank-index
     last-argument-start last-argument-end last-argument-index)))

(defun %copy-input-state-session-initargs (state
                                           search-query
                                           search-original-buffer
                                           search-original-cursor
                                           search-index-supplied-p
                                           search-index
                                           undo-stack-supplied-p
                                           undo-stack
                                           redo-stack-supplied-p
                                           redo-stack)
  (append
   (list
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
                             (input-state-search-original-cursor state)))
   (%input-state-copy-supplied-args state search-index undo-stack redo-stack)))
