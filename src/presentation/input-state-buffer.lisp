;;; Primitive buffer cursor and deletion operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(nshell.util:define-value-struct %buffer-splice
    ((start 0 :type fixnum)
     (end 0 :type fixnum)
     (inserted "" :type string :optional t))
  :constructor make-buffer-splice)

(defun buffer-splice-result (splice buffer)
  (concatenate 'string
               (subseq buffer 0 (%buffer-splice-start splice))
               (%buffer-splice-inserted splice)
               (subseq buffer (%buffer-splice-end splice))))

(defun buffer-splice-cursor-pos (splice)
  (+ (%buffer-splice-start splice)
     (length (%buffer-splice-inserted splice))))

(nshell.util:define-value-struct %buffer-insertion-plan
    ((splice nil))
  :public-accessors nil)

(nshell.util:define-value-struct %buffer-insertion
    ((plan nil))
  :public-accessors nil)

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

(nshell.util:define-value-struct %buffer-deletion
    ((plan nil))
  :public-accessors nil)

(nshell.util:define-value-struct %buffer-deletion-plan
    ((splice nil))
  :public-accessors nil)

(nshell.util:define-value-struct %buffer-deletion-request
    ((kind :before-cursor)
     (cursor 0 :type fixnum))
  :public-accessors nil)

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

(nshell.util:define-value-struct %cursor-move-request
    ((kind :by)
     (cursor 0 :type fixnum)
     (delta 0 :type fixnum)
     (position 0 :type fixnum))
  :public-accessors nil)

(defun cursor-move-request-by (cursor-pos delta)
  (%make-cursor-move-request :by cursor-pos delta 0))

(defun cursor-move-request-to (position)
  (%make-cursor-move-request :to 0 0 position))

(nshell.util:define-value-struct %cursor-move-edit
    ((cursor-pos 0 :type fixnum))
  :public-accessors nil)

(defun cursor-move-edit-for-request (request)
  (case (%cursor-move-request-kind request)
    (:by
     (%make-cursor-move-edit
      (+ (%cursor-move-request-cursor request)
         (%cursor-move-request-delta request))))
    (:to
     (%make-cursor-move-edit
      (%cursor-move-request-position request)))))

(nshell.util:define-value-struct %buffer-clear-plan
    ((buffer "" :type string)
     (cursor-pos 0 :type fixnum)
     (mode :insert)
     (vi-count nil)
     (vi-visual-anchor :clear)
     (clear-completion-p t :type boolean)
     (clear-history-search-p t :type boolean))
  :public-accessors nil
  :keyword-constructor t)

(defun make-buffer-clear-plan ()
  (%make-buffer-clear-plan
   :buffer ""
   :cursor-pos 0
   :mode :insert
   :vi-count nil
   :vi-visual-anchor :clear
   :clear-completion-p t
   :clear-history-search-p t))

(nshell.util:define-value-struct %buffer-clear-edit
    ((plan nil))
  :public-accessors nil)

(defun make-buffer-clear-edit ()
  (%make-buffer-clear-edit (make-buffer-clear-plan)))
