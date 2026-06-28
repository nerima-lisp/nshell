(in-package #:nshell.infrastructure.terminal)

(defconstant +escape+ #.(code-char 27))

(defmacro define-key-event-specs (name &body specs)
  `(defparameter ,name ',specs))

(define-key-event-specs +control-key-specs+
  (1 . :ctrl-a)
  (2 . :ctrl-b)
  (3 . :ctrl-c)
  (4 . :ctrl-d)
  (5 . :ctrl-e)
  (6 . :ctrl-f)
  (7 . :ctrl-g)
  (8 . :backspace)
  (9 . :tab)
  (10 . :enter)
  (11 . :ctrl-k)
  (12 . :ctrl-l)
  (13 . :enter)
  (14 . :ctrl-n)
  (16 . :ctrl-p)
  (18 . :ctrl-r)
  (19 . :ctrl-s)
  (20 . :ctrl-t)
  (21 . :ctrl-u)
  (23 . :ctrl-w)
  (25 . :ctrl-y)
  (31 . :ctrl-underscore)
  (127 . :backspace))

(define-key-event-specs +meta-code-specs+
  (8 . :alt-backspace)
  (127 . :alt-backspace))

(define-key-event-specs +meta-char-specs+
  (#\b . :alt-b)
  (#\c . :alt-c)
  (#\f . :alt-f)
  (#\d . :alt-d)
  (#\l . :alt-l)
  (#\r . :alt-r)
  (#\. . :alt-dot)
  (#\s . :alt-s)
  (#\t . :alt-t)
  (#\u . :alt-u)
  (#\y . :alt-y))

(define-key-event-specs +csi-arrow-specs+
  (#\A . :up)
  (#\B . :down)
  (#\C . :right)
  (#\D . :left))

(define-key-event-specs +csi-final-specs+
  (#\H . :home)
  (#\F . :end)
  (#\Z . :shift-tab))

(define-key-event-specs +csi-tilde-specs+
  (1 . :home)
  (3 . :delete)
  (4 . :end)
  (5 . :page-up)
  (6 . :page-down)
  (7 . :home)
  (8 . :end)
  (200 . :bracketed-paste-start)
  (201 . :bracketed-paste-end))

(define-key-event-specs +ss3-specs+
  (#\A . :up)
  (#\B . :down)
  (#\C . :right)
  (#\D . :left)
  (#\H . :home)
  (#\F . :end))

(define-key-event-specs +modifier-prefix-specs+
  (2 . ("SHIFT"))
  (3 . ("ALT"))
  (4 . ("SHIFT" "ALT"))
  (5 . ("CTRL"))
  (6 . ("SHIFT" "CTRL"))
  (7 . ("ALT" "CTRL"))
  (8 . ("SHIFT" "ALT" "CTRL")))

(defun lookup-key-event-type (key specs &key (test #'eql))
  (cdr (assoc key specs :test test)))

(defun key-event-from-spec (key specs &key (test #'eql))
  (let ((type (lookup-key-event-type key specs :test test)))
    (when type
      (make-key-event type))))

(defun printable-char-p (ch)
  "Return true for printable terminal characters, including Unicode."
  (graphic-char-p ch))

(defun split-string-on-char (string delimiter)
  (let ((parts '())
        (start 0))
    (loop for pos = (position delimiter string :start start)
          do (if pos
                 (progn
                   (push (subseq string start pos) parts)
                   (setf start (1+ pos)))
                 (progn
                   (push (subseq string start) parts)
                   (return))))
    (nreverse parts)))

(defun parse-integer-or-nil (string)
  (when (> (length string) 0)
    (handler-case (parse-integer string)
      (error () nil))))
