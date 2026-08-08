(in-package #:nshell.infrastructure.terminal)

;;; The escape-sequence vocabulary is provided by cl-tty-kit, whose ANSI helpers
;;; return strings.  nshell's helpers keep their side-effecting, stream-writing
;;; signatures (callers are unchanged) but delegate the actual byte sequence to
;;; cl-tty-kit, so there is a single source of truth for terminal control codes.
;;; Every sequence below was verified byte-identical to the previous hand-rolled
;;; output (see integration/test-terminal-ansi), including the SGR-mouse ordering.
;;;
;;; Every export here is the same two-line shape -- forward ARGS plus an
;;; optional STREAM to a cl-tty-kit call, write the string it returns -- so
;;; %DEFINE-ANSI-FORWARDER generates the DEFUN rather than each being spelled
;;; out. TTY-KIT-CALL is the full call form rather than derived from NAME: the
;;; cl-tty-kit function name, argument count, and any literal argument
;;; (ANSI-CLEAR-SCREEN's `2`, ANSI-ENABLE-SGR-MOUSE's `:normal`) all vary
;;; independently of NAME, so there is no naming convention to derive from.
;;; WITH-STREAM is nil only for the three legacy callers
;;; (ANSI-CLEAR-SCREEN/-CLEAR-LINE/-MOVE-CURSOR) that predate every other
;;; function's optional STREAM parameter and have no caller passing one.
(defmacro %define-ansi-forwarder (name (&rest args) tty-kit-call &key with-stream)
  (if with-stream
      `(defun ,name (,@args &optional (stream *standard-output*))
         (write-string ,tty-kit-call stream))
      `(defun ,name (,@args)
         (write-string ,tty-kit-call))))

(%define-ansi-forwarder ansi-clear-screen () (cl-tty-kit:ansi-clear-screen 2))
(%define-ansi-forwarder ansi-clear-line () (cl-tty-kit:ansi-clear-line 2))
(%define-ansi-forwarder ansi-move-cursor (row col) (cl-tty-kit:ansi-move-cursor row col))
(%define-ansi-forwarder ansi-save-cursor () (cl-tty-kit:ansi-save-cursor) :with-stream t)
(%define-ansi-forwarder ansi-restore-cursor () (cl-tty-kit:ansi-restore-cursor) :with-stream t)
(%define-ansi-forwarder ansi-hide-cursor () (cl-tty-kit:ansi-hide-cursor) :with-stream t)
(%define-ansi-forwarder ansi-show-cursor () (cl-tty-kit:ansi-show-cursor) :with-stream t)
(%define-ansi-forwarder ansi-enable-bracketed-paste () (cl-tty-kit:ansi-enable-bracketed-paste) :with-stream t)
(%define-ansi-forwarder ansi-disable-bracketed-paste () (cl-tty-kit:ansi-disable-bracketed-paste) :with-stream t)
(%define-ansi-forwarder ansi-enable-sgr-mouse () (cl-tty-kit:ansi-enable-mouse :normal) :with-stream t)
(%define-ansi-forwarder ansi-disable-sgr-mouse () (cl-tty-kit:ansi-disable-mouse :normal) :with-stream t)
(%define-ansi-forwarder ansi-enable-alternate-screen () (cl-tty-kit:ansi-enter-alternate-screen) :with-stream t)
(%define-ansi-forwarder ansi-disable-alternate-screen () (cl-tty-kit:ansi-exit-alternate-screen) :with-stream t)

(defun ansi-request-cursor-position (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-request-cursor-position) stream))

;;; Cursor motion and SGR styling. These exist so the presentation tier stops
;;; hand-writing "~C[~dA" and friends: the vocabulary belongs to this layer, and
;;; routing through it keeps cl-tty-kit named in one file rather than in a dozen
;;; rendering functions. Each is byte-identical to the sequence its call sites
;;; used to build by hand.
(%define-ansi-forwarder ansi-cursor-up (count) (cl-tty-kit:ansi-cursor-up count) :with-stream t)
(%define-ansi-forwarder ansi-cursor-down (count) (cl-tty-kit:ansi-cursor-down count) :with-stream t)
(%define-ansi-forwarder ansi-cursor-forward (count) (cl-tty-kit:ansi-cursor-forward count) :with-stream t)
(%define-ansi-forwarder ansi-cursor-back (count) (cl-tty-kit:ansi-cursor-back count) :with-stream t)
(%define-ansi-forwarder ansi-cursor-column (column) (cl-tty-kit:ansi-cursor-column column) :with-stream t)
(%define-ansi-forwarder ansi-dim () (cl-tty-kit:ansi-dim) :with-stream t)
(%define-ansi-forwarder ansi-reverse () (cl-tty-kit:ansi-reverse) :with-stream t)
(%define-ansi-forwarder ansi-reset-style () (cl-tty-kit:ansi-reset-style) :with-stream t)

(defun ansi-color-code (color)
  (let ((map '(("00FF00" . 2) ("00AFFF" . 4) ("FF0000" . 1) ("FFFF00" . 3)
               ("FFA500" . 3) ("555555" . 8) ("737373" . 8) ("FFFFFF" . 7))))
    (or (cdr (assoc color map :test #'string=)) 7)))
