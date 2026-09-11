;;; REPL completion output helpers
(in-package #:nshell.presentation)

(defun reset-rendered-completion-state ()
  (setf *completion-rendered-lines* 0))

(defun %render-completions-below-prompt (candidates &key selected-index)
  (%render-transient-output-below-prompt
   (lambda ()
     (render-completions candidates :selected-index selected-index
                                     :theme (nshell.domain.configuration:config-theme *config*)))))

(defun clear-rendered-completions ()
  (when (> *completion-rendered-lines* 0)
    (%clear-rendered-transient-output *completion-rendered-lines*)
    (reset-rendered-completion-state)))
