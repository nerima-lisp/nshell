(in-package #:nshell.presentation)

(defun %input-physical-line-start (buffer position)
  (1+ (or (position #\Newline buffer :end position :from-end t)
          -1)))

(defun %input-physical-line-end (buffer position)
  (or (position #\Newline buffer :start position)
      (length buffer)))

(defun %input-visual-column (buffer start end)
  (loop with column = 0
        for grapheme in
          (cl-tty-kit:string-graphemes (subseq buffer start end))
        do (if (string= grapheme (string #\Tab))
               (incf column (- 8 (mod column 8)))
               (incf column (%grapheme-visible-width grapheme)))
        finally (return column)))

(defun %input-position-at-visual-column (buffer start end target-column)
  (loop with position = start
        with column = 0
        for grapheme in
          (cl-tty-kit:string-graphemes (subseq buffer start end))
        for width = (if (string= grapheme (string #\Tab))
                        (- 8 (mod column 8))
                        (%grapheme-visible-width grapheme))
        when (< target-column (+ column width))
          do (return position)
        do (incf position (length grapheme))
           (incf column width)
        finally (return end)))

(defun %move-input-state-vertically (state direction)
  (let* ((buffer (input-state-buffer state))
         (cursor (input-state-cursor-pos state))
         (line-start (%input-physical-line-start buffer cursor))
         (line-end (%input-physical-line-end buffer cursor))
         (history-output (if (eq direction :up) :history-prev :history-next)))
    (cond
      ((not (find #\Newline buffer))
       (values (copy-input-state-with state
                                      :preferred-visual-column nil)
               history-output))
      ((and (eq direction :up) (zerop line-start))
       (values (copy-input-state-with state
                                      :preferred-visual-column nil)
               history-output))
      ((and (eq direction :down) (= line-end (length buffer)))
       (values (copy-input-state-with state
                                      :preferred-visual-column nil)
               history-output))
      (t
       (let* ((preferred-column
                (or (input-state-preferred-visual-column state)
                    (%input-visual-column buffer line-start cursor)))
              (target-start
                (if (eq direction :up)
                    (1+ (or (position #\Newline buffer
                                     :end (1- line-start)
                                     :from-end t)
                            -1))
                    (1+ line-end)))
              (target-end (%input-physical-line-end buffer target-start))
              (target-position
                (%input-position-at-visual-column
                 buffer target-start target-end preferred-column)))
         (values
          (copy-input-state-with
           state
           :cursor-pos target-position
           :preferred-visual-column preferred-column
           :suggestion :clear)
          :redraw))))))

(defun move-input-state-to-physical-line-end (state)
  (let* ((buffer (input-state-buffer state))
         (cursor (input-state-cursor-pos state))
         (line-end (%input-physical-line-end buffer cursor)))
    (copy-input-state-with state
                           :cursor-pos line-end
                           :preferred-visual-column nil
                           :suggestion :clear)))
