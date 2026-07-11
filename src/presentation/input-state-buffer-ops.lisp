;;; Buffer editing operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defmacro %with-buffer-edit-or-none ((state buffer cursor edit) request-form &body body)
  `(with-buffer-edit (,state ,buffer ,cursor) ,state
     (let ((,edit ,request-form))
       (if ,edit
           (progn ,@body)
           (values ,state :none)))))

(defun apply-buffer-clear-plan (state plan)
  (let ((state (copy-input-state-with state
                                      :buffer (%buffer-clear-plan-buffer plan)
                                      :cursor-pos
                                      (%buffer-clear-plan-cursor-pos plan)
                                      :mode (%buffer-clear-plan-mode plan)
                                      :vi-count
                                      (%buffer-clear-plan-vi-count plan)
                                      :vi-visual-anchor
                                      (%buffer-clear-plan-vi-visual-anchor plan))))
    (when (%buffer-clear-plan-clear-completion-p plan)
      (setf state (clear-completion-session-state state)))
    (if (%buffer-clear-plan-clear-history-search-p plan)
        (clear-history-search-session-state state)
        state)))

(defun commit-buffer-clear-edit (state edit)
  (apply-buffer-clear-plan state (%buffer-clear-edit-plan edit)))

(defun %commit-cursor-move-request (state request)
  (values (commit-cursor-move-edit
           state
           (cursor-move-edit-for-request request))
          :redraw))

(defun commit-cursor-move-edit (state edit)
  (copy-input-state-with state
                         :suggestion :clear
                         :cursor-pos (%cursor-move-edit-cursor-pos edit)))

(defun backspace-before-cursor (state)
  (%with-buffer-edit-or-none (state buffer cursor deletion)
      (buffer-deletion-for-request (buffer-deletion-request-before-cursor cursor)
                                   buffer)
    (commit-buffer-edit (buffer-deletion-result deletion buffer)
                        :cursor-pos
                        (buffer-deletion-cursor-pos deletion))))

(defun delete-char-at-cursor (state)
  (%with-buffer-edit-or-none (state buffer cursor deletion)
      (buffer-deletion-for-request (buffer-deletion-request-at-cursor cursor)
                                   buffer)
    (commit-buffer-edit (buffer-deletion-result deletion buffer)
                        :cursor-pos
                        (buffer-deletion-cursor-pos deletion))))

(defun move-cursor-clearing-suggestion (state delta)
  (with-normalized-input-state (state state)
    (%commit-cursor-move-request
     state
     (cursor-move-request-by (input-state-cursor-pos state) delta))))

(defun move-cursor-to-clearing-suggestion (state position)
  (with-normalized-input-state (state state)
    (%commit-cursor-move-request state (cursor-move-request-to position))))

(defun clear-input-state (state)
  (values (commit-buffer-clear-edit state (make-buffer-clear-edit))
          :redraw))

(defun insert-char-at-cursor (state ch)
  (%with-buffer-edit-or-none (state buffer cursor insertion)
      (buffer-insertion-at-cursor buffer cursor (string ch))
    (commit-buffer-edit (buffer-insertion-result insertion buffer)
                        :cursor-pos
                        (buffer-insertion-cursor-pos insertion))))

(defun insert-string-at-cursor (state text)
  "Insert TEXT at cursor, capped by `+max-input-buffer-size+'."
  (%with-buffer-edit-or-none (state buffer cursor insertion)
      (buffer-insertion-at-cursor buffer cursor text)
    (commit-buffer-edit (buffer-insertion-result insertion buffer)
                        :cursor-pos
                        (buffer-insertion-cursor-pos insertion))))

(defun normalize-paste-text (text)
  "Normalize pasted line endings to LF while preserving other text."
  (when (stringp text)
    (with-output-to-string (stream)
      (loop with index = 0
            while (< index (length text))
            for ch = (char text index)
            do (cond
                 ((char= ch #\Return)
                  (write-char #\Newline stream)
                  (incf index)
                  (when (and (< index (length text))
                             (char= (char text index) #\Newline))
                    (incf index)))
                 (t
                  (write-char ch stream)
                  (incf index)))))))

(defun insert-paste-at-cursor (state event)
  (insert-string-at-cursor state
                           (normalize-paste-text
                            (getf (nshell.domain.input:key-event-data event)
                                  :text))))

(defun insert-newline-at-cursor (state &key (indent 0))
  "Insert a logical continuation newline at the cursor."
  (let ((newline (concatenate 'string
                              (string #\Newline)
                              (make-string (max 0 indent)
                                           :initial-element #\Space))))
    (insert-string-at-cursor state newline)))
