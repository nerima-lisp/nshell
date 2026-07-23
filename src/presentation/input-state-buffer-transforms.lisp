;;; Higher-level buffer transforms for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defparameter *sudo-prefix-text* "sudo ")
(defparameter *sudo-command-text* "sudo")

(define-value-struct %sudo-prefix-operation
    ((kind :insert-prefix :type keyword)))

(defun sudo-prefix-operation-for-buffer (buffer)
  (cond
    ((string= buffer *sudo-command-text*)
     (%make-sudo-prefix-operation :remove-command))
    ((and (>= (length buffer) (length *sudo-prefix-text*))
          (string= (subseq buffer 0 (length *sudo-prefix-text*))
                   *sudo-prefix-text*))
     (%make-sudo-prefix-operation :remove-prefix))
    (t
     (%make-sudo-prefix-operation :insert-prefix))))

(define-value-struct %sudo-prefix-plan
    ((splice nil)
     (cursor-delta 0 :type fixnum)))

(define-value-struct %sudo-prefix-edit
    ((plan nil :type %sudo-prefix-plan)))

(defun sudo-prefix-edit-for-operation (operation)
  (case (sudo-prefix-operation-kind operation)
    (:remove-command
     (%make-sudo-prefix-edit
      (%make-sudo-prefix-plan
       (make-buffer-splice 0 (length *sudo-command-text*))
       (- (length *sudo-command-text*)))))
    (:remove-prefix
     (%make-sudo-prefix-edit
      (%make-sudo-prefix-plan
       (make-buffer-splice 0 (length *sudo-prefix-text*))
       (- (length *sudo-prefix-text*)))))
    (:insert-prefix
     (%make-sudo-prefix-edit
      (%make-sudo-prefix-plan
       (make-buffer-splice 0 0 *sudo-prefix-text*)
       (length *sudo-prefix-text*))))))

(defun sudo-prefix-edit-buffer (edit buffer)
  (buffer-splice-result
   (sudo-prefix-plan-splice (sudo-prefix-edit-plan edit))
   buffer))

(defun sudo-prefix-edit-cursor-pos (edit cursor)
  (max 0 (+ cursor
            (sudo-prefix-plan-cursor-delta (sudo-prefix-edit-plan edit)))))

(defun toggle-sudo-prefix (state)
  (with-buffer-edit (state buffer cursor) state
    (let* ((operation (sudo-prefix-operation-for-buffer buffer))
           (edit (sudo-prefix-edit-for-operation operation)))
      (commit-buffer-edit (sudo-prefix-edit-buffer edit buffer)
                          :cursor-pos (sudo-prefix-edit-cursor-pos edit cursor)))))

(define-value-struct %char-transposition-plan
    ((left 0 :type fixnum)
     (right 0 :type fixnum)
     (cursor-pos 0 :type fixnum)))

(define-value-struct %char-transposition
    ((plan nil :type %char-transposition-plan)))

(defun char-transposition-at-cursor (buffer cursor)
  (let ((buffer-length (length buffer)))
    (unless (or (< buffer-length 2) (zerop cursor))
      (let* ((left (if (= cursor buffer-length)
                       (- buffer-length 2)
                       (1- cursor)))
             (right (1+ left))
             (cursor-pos (if (= cursor buffer-length)
                             buffer-length
                             (1+ cursor))))
        (%make-char-transposition
         (%make-char-transposition-plan left right cursor-pos))))))

(defun char-transposition-buffer (transposition buffer)
  (let* ((plan (char-transposition-plan transposition))
         (new-buffer (copy-seq buffer))
         (left (char-transposition-plan-left plan))
         (right (char-transposition-plan-right plan)))
    (rotatef (char new-buffer left) (char new-buffer right))
    new-buffer))

(defun char-transposition-cursor-pos (transposition)
  (char-transposition-plan-cursor-pos
   (char-transposition-plan transposition)))

(defun transpose-chars-around-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (let ((transposition (char-transposition-at-cursor buffer cursor)))
      (if transposition
          (commit-buffer-edit
           (char-transposition-buffer transposition buffer)
           :cursor-pos (char-transposition-cursor-pos transposition))
          (values state :none)))))
