(in-package #:nshell.infrastructure.terminal)

(defstruct (cell (:constructor %make-cell (&key character foreground background bold-p underline-p)))
  (character nil :type (or null character))
  (foreground nil :type (or null string))
  (background nil :type (or null string))
  (bold-p nil :type boolean)
  (underline-p nil :type boolean))

(defun make-cell (&key character foreground background bold-p underline-p)
  (%make-cell :character character
              :foreground foreground
              :background background
              :bold-p bold-p
              :underline-p underline-p))

(defstruct (screen (:constructor %make-screen (width height cells)))
  (width 80 :type integer)
  (height 24 :type integer)
  cells)

(defun %make-empty-cells (width height)
  (let ((cells (make-array (list height width))))
    (loop for row below height
          do (loop for col below width
                   do (setf (aref cells row col) (make-cell))))
    cells))

(defun make-screen (&key (width 80) (height 24))
  (%make-screen width height (%make-empty-cells width height)))

(defun %in-screen-p (screen row col)
  (and (<= 0 row) (< row (screen-height screen))
       (<= 0 col) (< col (screen-width screen))))

(defun screen-cell (screen row col)
  (when (%in-screen-p screen row col)
    (aref (screen-cells screen) row col)))

(defun %wide-character-p (char)
  (let ((code (char-code char)))
    (or (<= #x1100 code #x115F)
        (<= #x2329 code #x232A)
        (<= #x2E80 code #xA4CF)
        (<= #xAC00 code #xD7A3)
        (<= #xF900 code #xFAFF)
        (<= #xFE10 code #xFE19)
        (<= #xFE30 code #xFE6F)
        (<= #xFF00 code #xFF60)
        (<= #xFFE0 code #xFFE6)
        (<= #x1F300 code #x1FAFF))))

(defun %screen-character-width (char)
  (cond
    ((null char) 1)
    ((char= char #\Tab) 4)
    ((%wide-character-p char) 2)
    (t 1)))

(defun %clear-screen-cell (screen row col)
  (when (%in-screen-p screen row col)
    (setf (aref (screen-cells screen) row col) (make-cell))))

(defun screen-put-cell (screen row col character &key foreground background bold-p underline-p)
  (when (%in-screen-p screen row col)
    (setf (aref (screen-cells screen) row col)
          (make-cell :character character
                     :foreground foreground
                     :background background
                     :bold-p (not (null bold-p))
                     :underline-p (not (null underline-p)))))
  screen)

(defun screen-put-string (screen row col text &key foreground background bold-p underline-p)
  (loop with target-col = col
        for offset below (length text)
        for char = (char text offset)
        for char-width = (%screen-character-width char)
        while (<= (+ target-col char-width) (screen-width screen))
        do
           (screen-put-cell screen row target-col char
                            :foreground foreground
                            :background background
                            :bold-p bold-p
                            :underline-p underline-p)
           (loop for trailing-col from (1+ target-col) below (+ target-col char-width)
                 do (%clear-screen-cell screen row trailing-col))
           (incf target-col char-width))
  screen)

(defun %span-foreground (index spans)
  (loop for span in spans
        for start = (getf span :start)
        for end = (getf span :end)
        when (and start end (<= start index) (< index end))
          return (getf span :role)))

(defun screen-put-line (screen row text &key spans)
  (screen-clear-line screen row)
  (loop with target-col = 0
        for index below (length text)
        for char = (char text index)
        for char-width = (%screen-character-width char)
        while (<= (+ target-col char-width) (screen-width screen))
        do
           (screen-put-cell screen row target-col char
                            :foreground (%span-foreground index spans))
           (loop for trailing-col from (1+ target-col) below (+ target-col char-width)
                 do (%clear-screen-cell screen row trailing-col))
           (incf target-col char-width))
  screen)

(defun screen-clear-line (screen row)
  (when (<= 0 row (1- (screen-height screen)))
    (loop for col below (screen-width screen)
          do (setf (aref (screen-cells screen) row col) (make-cell))))
  screen)

(defun screen-clear (screen)
  (loop for row below (screen-height screen)
        do (screen-clear-line screen row))
  screen)

(defun screen-resize (screen width height)
  (let ((new-cells (%make-empty-cells width height))
        (old-cells (screen-cells screen)))
    (loop for row below (min height (screen-height screen))
          do (loop for col below (min width (screen-width screen))
                   do (setf (aref new-cells row col)
                            (copy-cell (aref old-cells row col)))))
    (setf (screen-width screen) width
          (screen-height screen) height
          (screen-cells screen) new-cells))
  screen)

(defun %cell-equal-p (left right)
  (and (char= (or (cell-character left) #\Null)
              (or (cell-character right) #\Null))
       (equal (cell-foreground left) (cell-foreground right))
       (equal (cell-background left) (cell-background right))
       (eql (cell-bold-p left) (cell-bold-p right))
       (eql (cell-underline-p left) (cell-underline-p right))))

(defun screen-diff (old new)
  (loop for row below (min (screen-height old) (screen-height new))
        append (loop for col below (min (screen-width old) (screen-width new))
                     for old-cell = (screen-cell old row col)
                     for new-cell = (screen-cell new row col)
                     unless (%cell-equal-p old-cell new-cell)
                       collect (list row col new-cell))))

(defun %hex-pair-value (text start)
  (parse-integer text :start start :end (+ start 2) :radix 16))

(defun %emit-color (stream prefix color)
  (when (and color (= 6 (length color)))
    (format stream "~C[~a;2;~d;~d;~dm"
            #\Esc prefix
            (%hex-pair-value color 0)
            (%hex-pair-value color 2)
            (%hex-pair-value color 4))))

(defun %emit-cell-style (stream cell)
  (when (cell-bold-p cell)
    (format stream "~C[1m" #\Esc))
  (when (cell-underline-p cell)
    (format stream "~C[4m" #\Esc))
  (%emit-color stream "38" (cell-foreground cell))
  (%emit-color stream "48" (cell-background cell)))

(defun screen-render (old new &key (stream *standard-output*))
  (dolist (change (screen-diff old new))
    (destructuring-bind (row col cell) change
      (format stream "~C[~d;~dH" #\Esc (1+ row) (1+ col))
      (%emit-cell-style stream cell)
      (write-char (or (cell-character cell) #\Space) stream)
      (format stream "~C[0m" #\Esc)))
  t)
