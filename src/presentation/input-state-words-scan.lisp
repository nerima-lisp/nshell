;;; Shell token scanning helpers for the input reducer.

(in-package #:nshell.presentation)

(defstruct (shell-token-range
            (:constructor %make-shell-token-range (start end)))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t))

(defun shell-token-end (text start)
  "Return the end index of the shell token in TEXT starting at START."
  (let ((pos start)
        (end (length text))
        (quote nil)
        (escaped nil))
    (block scan
      (loop while (< pos end)
            for ch = (char text pos)
            do (cond
                 ((eq quote #\')
                  (incf pos)
                  (when (char= ch #\')
                    (setf quote nil)))
                 (escaped
                  (setf escaped nil)
                  (incf pos))
                 ((char= ch #\\)
                  (setf escaped t)
                  (incf pos))
                 ((eq quote #\")
                  (incf pos)
                  (when (char= ch #\")
                    (setf quote nil)))
                 ((or (char= ch #\')
                      (char= ch #\"))
                  (setf quote ch)
                  (incf pos))
                 ((nshell.domain.parsing:shell-token-separator-p ch)
                  (return-from scan pos))
                 (t
                  (incf pos)))))
    pos))

(defun shell-token-ranges-before (text limit)
  "Return shell token ranges whose starts are before LIMIT."
  (let ((pos 0)
        (end (min limit (length text)))
        (ranges nil))
    (loop while (< pos end)
          do (if (nshell.domain.parsing:shell-token-separator-p
                  (char text pos))
                 (incf pos)
                 (let ((token-start pos)
                       (token-end (shell-token-end text pos)))
                   (push (%make-shell-token-range token-start token-end)
                         ranges)
                   (setf pos (max token-end (1+ pos))))))
    (nreverse ranges)))

(defun shell-token-range-at-position (text position)
  "Return the shell token range containing POSITION, or NIL."
  (loop for range in (shell-token-ranges-before text (length text))
        when (and (<= (shell-token-range-start range) position)
                  (< position (shell-token-range-end range)))
          do (return range)))

(defun shell-token-range-at-or-after-cursor (buffer cursor)
  "Return the shell token range containing or following CURSOR, or NIL."
  (let* ((end (length buffer))
         (position (min cursor end))
         (ranges (shell-token-ranges-before buffer end)))
    (cond
      ((null ranges)
       nil)
      ((>= position end)
       (car (last ranges)))
      (t
       (loop for range in ranges
             when (or (and (<= (shell-token-range-start range) position)
                           (< position (shell-token-range-end range)))
                      (>= (shell-token-range-start range) position))
               do (return range))))))

(defun shell-token-range-before-position (buffer position)
  "Return the shell token range before POSITION, or NIL."
  (let ((previous nil))
    (dolist (range (shell-token-ranges-before buffer (length buffer)))
      (if (<= (shell-token-range-end range) position)
          (setf previous range)
        (return)))
    previous))

(defun previous-kill-word-start (buffer cursor)
  (let ((pos cursor))
    (loop while (and (> pos 0)
                     (nshell.domain.parsing:shell-token-separator-p
                      (char buffer (1- pos))))
          do (decf pos))
    (let ((range (and (> pos 0)
                      (shell-token-range-at-position buffer (1- pos)))))
      (if range
          (shell-token-range-start range)
          pos))))

(defun next-kill-word-end (buffer cursor)
  (let ((pos cursor)
        (end (length buffer)))
    (loop while (and (< pos end)
                     (nshell.domain.parsing:shell-token-separator-p
                      (char buffer pos)))
          do (incf pos))
    (if (< pos end)
        (let ((range (shell-token-range-at-position buffer pos)))
          (if range
              (shell-token-range-end range)
              (shell-token-end buffer pos)))
        pos)))
