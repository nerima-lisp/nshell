;;; Primitive buffer cursor and deletion operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (buffer-splice
             (:constructor %make-buffer-splice (start end inserted))
             (:conc-name %buffer-splice-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (inserted "" :type string :read-only t))

(defun make-buffer-splice (start end &optional (inserted ""))
  (%make-buffer-splice start end inserted))

(defun buffer-splice-result (splice buffer)
  (concatenate 'string
               (subseq buffer 0 (%buffer-splice-start splice))
               (%buffer-splice-inserted splice)
               (subseq buffer (%buffer-splice-end splice))))

(defun buffer-splice-cursor-pos (splice)
  (+ (%buffer-splice-start splice)
     (length (%buffer-splice-inserted splice))))

(defun %splice-buffer (buffer start end &optional (inserted ""))
  (buffer-splice-result (make-buffer-splice start end inserted) buffer))

(defun backspace-before-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (if (zerop cursor)
        (values state :none)
        (let ((splice (make-buffer-splice (1- cursor) cursor)))
          (commit-buffer-edit (buffer-splice-result splice buffer)
                              :cursor-pos (buffer-splice-cursor-pos splice))))))

(defun delete-char-at-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (if (>= cursor (length buffer))
        (values state :none)
        (let ((splice (make-buffer-splice cursor (1+ cursor))))
          (commit-buffer-edit (buffer-splice-result splice buffer)
                              :cursor-pos (buffer-splice-cursor-pos splice))))))

(defun move-cursor-clearing-suggestion (state delta)
  (with-normalized-input-state (state state)
    (values (copy-input-state-with state
                                   :suggestion :clear
                                   :cursor-pos (+ (input-state-cursor-pos state)
                                                  delta))
            :redraw)))

(defun move-cursor-to-clearing-suggestion (state position)
  (with-normalized-input-state (state state)
    (values (copy-input-state-with state
                                   :suggestion :clear
                                   :cursor-pos position)
            :redraw)))

(defun clear-input-state (state)
  (values (clear-history-search-session-state
           (copy-input-state-clearing-completion state
                                                 :buffer ""
                                                 :cursor-pos 0
                                                 :mode :insert
                                                 :vi-count nil
                                                 :vi-visual-anchor :clear))
          :redraw))

(defun insert-char-at-cursor (state ch)
  (with-buffer-edit (state buffer cursor) state
    (if (>= (length buffer) +max-input-buffer-size+)
        (values state :none)
        (let ((splice (make-buffer-splice cursor cursor (string ch))))
          (commit-buffer-edit (buffer-splice-result splice buffer)
                              :cursor-pos (buffer-splice-cursor-pos splice))))))

(defun insert-string-at-cursor (state text)
  "Insert TEXT at cursor, capped by `+max-input-buffer-size+'."
  (with-buffer-edit (state buffer cursor) state
    (let ((remaining (- +max-input-buffer-size+ (length buffer))))
      (if (or (not (stringp text)) (<= remaining 0) (zerop (length text)))
          (values state :none)
          (let* ((inserted (if (> (length text) remaining)
                               (subseq text 0 remaining)
                               text))
                 (splice (make-buffer-splice cursor cursor inserted)))
            (commit-buffer-edit (buffer-splice-result splice buffer)
                                :cursor-pos (buffer-splice-cursor-pos splice)))))))

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
