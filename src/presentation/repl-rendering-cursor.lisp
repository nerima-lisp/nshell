(in-package #:nshell.presentation)

(define-value-struct %rendered-position
    ((row 0 :type fixnum)
     (column 0 :type fixnum)))

(defun %advance-rendered-character (position char terminal-width)
  (let ((row (rendered-position-row position))
        (column (rendered-position-column position)))
    (if (char= char #\Newline)
        (%make-rendered-position (1+ row) 2)
        (let ((char-width (%char-visible-width char)))
          (when (and terminal-width
                     (plusp terminal-width)
                     (> (+ column char-width) terminal-width))
            (setf row (1+ row)
                  column 0))
          (if (and terminal-width
                   (plusp terminal-width)
                   (> char-width terminal-width))
              (%make-rendered-position (1+ row) (- char-width terminal-width))
              (%make-rendered-position row (+ column char-width)))))))

(defun %advance-rendered-string (position text terminal-width)
  (loop with current = position
        for char across (or text "")
        do (setf current
                 (%advance-rendered-character current char terminal-width))
        finally (return current)))

(defun %initial-rendered-position (prompt-width terminal-width)
  (let ((prompt-width (or prompt-width 0)))
    (if (and terminal-width
           (plusp terminal-width)
           (> prompt-width terminal-width))
        (%make-rendered-position (floor (1- prompt-width) terminal-width)
                                 (1+ (mod (1- prompt-width) terminal-width)))
        (%make-rendered-position 0 prompt-width))))

(defun %rendered-buffer-line-count (text &key suggestion search-suffix terminal-width
                                         (prompt-width 0))
  (let* ((initial-position (%initial-rendered-position prompt-width terminal-width))
         (text-position (%advance-rendered-string initial-position text terminal-width))
         (suggestion-position (%advance-rendered-string text-position
                                                        suggestion
                                                        terminal-width))
         (final-position (%advance-rendered-string suggestion-position
                                                   search-suffix
                                                   terminal-width)))
    (1+ (rendered-position-row final-position))))

(defun %rendered-buffer-position (text cursor prompt-width &key terminal-width)
  (let ((initial-position (%initial-rendered-position prompt-width terminal-width)))
    (loop with current = initial-position
          for index below (max 0 (min cursor (length text)))
          for char = (char text index)
          do (setf current
                   (%advance-rendered-character current char terminal-width))
          finally (return current))))

(defun %cursor-tail-visible-width (text cursor prompt-width suggestion
                                   &optional search-suffix terminal-width)
  (let* ((cursor-position (%rendered-buffer-position text cursor prompt-width
                                                     :terminal-width terminal-width))
         (text-end-position (%rendered-buffer-position text (length text) prompt-width
                                                       :terminal-width terminal-width))
         (suggestion-position (%advance-rendered-string text-end-position
                                                        suggestion
                                                        terminal-width))
         (final-position (%advance-rendered-string suggestion-position
                                                   search-suffix
                                                   terminal-width)))
    (if (= (rendered-position-row cursor-position)
           (rendered-position-row final-position))
        (max 0 (- (rendered-position-column final-position)
                  (rendered-position-column cursor-position)))
        0)))

(defun %move-cursor-to-rendered-position (text cursor prompt-width suggestion search-suffix
                                          &key terminal-width)
  (let* ((target-position (%rendered-buffer-position text cursor prompt-width
                                                     :terminal-width terminal-width))
         (text-end-position (%rendered-buffer-position text (length text) prompt-width
                                                       :terminal-width terminal-width))
         (suggestion-position (%advance-rendered-string text-end-position
                                                        suggestion
                                                        terminal-width))
         (final-position (%advance-rendered-string suggestion-position
                                                   search-suffix
                                                   terminal-width))
         (target-row (rendered-position-row target-position))
         (target-column (rendered-position-column target-position))
         (final-row (rendered-position-row final-position))
         (final-column (rendered-position-column final-position)))
    (let ((rows-up (- final-row target-row)))
      (cond
        ((plusp rows-up)
         (format t "~C[~dA~C[~dG" #\Esc rows-up #\Esc (1+ target-column)))
        (t
         (let ((columns (- final-column target-column)))
           (when (plusp columns)
             (format t "~C[~dD" #\Esc columns))))))))
