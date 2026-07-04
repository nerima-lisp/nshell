;;; Word motion helpers for the input reducer.

(in-package #:nshell.presentation)

(defun move-word-left (state)
  (with-input-buffer (state buffer pos) state
    (let ((scan-limit pos))
      (loop while (and (> scan-limit 0)
                       (nshell.domain.parsing:shell-token-separator-p
                        (char buffer (1- scan-limit))))
            do (decf scan-limit))
      (let ((ranges (shell-token-ranges-before buffer scan-limit)))
        (move-cursor-to-clearing-suggestion
         state
         (if ranges
             (shell-token-range-start (car (last ranges)))
             0))))))

(defun move-word-right (state)
  (with-input-buffer (state buffer pos) state
    (let ((end (length buffer)))
      (if (and (< pos end)
               (not (nshell.domain.parsing:shell-token-separator-p
                     (char buffer pos))))
          (let ((range (shell-token-range-at-position buffer pos)))
            (setf pos (if range
                          (shell-token-range-end range)
                          (shell-token-end buffer pos)))))
      (loop while (and (< pos end)
                       (nshell.domain.parsing:shell-token-separator-p
                        (char buffer pos)))
            do (incf pos))
      (move-cursor-to-clearing-suggestion state pos))))

(defun transform-word-at-cursor (state transform)
  "Apply TRANSFORM to the shell token at or after the cursor."
  (with-buffer-edit (state buffer cursor) state
    (let ((range (shell-token-range-at-or-after-cursor buffer cursor)))
      (if (null range)
          (values state :none)
          (let* ((start (shell-token-range-start range))
                 (end (shell-token-range-end range))
                 (word (subseq buffer start end))
                 (new-word (funcall transform word))
                 (new-buffer (concatenate 'string
                                          (subseq buffer 0 start)
                                          new-word
                                          (subseq buffer end))))
            (commit-buffer-edit new-buffer
                                :cursor-pos (+ start (length new-word))))))))

(defun capitalize-token-text (text)
  "Capitalize the first alphabetic character in TEXT and downcase the rest."
  (let ((result (string-downcase text))
        (capitalized nil))
    (loop for index below (length result)
          for char = (char result index)
          until capitalized
          when (alpha-char-p char)
            do (setf (char result index) (char-upcase char)
                     capitalized t))
    result))

(defun upcase-word-at-cursor (state)
  "Uppercase the shell token at or after the cursor."
  (transform-word-at-cursor state #'string-upcase))

(defun downcase-word-at-cursor (state)
  "Lowercase the shell token at or after the cursor."
  (transform-word-at-cursor state #'string-downcase))

(defun capitalize-word-at-cursor (state)
  "Capitalize the shell token at or after the cursor."
  (transform-word-at-cursor state #'capitalize-token-text))

(defstruct (word-transposition
            (:constructor %make-word-transposition
                (left-start left-end middle-start middle-end right-start right-end))
            (:conc-name %word-transposition-))
  (left-start 0 :type fixnum :read-only t)
  (left-end 0 :type fixnum :read-only t)
  (middle-start 0 :type fixnum :read-only t)
  (middle-end 0 :type fixnum :read-only t)
  (right-start 0 :type fixnum :read-only t)
  (right-end 0 :type fixnum :read-only t))

(defun word-transposition-left-start (transposition)
  (%word-transposition-left-start transposition))

(defun word-transposition-left-end (transposition)
  (%word-transposition-left-end transposition))

(defun word-transposition-middle-start (transposition)
  (%word-transposition-middle-start transposition))

(defun word-transposition-middle-end (transposition)
  (%word-transposition-middle-end transposition))

(defun word-transposition-right-start (transposition)
  (%word-transposition-right-start transposition))

(defun word-transposition-right-end (transposition)
  (%word-transposition-right-end transposition))

(defun word-transposition-at-cursor (buffer cursor)
  (let ((right-range (shell-token-range-at-or-after-cursor buffer cursor)))
    (when right-range
      (let ((left-range (shell-token-range-before-position
                         buffer
                         (shell-token-range-start right-range))))
        (when left-range
          (%make-word-transposition
           (shell-token-range-start left-range)
           (shell-token-range-end left-range)
           (shell-token-range-end left-range)
           (shell-token-range-start right-range)
           (shell-token-range-start right-range)
           (shell-token-range-end right-range)))))))

(defun word-transposition-buffer (transposition buffer)
  (concatenate 'string
               (subseq buffer 0 (word-transposition-left-start transposition))
               (subseq buffer
                       (word-transposition-right-start transposition)
                       (word-transposition-right-end transposition))
               (subseq buffer
                       (word-transposition-middle-start transposition)
                       (word-transposition-middle-end transposition))
               (subseq buffer
                       (word-transposition-left-start transposition)
                       (word-transposition-left-end transposition))
               (subseq buffer (word-transposition-right-end transposition))))

(defun word-transposition-cursor-pos (transposition)
  (+ (word-transposition-left-start transposition)
     (- (word-transposition-right-end transposition)
        (word-transposition-right-start transposition))
     (- (word-transposition-middle-end transposition)
        (word-transposition-middle-start transposition))
     (- (word-transposition-left-end transposition)
        (word-transposition-left-start transposition))))

(defun transpose-words-around-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (let ((transposition (word-transposition-at-cursor buffer cursor)))
      (if (null transposition)
          (values state :none)
          (commit-buffer-edit
           (word-transposition-buffer transposition buffer)
           :cursor-pos (word-transposition-cursor-pos transposition))))))