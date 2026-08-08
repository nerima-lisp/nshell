(in-package #:nshell.infrastructure.terminal)


(defparameter *max-bracketed-paste-size* 4096
  "Maximum number of pasted characters retained by the terminal reader.")

(defun read-available-char (&key (attempts 20) (sleep-seconds 0.001))
  (loop repeat attempts
        when (listen *standard-input*)
          return (read-char *standard-input* nil nil)
        do (sleep sleep-seconds)
        finally (return nil)))

(defun query-cursor-position (&key (attempts 20) (sleep-seconds 0.005))
  "Return the terminal cursor position as 1-based ROW and COLUMN values.

When the response is unavailable or the first byte is ordinary input, return
NIL values and preserve any input consumed while looking for the response."
  (ansi-request-cursor-position)
  (finish-output)
  (let ((chars '()))
    (labels ((restore-input ()
               (dolist (character chars)
                 (ignore-errors
                   (unread-char character *standard-input*)))))
      (let ((first (read-available-char :attempts 1 :sleep-seconds 0)))
        (cond
          ((null first)
           (values nil nil))
          ((not (char= first #\Esc))
           (push first chars)
           (restore-input)
           (values nil nil))
          (t
           (push first chars)
           (loop repeat attempts
                 do (multiple-value-bind (row column consumed)
                        (cl-tty-kit:decode-cursor-position-report
                         (coerce (reverse chars) 'string))
                      (when (and (integerp row)
                                 (integerp column)
                                 (plusp consumed))
                        (return-from query-cursor-position
                          (values (1+ row) (1+ column)))))
                    (let ((next (read-available-char
                                 :attempts 1
                                 :sleep-seconds 0)))
                      (if next
                          (push next chars)
                          (sleep sleep-seconds))))
           (restore-input)
           (values nil nil)))))))

(defun csi-final-char-p (ch)
  "Return true when CH is a CSI final byte."
  (let ((code (char-code ch)))
    (<= #x40 code #x7e)))

(defun read-csi-sequence (&key (limit 64))
  "Read a CSI body through its final byte without consuming following input."
  (let ((chars '()))
    (loop repeat limit
          for ch = (read-char *standard-input* nil nil)
          while ch
          do (push ch chars)
          when (csi-final-char-p ch)
            do (return))
    (coerce (nreverse chars) 'string)))

(defun read-ss3-sequence (&key (limit 8))
  "Read a short SS3 body without consuming unrelated following input."
  (let ((chars '()))
    (loop repeat limit
          for ch = (read-char *standard-input* nil nil)
          while ch
          do (push ch chars)
          when (alpha-char-p ch)
            do (return))
    (coerce (nreverse chars) 'string)))

(defun normalize-bracketed-paste-text (text)
  "Normalize pasted line endings to LF while preserving other text."
  (when (stringp text)
    (with-output-to-string (stream)
      (loop with index = 0
            while (< index (length text))
            for ch = (char text index)
            do (cond
                 ((char= ch #\Return)
                  (write-char #\Newline stream)
                  (incf index)
                  (when (and (< index (length text))
                             (char= (char text index) #\Newline))
                    (incf index)))
                 (t
                  (write-char ch stream)
                  (incf index)))))))

(defun read-bracketed-paste-text ()
  "Read bytes until the bracketed paste terminator ESC [ 201 ~.

The terminator is consumed and not included in the returned text."
  (let ((chars '())
        (retained 0)
        (terminator (coerce (list +escape+ #\[ #\2 #\0 #\1 #\~) 'string))
        (window "")
        (matched nil))
    (labels ((retain-character (ch)
               (when (< retained *max-bracketed-paste-size*)
                 (push ch chars)
                 (incf retained))))
      (loop for ch = (read-char *standard-input* nil nil)
            while ch
            do (setf window
                     (concatenate 'string window (string ch)))
               (when (> (length window) (length terminator))
                 (retain-character (char window 0))
                 (setf window (subseq window 1)))
               (when (string= window terminator)
                 (setf matched t)
                 (return)))
      (unless matched
        (loop for ch across window do (retain-character ch))))
    (normalize-bracketed-paste-text (coerce (nreverse chars) 'string))))

(defun read-escape-key-event ()
  "Read and decode one ESC-prefixed terminal input event."
  (let ((prefix (read-available-char)))
    (cond
      ((null prefix) (make-key-event :escape))
      ((char= prefix #\[)
       (let ((event (decode-csi-sequence (read-csi-sequence))))
         (case (key-event-type event)
           (:bracketed-paste-start
            (make-key-event :paste nil nil
                            (list :protocol :bracketed
                                  :text (read-bracketed-paste-text))))
           (:bracketed-paste-end (make-key-event :ignore))
           (otherwise event))))
      ((char= prefix #\O)
       (decode-ss3-sequence (read-ss3-sequence)))
      (t (decode-meta-key prefix)))))

(defun read-key-event ()
  "Read and decode one terminal key event from `*standard-input*'."
  (let ((ch (read-char *standard-input* nil nil)))
    (when ch
      (decode-character-key ch))))
