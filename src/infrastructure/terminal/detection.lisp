(in-package #:nshell.infrastructure.terminal)

(defun interactive-terminal-p (&optional (fd 0))
  "Return T when FD is attached to an interactive terminal."
  #+sbcl (= 1 (sb-unix:unix-isatty fd))
  #-sbcl nil)
(defun controlling-terminal-p ()
  "Return T when this process has a controlling terminal."
  (let ((fd
          (handler-case
              (sb-posix:open "/dev/tty" sb-posix:o-rdonly)
            (sb-posix:syscall-error (condition)
              (if (= (sb-posix:syscall-errno condition) sb-posix:enxio)
                  nil
                  (error condition))))))
    (when fd
      (sb-posix:close fd)
      t)))
(defun terminal-control-sequences-supported-p ()
  "Return T when terminal control sequences are appropriate for this session."
  (and (interactive-terminal-p 0)
       (interactive-terminal-p 1)
       (not (let ((term (host-kit:getenv "TERM")))
              (and term (string-equal term "dumb"))))))
