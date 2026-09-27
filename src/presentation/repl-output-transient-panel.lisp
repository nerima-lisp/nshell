;;; REPL transient output region
(in-package #:nshell.presentation)

(defvar *transient-panel-content* nil)
(defvar *preserve-transient-panel-on-next-prompt-p* nil)

(defun %transient-output-row-offset ()
  (max 0
       (- (1- *prompt-rendered-lines*)
          *prompt-rendered-cursor-row*)))

(defun %render-transient-output-below-prompt (renderer)
  (nshell.infrastructure.terminal:ansi-save-cursor)
  (unwind-protect
       (progn
         (let ((rows (%transient-output-row-offset)))
           (when (plusp rows)
             (nshell.infrastructure.terminal:ansi-cursor-down rows)))
         (funcall renderer))
    (nshell.infrastructure.terminal:ansi-restore-cursor)))

(defun %clear-rendered-transient-output (rendered-lines)
  (when (plusp rendered-lines)
    (nshell.infrastructure.terminal:ansi-save-cursor)
    (unwind-protect
         (progn
           (let ((rows (+ (%transient-output-row-offset)
                          rendered-lines
                          1)))
             (when (plusp rows)
               (nshell.infrastructure.terminal:ansi-cursor-down rows)))
           (format t "~C" #\Return)
           (nshell.infrastructure.terminal:ansi-clear-line)
           (loop repeat rendered-lines
                 do
             (format t "~C[A" #\Esc)
             (nshell.infrastructure.terminal:ansi-clear-line)))
      (nshell.infrastructure.terminal:ansi-restore-cursor))))

(defun reset-rendered-transient-panel-state ()
  (setf *transient-panel-rendered-lines* 0
        *transient-panel-content* nil))

(defun clear-rendered-transient-panel ()
  (when (plusp *transient-panel-rendered-lines*)
    (%clear-rendered-transient-output *transient-panel-rendered-lines*))
  (reset-rendered-transient-panel-state))

(defun %transient-panel-lines (content)
  (labels ((split-line (line)
             (let ((lines nil)
                   (start 0))
               (loop for newline = (position #\Newline line :start start)
                     do (push (subseq line start (or newline (length line)))
                              lines)
                     if newline
                       do (setf start (1+ newline))
                     else
                       do (return))
               (nreverse lines)))
           (line-text (value)
             (if (stringp value)
                 value
                 (princ-to-string value))))
    (cond
      ((null content) nil)
      ((stringp content) (split-line content))
      ((listp content)
       (loop for value in content
             append (split-line (line-text value))))
      (t (split-line (line-text content))))))

(defun %transient-panel-visible-lines (lines max-rows)
  (let ((content-rows (max 0 (- max-rows 2))))
    (cond
      ((zerop content-rows) nil)
      ((<= (length lines) content-rows) lines)
      ((= content-rows 1) '("…"))
      (t (cons "…" (last lines (1- content-rows)))))))

(defun %transient-panel-terminal-rows ()
  (handler-case
      (multiple-value-bind (rows columns)
          (nshell.infrastructure.acl:get-terminal-size)
        (declare (ignore columns))
        (if (and (numberp rows) (plusp rows)) rows 0))
    (error () 0)))

(defun %transient-panel-border (left right width)
  (format nil "~a~a~a"
          left
          (make-string (max 0 (- width 2)) :initial-element #\─)
          right))

(defun %transient-panel-line (line width)
  (let* ((content-width (max 0 (- width 4)))
         (visible (%truncate-string-to-width line content-width))
         (padding (max 0 (- content-width (%string-visible-width visible)))))
    (concatenate 'string
                 "│ "
                 visible
                 (make-string padding :initial-element #\Space)
                 " │")))

(defun %render-transient-panel-lines (lines width)
  (format t "~C~%" #\Return)
  (format t "~a~%"
          (%transient-panel-border #\┌ #\┐ width))
  (dolist (line lines)
    (format t "~a~%"
            (%transient-panel-line line width)))
  (format t "~a~%"
          (%transient-panel-border #\└ #\┘ width))
  (+ 2 (length lines)))

(defun render-transient-panel (content &key (terminal-width (terminal-width)))
  (clear-rendered-transient-panel)
  (setf *transient-panel-content* content)
  (let* ((lines (%transient-panel-lines content))
         (terminal-rows (%transient-panel-terminal-rows))
         (max-rows (max 0 (- terminal-rows *prompt-rendered-lines* 1)))
         (width (max 2 terminal-width))
         (visible-lines (%transient-panel-visible-lines lines max-rows)))
    (when (and lines (>= max-rows 2))
      (setf *transient-panel-rendered-lines*
            (%render-transient-output-below-prompt
             (lambda ()
               (%render-transient-panel-lines visible-lines width)))))
    *transient-panel-rendered-lines*))

(defun transient-panel-displayed-p ()
  (plusp *transient-panel-rendered-lines*))

(defun commit-transient-panel-to-scrollback (&key (terminal-width (terminal-width)))
  "Commit the complete transient panel contents as ordinary terminal output.

The panel and prompt are erased before the complete content is emitted
without the height limit, making the result ordinary terminal output rather
than another transient redraw."
  (when (and (transient-panel-displayed-p)
             *transient-panel-content*)
    (let ((lines (%transient-panel-lines *transient-panel-content*)))
      (clear-rendered-transient-panel)
      (clear-rendered-prompt)
      (%render-transient-panel-lines lines (max 2 terminal-width))
      (reset-rendered-transient-panel-state)
      t)))

(defun update-transient-panel (content &key (terminal-width (terminal-width)))
  (render-transient-panel content :terminal-width terminal-width))
