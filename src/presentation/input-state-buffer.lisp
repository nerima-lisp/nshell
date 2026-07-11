;;; Primitive buffer cursor and deletion operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (%buffer-splice
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

(defstruct (%buffer-insertion-plan
             (:constructor %make-buffer-insertion-plan (splice))
             (:conc-name %buffer-insertion-plan-))
  splice)

(defstruct (%buffer-insertion
             (:constructor %make-buffer-insertion (plan))
             (:conc-name %buffer-insertion-))
  plan)

(defun buffer-insertion-at-cursor (buffer cursor text)
  (when (stringp text)
    (let ((remaining (- +max-input-buffer-size+ (length buffer))))
      (when (and (plusp remaining)
                 (plusp (length text)))
        (let ((inserted (if (> (length text) remaining)
                            (subseq text 0 remaining)
                            text)))
          (%make-buffer-insertion
           (%make-buffer-insertion-plan
            (make-buffer-splice cursor cursor inserted))))))))

(defun buffer-insertion-result (insertion buffer)
  (buffer-splice-result
   (%buffer-insertion-plan-splice (%buffer-insertion-plan insertion))
   buffer))

(defun buffer-insertion-cursor-pos (insertion)
  (buffer-splice-cursor-pos
   (%buffer-insertion-plan-splice (%buffer-insertion-plan insertion))))

(defstruct (%buffer-deletion
             (:constructor %make-buffer-deletion (plan))
             (:conc-name %buffer-deletion-))
  plan)

(defstruct (%buffer-deletion-plan
             (:constructor %make-buffer-deletion-plan (splice))
             (:conc-name %buffer-deletion-plan-))
  splice)

(defstruct (%buffer-deletion-request
             (:constructor %make-buffer-deletion-request (kind cursor))
             (:conc-name %buffer-deletion-request-))
  (kind :before-cursor :read-only t)
  (cursor 0 :type fixnum :read-only t))

(defun buffer-deletion-request-before-cursor (cursor)
  (%make-buffer-deletion-request :before-cursor cursor))

(defun buffer-deletion-request-at-cursor (cursor)
  (%make-buffer-deletion-request :at-cursor cursor))

(defun buffer-deletion-for-request (request buffer)
  (let ((cursor (%buffer-deletion-request-cursor request)))
    (case (%buffer-deletion-request-kind request)
      (:before-cursor
       (unless (zerop cursor)
         (%make-buffer-deletion
          (%make-buffer-deletion-plan
           (make-buffer-splice (1- cursor) cursor)))))
      (:at-cursor
       (unless (>= cursor (length buffer))
         (%make-buffer-deletion
          (%make-buffer-deletion-plan
           (make-buffer-splice cursor (1+ cursor)))))))))

(defun buffer-deletion-result (deletion buffer)
  (buffer-splice-result
   (%buffer-deletion-plan-splice (%buffer-deletion-plan deletion))
   buffer))

(defun buffer-deletion-cursor-pos (deletion)
  (buffer-splice-cursor-pos
   (%buffer-deletion-plan-splice (%buffer-deletion-plan deletion))))

(defstruct (%cursor-move-request
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

(defstruct (%cursor-move-edit
             (:constructor %make-cursor-move-edit (cursor-pos))
             (:conc-name %cursor-move-edit-))
  (cursor-pos 0 :type fixnum :read-only t))

(defun cursor-move-edit-for-request (request)
  (case (%cursor-move-request-kind request)
    (:by
     (%make-cursor-move-edit
      (+ (%cursor-move-request-cursor request)
         (%cursor-move-request-delta request))))
    (:to
     (%make-cursor-move-edit
      (%cursor-move-request-position request)))))

(defstruct (%buffer-clear-plan
             (:constructor %make-buffer-clear-plan
                 (&key buffer cursor-pos mode vi-count vi-visual-anchor
                       clear-completion-p clear-history-search-p))
             (:conc-name %buffer-clear-plan-))
  (buffer "" :type string :read-only t)
  (cursor-pos 0 :type fixnum :read-only t)
  (mode :insert :read-only t)
  (vi-count nil :read-only t)
  (vi-visual-anchor :clear :read-only t)
  (clear-completion-p t :type boolean :read-only t)
  (clear-history-search-p t :type boolean :read-only t))

(defun make-buffer-clear-plan ()
  (%make-buffer-clear-plan
   :buffer ""
   :cursor-pos 0
   :mode :insert
   :vi-count nil
   :vi-visual-anchor :clear
   :clear-completion-p t
   :clear-history-search-p t))

(defstruct (%buffer-clear-edit
             (:constructor %make-buffer-clear-edit (plan))
             (:conc-name %buffer-clear-edit-))
  plan)

(defun make-buffer-clear-edit ()
  (%make-buffer-clear-edit (make-buffer-clear-plan)))
