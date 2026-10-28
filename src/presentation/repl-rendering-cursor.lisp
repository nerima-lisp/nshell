(in-package #:nshell.presentation)

(define-value-struct %rendered-position
    ((row 0 :type fixnum)
     (column 0 :type fixnum)))

(defun %advance-rendered-string (position text terminal-width)
  (let ((row (rendered-position-row position))
        (column (rendered-position-column position)))
    (dolist (grapheme (cl-tty-kit:string-graphemes (or text "")))
      (multiple-value-setq (row column)
        (%advance-rendered-components row column grapheme terminal-width)))
    (%make-rendered-position row column)))

(defun %advance-rendered-grapheme (position grapheme terminal-width)
  (multiple-value-bind (row column)
      (%advance-rendered-components (rendered-position-row position)
                                    (rendered-position-column position)
                                    grapheme
                                    terminal-width)
    (%make-rendered-position row column)))

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

(defun %advance-rendered-components (row column grapheme terminal-width)
  (if (and (= (length grapheme) 1)
           (char= (char grapheme 0) #\Newline))
      (values (1+ row) 2)
      (let ((width (%string-visible-width grapheme)))
        (when (and terminal-width
                   (plusp terminal-width)
                   (> (+ column width) terminal-width))
          (setf row (1+ row)
                column 0))
        (if (and terminal-width
                 (plusp terminal-width)
                 (> width terminal-width))
            (values (1+ row) (- width terminal-width))
            (values row (+ column width))))))

(defun %initial-rendered-position (prompt-width terminal-width)
  (let ((prompt-width (or prompt-width 0)))
    (if (and terminal-width
           (plusp terminal-width)
           (> prompt-width terminal-width))
        (%make-rendered-position (floor (1- prompt-width) terminal-width)
                                 (1+ (mod (1- prompt-width) terminal-width)))
        (%make-rendered-position 0 prompt-width))))

(defun %rendered-buffer-line-count (text &key cursor suggestion search-suffix terminal-width
                                         (prompt-width 0))
  (let* ((initial-position (%initial-rendered-position prompt-width terminal-width))
         (row (rendered-position-row initial-position))
         (column (rendered-position-column initial-position))
         (consumed 0)
         (cursor-position (and cursor
                               (<= cursor 0)
                               initial-position)))
    (dolist (grapheme (cl-tty-kit:string-graphemes (or text "")))
      (incf consumed (length grapheme))
      (multiple-value-setq (row column)
        (%advance-rendered-components row column grapheme terminal-width))
      (when (and cursor
                 (null cursor-position)
                 (>= consumed cursor))
        (setf cursor-position (%make-rendered-position row column))))
    (let* ((text-end-position (%make-rendered-position row column))
           (suggestion-position (%advance-rendered-string text-end-position
                                                          suggestion
                                                          terminal-width))
           (final-position (%advance-rendered-string suggestion-position
                                                     search-suffix
                                                     terminal-width))
           (line-count (1+ (rendered-position-row final-position))))
      (if cursor
          (values line-count
                  (or cursor-position text-end-position)
                  text-end-position
                  final-position)
          line-count))))

(defun %rendered-buffer-position (text cursor prompt-width &key terminal-width)
  (let* ((initial-position (%initial-rendered-position prompt-width terminal-width))
         (row (rendered-position-row initial-position))
         (column (rendered-position-column initial-position))
         (consumed 0))
    (dolist (grapheme (cl-tty-kit:string-graphemes text))
      (when (>= consumed cursor)
        (return))
      (incf consumed (length grapheme))
      (multiple-value-setq (row column)
        (%advance-rendered-components row column grapheme terminal-width)))
    (%make-rendered-position row column)))

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
  (multiple-value-bind (line-count cursor-position text-end-position final-position)
      (%rendered-buffer-line-count text
                                   :cursor cursor
                                   :suggestion suggestion
                                   :search-suffix search-suffix
                                   :terminal-width terminal-width
                                   :prompt-width prompt-width)
    (declare (ignore line-count text-end-position))
    (if (= (rendered-position-row cursor-position)
           (rendered-position-row final-position))
        (max 0 (- (rendered-position-column final-position)
                  (rendered-position-column cursor-position)))
        0)))

(defun %move-cursor-to-rendered-position (text cursor prompt-width suggestion search-suffix
                                          &key terminal-width)
  (multiple-value-bind (line-count target-position text-end-position final-position)
      (%rendered-buffer-line-count text
                                   :cursor cursor
                                   :suggestion suggestion
                                   :search-suffix search-suffix
                                   :terminal-width terminal-width
                                   :prompt-width prompt-width)
    (declare (ignore text-end-position))
    (let ((target-row (rendered-position-row target-position))
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
               (nshell.infrastructure.terminal:ansi-cursor-back columns))))))
      (values line-count target-position))))
