(in-package #:nshell.infrastructure.terminal)

;;; The escape-sequence vocabulary is provided by cl-tty-kit, whose ANSI helpers
;;; return strings.  nshell's helpers keep their side-effecting, stream-writing
;;; signatures (callers are unchanged) but delegate the actual byte sequence to
;;; cl-tty-kit, so there is a single source of truth for terminal control codes.
;;; Every sequence below was verified byte-identical to the previous hand-rolled
;;; output (see integration/test-terminal-ansi), including the SGR-mouse ordering.
(defun ansi-clear-screen () (write-string (cl-tty-kit:ansi-clear-screen 2)))
(defun ansi-clear-line () (write-string (cl-tty-kit:ansi-clear-line 2)))
(defun ansi-move-cursor (row col) (write-string (cl-tty-kit:ansi-move-cursor row col)))
(defun ansi-save-cursor (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-save-cursor) stream))
(defun ansi-restore-cursor (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-restore-cursor) stream))
(defun ansi-hide-cursor (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-hide-cursor) stream))
(defun ansi-show-cursor (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-show-cursor) stream))
(defun ansi-enable-bracketed-paste (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-enable-bracketed-paste) stream))
(defun ansi-disable-bracketed-paste (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-disable-bracketed-paste) stream))
(defun ansi-enable-sgr-mouse (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-enable-mouse :normal) stream))
(defun ansi-disable-sgr-mouse (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-disable-mouse :normal) stream))
(defun ansi-enable-alternate-screen (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-enter-alternate-screen) stream))
(defun ansi-disable-alternate-screen (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-exit-alternate-screen) stream))
;;; Cursor motion and SGR styling. These exist so the presentation tier stops
;;; hand-writing "~C[~dA" and friends: the vocabulary belongs to this layer, and
;;; routing through it keeps cl-tty-kit named in one file rather than in a dozen
;;; rendering functions. Each is byte-identical to the sequence its call sites
;;; used to build by hand.
(defun ansi-cursor-up (count &optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-cursor-up count) stream))
(defun ansi-cursor-down (count &optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-cursor-down count) stream))
(defun ansi-cursor-forward (count &optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-cursor-forward count) stream))
(defun ansi-cursor-back (count &optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-cursor-back count) stream))
(defun ansi-cursor-column (column &optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-cursor-column column) stream))
(defun ansi-dim (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-dim) stream))
(defun ansi-reverse (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-reverse) stream))
(defun ansi-reset-style (&optional (stream *standard-output*))
  (write-string (cl-tty-kit:ansi-reset-style) stream))

(defun ansi-color-code (color)
  (let ((map '(("00FF00" . 2) ("00AFFF" . 4) ("FF0000" . 1) ("FFFF00" . 3)
               ("FFA500" . 3) ("555555" . 8) ("737373" . 8) ("FFFFFF" . 7))))
    (or (cdr (assoc color map :test #'string=)) 7)))
