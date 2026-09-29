(in-package #:nshell.infrastructure.terminal)

(defparameter *east-asian-ambiguous-probe-character* #\§)

(defun %east-asian-probe-width (&key (attempts 20) (sleep-seconds 0.005))
  "Measure the terminal width of one East Asian Ambiguous character.

The two cursor queries use the existing CPR reader, whose input restoration
keeps ordinary input ahead of the line editor.  The probe is erased with ECH
after returning to the saved cursor position."
  (let ((stream *standard-output*)
        (input *standard-input*))
    (write-string (cl-tty-kit:ansi-save-cursor) stream)
    (finish-output stream)
    (unwind-protect
         (let ((*standard-output* stream)
               (*standard-input* input))
           (multiple-value-bind (before-row before-column)
               (query-cursor-position :attempts attempts
                                      :sleep-seconds sleep-seconds)
             (declare (ignore before-row))
             (when before-column
               (write-char *east-asian-ambiguous-probe-character* stream)
               (finish-output stream)
               (multiple-value-bind (after-row after-column)
                   (query-cursor-position :attempts attempts
                                          :sleep-seconds sleep-seconds)
                 (declare (ignore after-row))
                 (when after-column
                   (- after-column before-column)))))
      (write-string (cl-tty-kit:ansi-restore-cursor) stream)
      ;; ECH clears cells without moving the cursor or clobbering neighbors.
      (write-string (format nil "~C[2X" (code-char 27)) stream)
      (write-string (cl-tty-kit:ansi-restore-cursor) stream)
      (finish-output stream)))))

(defun detect-east-asian-ambiguous-wide-p (&key (attempts 20)
                                                (sleep-seconds 0.005))
  "Return T when the interactive terminal renders ambiguous text wide.

NIL means that no trustworthy CPR measurement was obtained.  The default
arguments bound the probe wait to about 100ms, before the locale fallback."
  (eql 2 (%east-asian-probe-width :attempts attempts
                                  :sleep-seconds sleep-seconds)))
