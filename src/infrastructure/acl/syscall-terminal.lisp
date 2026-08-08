(in-package #:nshell.infrastructure.acl)

;;; The window-size query is cl-tty-kit:terminal-size rather than a local ioctl.
;;; This is a bug fix, not only de-duplication: the hand-rolled version called
;;; the %ioctl DEFINE-ALIEN-ROUTINE in syscall-foreign.lisp, and ioctl(2) is
;;; variadic. On arm64 a variadic argument is passed on the stack while a
;;; fixed-prototype alien call passes it in a register, so the winsize pointer
;;; never reached the kernel and the call returned -1/EFAULT on Apple Silicon --
;;; every caller then fell back to 80 columns. cl-tty-kit goes through
;;; SB-UNIX:UNIX-IOCTL, which marshals a variadic call correctly.
;;;
;;; cl-tty-kit:terminal-size returns (VALUES COLUMNS ROWS) and reports an
;;; unavailable size as (VALUES NIL NIL). GET-TERMINAL-SIZE keeps nshell's
;;; established contract instead -- (VALUES ROWS COLUMNS), signalling when the
;;; size is unknown -- because its three callers all sit inside a HANDLER-CASE
;;; that supplies the 80-column fallback, and returning NIL rather than
;;; signalling would slip a NIL width past them into the layout arithmetic.

(define-condition terminal-size-unavailable (error)
  ((fd :initarg :fd :reader terminal-size-unavailable-fd))
  (:report
   (lambda (condition stream)
     (format stream "Terminal size is unavailable on fd ~d."
             (terminal-size-unavailable-fd condition)))))

(defun get-terminal-size (&optional (fd 0))
  "Return terminal size as (values rows cols).
Signals TERMINAL-SIZE-UNAVAILABLE when FD is not a terminal or the window size
cannot be determined."
  (multiple-value-bind (columns rows) (cl-tty-kit:terminal-size fd)
    (if (and rows columns)
        (values rows columns)
        (error 'terminal-size-unavailable :fd fd))))
