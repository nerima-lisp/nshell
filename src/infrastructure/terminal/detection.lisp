(in-package #:nshell.infrastructure.terminal)

(defun interactive-terminal-p (&optional (fd 0))
  "Return T when FD is attached to an interactive terminal."
  #+sbcl (= 1 (sb-unix:unix-isatty fd))
  #-sbcl nil)
(defun terminal-control-sequences-supported-p ()
  "Return T when terminal control sequences are appropriate for this session."
  (and (interactive-terminal-p 0)
       (interactive-terminal-p 1)
       (not (let ((term (host-kit:getenv "TERM")))
              (and term (string-equal term "dumb"))))))
