;;; REPL completion output helpers
(in-package #:nshell.presentation)

(defun reset-rendered-completion-state ()
  (setf *completion-rendered-lines* 0))

(defun %render-completions-below-prompt (candidates &key selected-index)
  (nshell.infrastructure.terminal:ansi-save-cursor)
  (unwind-protect
       (progn
         (let ((rows (max 0
                          (- (1- *prompt-rendered-lines*)
                             *prompt-rendered-cursor-row*))))
           (when (plusp rows)
             (format t "~C[~dB" #\Esc rows)))
         (render-completions candidates :selected-index selected-index))
    (nshell.infrastructure.terminal:ansi-restore-cursor)))

(defun clear-rendered-completions ()
  (when (> *completion-rendered-lines* 0)
    (nshell.infrastructure.terminal:ansi-save-cursor)
    (unwind-protect
         (progn
           (let ((rows (+ (max 0
                               (- (1- *prompt-rendered-lines*)
                                  *prompt-rendered-cursor-row*))
                          *completion-rendered-lines*
                          1)))
             (when (plusp rows)
               (format t "~C[~dB" #\Esc rows)))
            (format t "~C" #\Return)
            (nshell.infrastructure.terminal:ansi-clear-line)
            (loop repeat *completion-rendered-lines*
                 do
             (format t "~C[A" #\Esc)
             (nshell.infrastructure.terminal:ansi-clear-line)))
      (nshell.infrastructure.terminal:ansi-restore-cursor))
    (reset-rendered-completion-state)))
