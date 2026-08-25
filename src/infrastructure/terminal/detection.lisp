(in-package #:nshell.infrastructure.terminal)

(defun interactive-terminal-p (&optional (fd 0))
  "Return T when FD is attached to an interactive terminal."
  #+sbcl (= 1 (sb-unix:unix-isatty fd))
  #-sbcl nil)
