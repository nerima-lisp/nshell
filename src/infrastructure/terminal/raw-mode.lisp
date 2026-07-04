(in-package #:nshell.infrastructure.terminal)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defvar *saved-termios* nil)

(defun enable-raw-mode ()
  "Enable raw terminal mode for character-by-character input."
  (handler-case
      (let ((termios (sb-posix:tcgetattr 0)))
        (setf *saved-termios* termios)
        (let ((raw (sb-posix:tcgetattr 0)))
          (setf (sb-posix:termios-iflag raw)
                (logand (sb-posix:termios-iflag raw)
                        (lognot (logior sb-posix:ixon
                                        sb-posix:ixoff))))
          (setf (sb-posix:termios-lflag raw)
                (logand (sb-posix:termios-lflag raw)
                        (lognot (logior sb-posix:icanon sb-posix:echo))))
          (sb-posix:tcsetattr 0 sb-posix:tcsadrain raw)))
    (error ())))

(defun restore-terminal-mode ()
  "Restore original terminal settings."
  (when *saved-termios*
    (handler-case
        (sb-posix:tcsetattr 0 sb-posix:tcsadrain *saved-termios*)
      (error ()))))
