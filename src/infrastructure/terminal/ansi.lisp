(in-package #:nshell.infrastructure.terminal)

;;; Keep terminal control codes in cl-tty-kit while preserving nshell's
;;; stream-writing API. The macro covers the uniform forwarding functions;
;;; TTY-KIT-CALL remains explicit because its arguments are not name-derived.
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

(defparameter +base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defun %base64-encode-octets (octets)
  (with-output-to-string (output)
    (loop for index from 0 below (length octets) by 3
          for remaining = (- (length octets) index)
          for first = (aref octets index)
          for second = (if (> remaining 1)
                           (aref octets (1+ index))
                           0)
          for third = (if (> remaining 2)
                          (aref octets (+ index 2))
                          0)
          for triple = (logior (ash first 16)
                               (ash second 8)
                               third)
          do (write-char (char +base64-alphabet+ (ldb (byte 6 18) triple))
                         output)
             (write-char (char +base64-alphabet+ (ldb (byte 6 12) triple))
                         output)
             (write-char (if (> remaining 1)
                             (char +base64-alphabet+ (ldb (byte 6 6) triple))
                             #\=)
                        output)
             (write-char (if (> remaining 2)
                             (char +base64-alphabet+ (ldb (byte 6 0) triple))
                             #\=)
                        output))))

(defun ansi-copy-to-clipboard (text &optional (stream *standard-output*))
  (write-char #\Esc stream)
  (write-string "]52;c;" stream)
  (write-string (%base64-encode-octets (nshell.util:utf-8-octets text)) stream)
  (write-char #\Bell stream))

(defparameter +host-clipboard-commands+
  '(("pbcopy")
    ("wl-copy")
    ("xclip" "-selection" "clipboard")
    ("xsel" "--clipboard" "--input")
    ("clip.exe")))

(defun %write-host-clipboard (text)
  (loop for command in +host-clipboard-commands+
        for program = (ignore-errors
                        (host-kit:find-program (first command)))
        when program
          do (handler-case
                 (let ((result (host-kit:run-program
                                program
                                (rest command)
                                :input text
                                :timeout 2d0)))
                   (when (and (eql 0 (host-kit:process-result-exit-code result))
                              (not (host-kit:process-result-timed-out-p result)))
                     (return t)))
               (error () nil))
        finally (return nil)))

(defvar *clipboard-host-writer* #'%write-host-clipboard)

(defun copy-to-clipboard (text &optional (stream *standard-output*))
  (if (and *clipboard-host-writer*
           (funcall *clipboard-host-writer* text))
      :host
      (progn
        (ansi-copy-to-clipboard text stream)
        :osc52)))

;;; Cursor motion and SGR styling belong to this terminal boundary.
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
