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
         (if ranges (caar (last ranges)) 0))))))

(defun move-word-right (state)
  (with-input-buffer (state buffer pos) state
    (let ((end (length buffer)))
      (if (and (< pos end)
               (not (nshell.domain.parsing:shell-token-separator-p
                     (char buffer pos))))
          (multiple-value-bind (token-start token-end token-found-p)
              (shell-token-range-at-position buffer pos)
            (declare (ignore token-start))
            (setf pos (if token-found-p
                          token-end
                          (shell-token-end buffer pos)))))
      (loop while (and (< pos end)
                       (nshell.domain.parsing:shell-token-separator-p
                        (char buffer pos)))
            do (incf pos))
      (move-cursor-to-clearing-suggestion state pos))))

(defun transform-word-at-cursor (state transform)
  "Apply TRANSFORM to the shell token at or after the cursor."
  (with-buffer-edit (state buffer cursor) state
    (multiple-value-bind (start end found-p)
        (shell-token-range-at-or-after-cursor buffer cursor)
      (if (not found-p)
          (values state :none)
          (let* ((word (subseq buffer start end))
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

(defun transpose-words-around-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (multiple-value-bind (right-start right-end right-found-p)
        (shell-token-range-at-or-after-cursor buffer cursor)
      (if (not right-found-p)
          (values state :none)
          (multiple-value-bind (left-start left-end left-found-p)
              (shell-token-range-before-position buffer right-start)
            (if (not left-found-p)
                (values state :none)
                (let* ((left-word (subseq buffer left-start left-end))
                       (middle (subseq buffer left-end right-start))
                       (right-word (subseq buffer right-start right-end))
                       (new-buffer
                         (concatenate 'string
                                      (subseq buffer 0 left-start)
                                      right-word
                                      middle
                                      left-word
                                      (subseq buffer right-end)))
                       (new-cursor (+ left-start
                                      (length right-word)
                                      (length middle)
                                      (length left-word))))
                  (commit-buffer-edit new-buffer
                                      :cursor-pos new-cursor))))))))
