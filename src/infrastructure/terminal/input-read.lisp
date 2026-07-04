(in-package #:nshell.infrastructure.terminal)


(defun read-available-char (&key (attempts 20) (sleep-seconds 0.001))
  (loop repeat attempts
        when (listen *standard-input*)
          return (read-char *standard-input* nil nil)
        do (sleep sleep-seconds)
        finally (return nil)))

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
        (terminator (coerce (list +escape+ #\[ #\2 #\0 #\1 #\~) 'string))
        (window "")
        (matched nil))
    (loop for ch = (read-char *standard-input* nil nil)
          while ch
          do (setf window
                   (concatenate 'string window (string ch)))
             (when (> (length window) (length terminator))
               (push (char window 0) chars)
               (setf window (subseq window 1)))
             (when (string= window terminator)
               (setf matched t)
               (return)))
    (unless matched
      (loop for ch across window do (push ch chars)))
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
