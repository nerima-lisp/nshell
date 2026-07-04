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

(defstruct (buffer-insertion
             (:constructor %make-buffer-insertion (splice))
             (:conc-name %buffer-insertion-))
  splice)

(defun buffer-insertion-at-cursor (buffer cursor text)
  (when (stringp text)
    (let ((remaining (- +max-input-buffer-size+ (length buffer))))
      (when (and (plusp remaining)
                 (plusp (length text)))
        (let ((inserted (if (> (length text) remaining)
                            (subseq text 0 remaining)
                            text)))
          (%make-buffer-insertion
           (make-buffer-splice cursor cursor inserted)))))))

(defun buffer-insertion-result (insertion buffer)
  (buffer-splice-result (%buffer-insertion-splice insertion) buffer))

(defun buffer-insertion-cursor-pos (insertion)
  (buffer-splice-cursor-pos (%buffer-insertion-splice insertion)))

(defstruct (buffer-deletion
             (:constructor %make-buffer-deletion (splice))
             (:conc-name %buffer-deletion-))
  splice)

(defstruct (buffer-deletion-request
             (:constructor %make-buffer-deletion-request (kind cursor))
             (:conc-name %buffer-deletion-request-))
  (kind :before-cursor :read-only t)
  (cursor 0 :type fixnum :read-only t))

(defun buffer-deletion-request-before-cursor (cursor)
  (%make-buffer-deletion-request :before-cursor cursor))

(defun buffer-deletion-request-at-cursor (cursor)
  (%make-buffer-deletion-request :at-cursor cursor))

(defun buffer-deletion-request-kind (request)
  (%buffer-deletion-request-kind request))

(defun buffer-deletion-request-cursor (request)
  (%buffer-deletion-request-cursor request))

(defun buffer-deletion-for-request (request buffer)
  (let ((cursor (buffer-deletion-request-cursor request)))
    (case (buffer-deletion-request-kind request)
      (:before-cursor
       (unless (zerop cursor)
         (%make-buffer-deletion
          (make-buffer-splice (1- cursor) cursor))))
      (:at-cursor
       (unless (>= cursor (length buffer))
         (%make-buffer-deletion
          (make-buffer-splice cursor (1+ cursor))))))))

(defun buffer-deletion-result (deletion buffer)
  (buffer-splice-result (%buffer-deletion-splice deletion) buffer))

(defun buffer-deletion-cursor-pos (deletion)
  (buffer-splice-cursor-pos (%buffer-deletion-splice deletion)))

(defstruct (cursor-move-request
             (:constructor %make-cursor-move-request (kind cursor delta position))
             (:conc-name %cursor-move-request-))
  (kind :by :read-only t)
  (cursor 0 :type fixnum :read-only t)
  (delta 0 :type fixnum :read-only t)
  (position 0 :type fixnum :read-only t))

(defun cursor-move-request-by (cursor-pos delta)
  (%make-cursor-move-request :by cursor-pos delta 0))

(defun cursor-move-request-to (position)
  (%make-cursor-move-request :to 0 0 position))

(defun cursor-move-request-kind (request)
  (%cursor-move-request-kind request))

(defun cursor-move-request-cursor (request)
  (%cursor-move-request-cursor request))

(defun cursor-move-request-delta (request)
  (%cursor-move-request-delta request))

(defun cursor-move-request-position (request)
  (%cursor-move-request-position request))

(defstruct (cursor-move-edit
             (:constructor %make-cursor-move-edit (cursor-pos))
             (:conc-name %cursor-move-edit-))
  (cursor-pos 0 :type fixnum :read-only t))

(defun cursor-move-edit-for-request (request)
  (case (cursor-move-request-kind request)
    (:by
     (%make-cursor-move-edit
      (+ (cursor-move-request-cursor request)
         (cursor-move-request-delta request))))
    (:to
     (%make-cursor-move-edit
      (cursor-move-request-position request)))))

(defun cursor-move-edit-cursor-pos (edit)
  (%cursor-move-edit-cursor-pos edit))

(defun commit-cursor-move-edit (state edit)
  (copy-input-state-with state
                         :suggestion :clear
                         :cursor-pos (cursor-move-edit-cursor-pos edit)))

(defstruct (buffer-clear-edit
             (:constructor %make-buffer-clear-edit ())
             (:conc-name %buffer-clear-edit-)))

(defun make-buffer-clear-edit ()
  (%make-buffer-clear-edit))

(defun commit-buffer-clear-edit (state edit)
  (declare (ignore edit))
  (clear-history-search-session-state
   (copy-input-state-clearing-completion state
                                         :buffer ""
                                         :cursor-pos 0
                                         :mode :insert
                                         :vi-count nil
                                         :vi-visual-anchor :clear)))

(defun backspace-before-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (let ((deletion (buffer-deletion-for-request
                     (buffer-deletion-request-before-cursor cursor)
                     buffer)))
      (if deletion
          (commit-buffer-edit (buffer-deletion-result deletion buffer)
                              :cursor-pos
                              (buffer-deletion-cursor-pos deletion))
          (values state :none)))))

(defun delete-char-at-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (let ((deletion (buffer-deletion-for-request
                     (buffer-deletion-request-at-cursor cursor)
                     buffer)))
      (if deletion
          (commit-buffer-edit (buffer-deletion-result deletion buffer)
                              :cursor-pos
                              (buffer-deletion-cursor-pos deletion))
          (values state :none)))))

(defun move-cursor-clearing-suggestion (state delta)
  (with-normalized-input-state (state state)
    (values (commit-cursor-move-edit
             state
             (cursor-move-edit-for-request
              (cursor-move-request-by (input-state-cursor-pos state) delta)))
            :redraw)))

(defun move-cursor-to-clearing-suggestion (state position)
  (with-normalized-input-state (state state)
    (values (commit-cursor-move-edit
             state
             (cursor-move-edit-for-request
              (cursor-move-request-to position)))
            :redraw)))

(defun clear-input-state (state)
  (values (commit-buffer-clear-edit state (make-buffer-clear-edit))
          :redraw))

(defun insert-char-at-cursor (state ch)
  (with-buffer-edit (state buffer cursor) state
    (let ((insertion (buffer-insertion-at-cursor buffer cursor (string ch))))
      (if insertion
          (commit-buffer-edit (buffer-insertion-result insertion buffer)
                              :cursor-pos
                              (buffer-insertion-cursor-pos insertion))
          (values state :none)))))

(defun insert-string-at-cursor (state text)
  "Insert TEXT at cursor, capped by `+max-input-buffer-size+'."
  (with-buffer-edit (state buffer cursor) state
    (let ((insertion (buffer-insertion-at-cursor buffer cursor text)))
      (if insertion
          (commit-buffer-edit (buffer-insertion-result insertion buffer)
                              :cursor-pos
                              (buffer-insertion-cursor-pos insertion))
          (values state :none)))))

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
