;;; Higher-level buffer transforms for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (sudo-prefix-edit
             (:constructor %make-sudo-prefix-edit (splice cursor-delta))
             (:conc-name %sudo-prefix-edit-))
  splice
  (cursor-delta 0 :type fixnum :read-only t))

(defun sudo-prefix-edit-for-buffer (buffer)
  (let ((prefix "sudo "))
    (cond
      ((string= buffer "sudo")
       (%make-sudo-prefix-edit (make-buffer-splice 0 4) -4))
      ((and (>= (length buffer) (length prefix))
            (string= (subseq buffer 0 (length prefix)) prefix))
       (%make-sudo-prefix-edit (make-buffer-splice 0 (length prefix))
                               (- (length prefix))))
      (t
       (%make-sudo-prefix-edit (make-buffer-splice 0 0 prefix)
                               (length prefix))))))

(defun sudo-prefix-edit-buffer (edit buffer)
  (buffer-splice-result (%sudo-prefix-edit-splice edit) buffer))

(defun sudo-prefix-edit-cursor-pos (edit cursor)
  (max 0 (+ cursor (%sudo-prefix-edit-cursor-delta edit))))

(defun toggle-sudo-prefix (state)
  (with-buffer-edit (state buffer cursor) state
    (let ((edit (sudo-prefix-edit-for-buffer buffer)))
      (commit-buffer-edit (sudo-prefix-edit-buffer edit buffer)
                          :cursor-pos (sudo-prefix-edit-cursor-pos edit cursor)))))

(defstruct (char-transposition
             (:constructor %make-char-transposition (left right cursor-pos))
             (:conc-name %char-transposition-))
  (left 0 :type fixnum :read-only t)
  (right 0 :type fixnum :read-only t)
  (cursor-pos 0 :type fixnum :read-only t))

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
        (%make-char-transposition left right cursor-pos)))))

(defun char-transposition-buffer (transposition buffer)
  (let ((new-buffer (copy-seq buffer))
        (left (%char-transposition-left transposition))
        (right (%char-transposition-right transposition)))
    (rotatef (char new-buffer left) (char new-buffer right))
    new-buffer))

(defun char-transposition-cursor-pos (transposition)
  (%char-transposition-cursor-pos transposition))

(defun transpose-chars-around-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (let ((transposition (char-transposition-at-cursor buffer cursor)))
      (if transposition
          (commit-buffer-edit
           (char-transposition-buffer transposition buffer)
           :cursor-pos (char-transposition-cursor-pos transposition))
          (values state :none)))))
