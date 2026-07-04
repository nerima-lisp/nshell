;;; Word motion helpers for the input reducer.

(in-package #:nshell.presentation)

(defstruct (word-motion-target
            (:constructor %make-word-motion-target (cursor-pos))
            (:conc-name %word-motion-target-))
  (cursor-pos 0 :type fixnum :read-only t))

(defun word-motion-target-cursor-pos (target)
  (%word-motion-target-cursor-pos target))

(defun word-motion-target-left (buffer cursor)
  (let ((scan-limit cursor))
    (loop while (and (> scan-limit 0)
                     (nshell.domain.parsing:shell-token-separator-p
                      (char buffer (1- scan-limit))))
          do (decf scan-limit))
    (let ((ranges (shell-token-ranges-before buffer scan-limit)))
      (%make-word-motion-target
       (if ranges
           (shell-token-range-start (car (last ranges)))
           0)))))

(defun word-motion-target-right (buffer cursor)
  (let ((pos cursor)
        (end (length buffer)))
    (when (and (< pos end)
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
    (%make-word-motion-target pos)))

(defun move-word-left (state)
  (with-input-buffer (state buffer cursor) state
    (move-cursor-to-clearing-suggestion
     state
     (word-motion-target-cursor-pos
      (word-motion-target-left buffer cursor)))))

(defun move-word-right (state)
  (with-input-buffer (state buffer cursor) state
    (move-cursor-to-clearing-suggestion
     state
     (word-motion-target-cursor-pos
      (word-motion-target-right buffer cursor)))))

(defstruct (word-transform-plan
            (:constructor %make-word-transform-plan (start end replacement))
            (:conc-name %word-transform-plan-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (replacement "" :type string :read-only t))

(defstruct (word-transform-edit
            (:constructor %make-word-transform-edit (plan))
            (:conc-name %word-transform-edit-))
  (plan (error "PLAN is required.") :type word-transform-plan :read-only t))

(defun word-transform-edit-plan (edit)
  (%word-transform-edit-plan edit))

(defun word-transform-plan-start (plan)
  (%word-transform-plan-start plan))

(defun word-transform-plan-end (plan)
  (%word-transform-plan-end plan))

(defun word-transform-plan-replacement (plan)
  (%word-transform-plan-replacement plan))

(defun word-transform-edit-at-cursor (buffer cursor transform)
  (let ((range (shell-token-range-at-or-after-cursor buffer cursor)))
    (when range
      (%make-word-transform-edit
       (%make-word-transform-plan
        (shell-token-range-start range)
        (shell-token-range-end range)
        (funcall transform
                 (subseq buffer
                         (shell-token-range-start range)
                         (shell-token-range-end range))))))))

(defun word-transform-edit-buffer (edit buffer)
  (let ((plan (word-transform-edit-plan edit)))
    (concatenate 'string
                 (subseq buffer 0 (word-transform-plan-start plan))
                 (word-transform-plan-replacement plan)
                 (subseq buffer (word-transform-plan-end plan)))))

(defun word-transform-edit-cursor-pos (edit)
  (let ((plan (word-transform-edit-plan edit)))
    (+ (word-transform-plan-start plan)
       (length (word-transform-plan-replacement plan)))))

(defun transform-word-at-cursor (state transform)
  "Apply TRANSFORM to the shell token at or after the cursor."
  (with-buffer-edit (state buffer cursor) state
    (let ((edit (word-transform-edit-at-cursor buffer cursor transform)))
      (if (null edit)
          (values state :none)
          (commit-buffer-edit
           (word-transform-edit-buffer edit buffer)
           :cursor-pos (word-transform-edit-cursor-pos edit))))))

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

(defstruct (word-transposition-plan
            (:constructor %make-word-transposition-plan
                (left-start left-end middle-start middle-end right-start right-end))
            (:conc-name %word-transposition-plan-))
  (left-start 0 :type fixnum :read-only t)
  (left-end 0 :type fixnum :read-only t)
  (middle-start 0 :type fixnum :read-only t)
  (middle-end 0 :type fixnum :read-only t)
  (right-start 0 :type fixnum :read-only t)
  (right-end 0 :type fixnum :read-only t))

(defstruct (word-transposition
            (:constructor %make-word-transposition (plan))
            (:conc-name %word-transposition-))
  (plan (error "PLAN is required.") :type word-transposition-plan :read-only t))

(defun word-transposition-plan (transposition)
  (%word-transposition-plan transposition))

(defun word-transposition-plan-left-start (plan)
  (%word-transposition-plan-left-start plan))

(defun word-transposition-plan-left-end (plan)
  (%word-transposition-plan-left-end plan))

(defun word-transposition-plan-middle-start (plan)
  (%word-transposition-plan-middle-start plan))

(defun word-transposition-plan-middle-end (plan)
  (%word-transposition-plan-middle-end plan))

(defun word-transposition-plan-right-start (plan)
  (%word-transposition-plan-right-start plan))

(defun word-transposition-plan-right-end (plan)
  (%word-transposition-plan-right-end plan))

(defun word-transposition-at-cursor (buffer cursor)
  (let ((right-range (shell-token-range-at-or-after-cursor buffer cursor)))
    (when right-range
      (let ((left-range (shell-token-range-before-position
                         buffer
                         (shell-token-range-start right-range))))
        (when left-range
          (%make-word-transposition
           (%make-word-transposition-plan
            (shell-token-range-start left-range)
            (shell-token-range-end left-range)
            (shell-token-range-end left-range)
            (shell-token-range-start right-range)
            (shell-token-range-start right-range)
            (shell-token-range-end right-range))))))))

(defun word-transposition-buffer (transposition buffer)
  (let ((plan (word-transposition-plan transposition)))
    (concatenate 'string
                 (subseq buffer 0 (word-transposition-plan-left-start plan))
                 (subseq buffer
                         (word-transposition-plan-right-start plan)
                         (word-transposition-plan-right-end plan))
                 (subseq buffer
                         (word-transposition-plan-middle-start plan)
                         (word-transposition-plan-middle-end plan))
                 (subseq buffer
                         (word-transposition-plan-left-start plan)
                         (word-transposition-plan-left-end plan))
                 (subseq buffer (word-transposition-plan-right-end plan)))))

(defun word-transposition-cursor-pos (transposition)
  (let ((plan (word-transposition-plan transposition)))
    (+ (word-transposition-plan-left-start plan)
       (- (word-transposition-plan-right-end plan)
          (word-transposition-plan-right-start plan))
       (- (word-transposition-plan-middle-end plan)
          (word-transposition-plan-middle-start plan))
       (- (word-transposition-plan-left-end plan)
          (word-transposition-plan-left-start plan)))))

(defun transpose-words-around-cursor (state)
  (with-buffer-edit (state buffer cursor) state
    (let ((transposition (word-transposition-at-cursor buffer cursor)))
      (if (null transposition)
          (values state :none)
          (commit-buffer-edit
           (word-transposition-buffer transposition buffer)
           :cursor-pos (word-transposition-cursor-pos transposition))))))
