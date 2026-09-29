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

(defun %rendered-character-start-position (position char terminal-width)
  "Return the cell at which CHAR is rendered from POSITION."
  (if (char= char #\Newline)
      position
      (let ((row (rendered-position-row position))
            (column (rendered-position-column position))
            (char-width (%char-visible-width char)))
        (when (and terminal-width
                   (plusp terminal-width)
                   (> (+ column char-width) terminal-width))
          (setf row (1+ row)
                column 0))
        (%make-rendered-position row column))))

(defun %advance-rendered-string (position text terminal-width)
  (loop with current = position
        for grapheme in (cl-tty-kit:string-graphemes (or text ""))
        do (setf current
                 (%advance-rendered-grapheme current grapheme terminal-width))
        finally (return current)))

(defun %advance-rendered-grapheme (position grapheme terminal-width)
  (if (and (= (length grapheme) 1)
           (char= (char grapheme 0) #\Newline))
      (%advance-rendered-character position #\Newline terminal-width)
      (let ((width (%string-visible-width grapheme)))
        (%advance-rendered-width position width terminal-width))))

(defun %rendered-grapheme-start-position (position grapheme terminal-width)
  (if (and (= (length grapheme) 1)
           (char= (char grapheme 0) #\Newline))
      position
      (let ((width (%string-visible-width grapheme)))
        (if (and terminal-width
                 (plusp terminal-width)
                 (> (+ (rendered-position-column position) width)
                    terminal-width))
            (%make-rendered-position
             (1+ (rendered-position-row position))
             0)
            position))))

(defun %advance-rendered-width (position width terminal-width)
  (let ((row (rendered-position-row position))
        (column (rendered-position-column position)))
    (when (and terminal-width
               (plusp terminal-width)
               (> (+ column width) terminal-width))
      (setf row (1+ row)
            column 0))
    (if (and terminal-width
             (plusp terminal-width)
             (> width terminal-width))
        (%make-rendered-position (1+ row) (- width terminal-width))
        (%make-rendered-position row (+ column width)))))

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
          with consumed = 0
          for grapheme in (cl-tty-kit:string-graphemes text)
          while (< consumed cursor)
          do (incf consumed (length grapheme))
             (setf current
                   (%advance-rendered-grapheme current grapheme terminal-width))
          finally (return current))))

(defun %rendered-buffer-index-at-position (text row column prompt-width
                                           &key terminal-width
                                             (origin-row 1)
                                             (origin-column 1))
  "Map a 1-based terminal cell to a buffer index.

The prompt origin and rendered cursor geometry are kept in the presentation
layer, so this function remains deterministic and does not perform terminal
I/O. NIL means that the cell belongs to the prompt, continuation prompt, or
lies outside the rendered buffer."
  (when (and (integerp row)
             (integerp column)
             (integerp origin-row)
             (integerp origin-column)
             (>= row origin-row)
             (>= column origin-column))
    (let ((target-row (- row origin-row))
          (target-column (- column origin-column)))
      (loop with current = (%initial-rendered-position prompt-width terminal-width)
            with index = 0
            for grapheme in (cl-tty-kit:string-graphemes (or text ""))
            for newline-p = (and (= (length grapheme) 1)
                                 (char= (char grapheme 0) #\Newline))
            for start = (%rendered-grapheme-start-position
                         current grapheme terminal-width)
            do (cond
                 (newline-p
                  (when (and (= target-row (rendered-position-row start))
                             (>= target-column (rendered-position-column start)))
                    (return index)))
                 (t
                  (let ((width (%string-visible-width grapheme)))
                    (when (and (plusp width)
                               (= target-row (rendered-position-row start))
                               (>= target-column (rendered-position-column start))
                               (< target-column
                                  (+ (rendered-position-column start) width)))
                      (return index)))))
                (setf current
                      (%advance-rendered-grapheme current grapheme terminal-width))
                (incf index (length grapheme))
            finally
               (when (and (= target-row (rendered-position-row current))
                          (>= target-column (rendered-position-column current)))
                 (return (length (or text ""))))))))

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
         (nshell.infrastructure.terminal:ansi-cursor-up rows-up)
         (nshell.infrastructure.terminal:ansi-cursor-column (1+ target-column)))
        (t
         (let ((columns (- final-column target-column)))
           (when (plusp columns)
             (nshell.infrastructure.terminal:ansi-cursor-back columns))))))))
