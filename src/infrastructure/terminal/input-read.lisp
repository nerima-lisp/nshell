(in-package #:nshell.infrastructure.terminal)


(defparameter *max-bracketed-paste-size* 65536
  "Maximum number of pasted characters retained by the terminal reader.")

(defstruct (terminal-input (:constructor %make-terminal-input))
  "Reader state the terminal input stream itself cannot hold.

READ-AHEAD holds characters taken from the stream but not yet delivered.
Readers that consume more than one character before deciding they cannot use
it put the characters back here: CL allows only one UNREAD-CHAR after each
READ-CHAR, so a multi-character push-back through the stream is undefined.
CURSOR-REPORTS-UNSUPPORTED-P records that a cursor position reply did not
arrive in time, after which no more requests are sent."
  (read-ahead '() :type list)
  (cursor-reports-unsupported-p nil))

(defvar *terminal-inputs* (make-hash-table :test 'eq :weakness :key)
  "TERMINAL-INPUT state for each input stream that a terminal reader used.")

(defun %terminal-input (&optional (stream *standard-input*))
  (or (gethash stream *terminal-inputs*)
      (setf (gethash stream *terminal-inputs*) (%make-terminal-input))))

(defun push-back-input (characters &optional (stream *standard-input*))
  "Deliver CHARACTERS, in order, before any later input from STREAM."
  (when characters
    (let ((state (%terminal-input stream)))
      (setf (terminal-input-read-ahead state)
            (append characters (terminal-input-read-ahead state))))))

(defun next-input-char (&optional (stream *standard-input*))
  "Return the next character of STREAM, read-ahead input first; NIL at EOF."
  (let ((state (%terminal-input stream)))
    (if (terminal-input-read-ahead state)
        (pop (terminal-input-read-ahead state))
        (read-char stream nil nil))))

(defun input-ready-p (&optional (stream *standard-input*))
  "Return true when NEXT-INPUT-CHAR can return a character without blocking."
  (or (terminal-input-read-ahead (%terminal-input stream))
      (listen stream)))

(defun read-input-line (&optional (stream *standard-input*))
  "READ-LINE STREAM, returning NIL at end of file, after its read-ahead input.

Commands that read a line from the terminal use this, so keys typed ahead and
held back by a terminal reader reach them in order; the rest of the read-ahead
input stays ahead of later input."
  (let* ((state (gethash stream *terminal-inputs*))
         (pending (and state (terminal-input-read-ahead state))))
    (if (null pending)
        (read-line stream nil nil)
        (let ((newline (position #\Newline pending)))
          (if newline
              (prog1 (coerce (subseq pending 0 newline) 'string)
                (setf (terminal-input-read-ahead state)
                      (nthcdr (1+ newline) pending)))
              (progn
                (setf (terminal-input-read-ahead state) '())
                (concatenate 'string
                             (coerce pending 'string)
                             (or (read-line stream nil nil) ""))))))))

(defun read-available-char (&key (attempts 20) (sleep-seconds 0.001))
  (loop repeat attempts
        when (input-ready-p)
          return (next-input-char)
        do (sleep sleep-seconds)
        finally (return nil)))

(defun %append-read-ahead (characters &optional (stream *standard-input*))
  "Deliver CHARACTERS, in order, after the read-ahead input STREAM already has."
  (when characters
    (let ((state (%terminal-input stream)))
      (setf (terminal-input-read-ahead state)
            (append (terminal-input-read-ahead state) characters)))))

(defun %input-fd (stream)
  "Return the file descriptor behind input STREAM, following synonym streams, or NIL."
  (typecase stream
    (sb-sys:fd-stream (sb-sys:fd-stream-fd stream))
    (synonym-stream
     (let ((symbol (synonym-stream-symbol stream)))
       (and (boundp symbol) (%input-fd (symbol-value symbol)))))))

(defun %input-at-eof-p (stream)
  "Return true when STREAM, which its descriptor reports readable, is at end of file."
  (unless (listen stream)
    (let ((ch (read-char-no-hang stream nil :eof)))
      (when (characterp ch)
        (unread-char ch stream))
      (eq ch :eof))))

(defun query-cursor-position (&key (attempts 20) (sleep-seconds 0.005))
  "Return the terminal cursor position as 1-based ROW and COLUMN values.

Wait up to ATTEMPTS times SLEEP-SECONDS for the reply and read the stream
exactly through the reply's final byte, so that no reply is left for a later
reader or for the terminal to echo once raw mode is left.  A stream backed by
a file descriptor is waited on until it is readable; any other stream is
polled ATTEMPTS times, SLEEP-SECONDS apart.  Keys that arrive before the
reply are queued, in order, as read-ahead input.  When no reply arrives in
time, queue everything read, return NIL values, and send no more requests on
this stream."
  (let ((state (%terminal-input))
        (chars (make-array 16 :element-type 'character
                              :adjustable t :fill-pointer 0))
        (report-start nil)
        (fd (%input-fd *standard-input*)))
    (when (terminal-input-cursor-reports-unsupported-p state)
      (return-from query-cursor-position (values nil nil)))
    (ansi-request-cursor-position)
    (finish-output)
    (flet ((read-available ()
             (loop while (listen *standard-input*)
                   do (let ((ch (read-char *standard-input* nil nil)))
                        (unless ch
                          (return))
                        (when (char= ch +escape+)
                          (setf report-start (fill-pointer chars)))
                        (vector-push-extend ch chars)
                        (when (and report-start (char= ch #\R))
                          (let ((candidate (subseq chars report-start)))
                            (multiple-value-bind (row column consumed)
                                (cl-tty-kit:decode-cursor-position-report candidate)
                              (when (and row column (= consumed (length candidate)))
                                (%append-read-ahead
                                 (coerce (subseq chars 0 report-start) 'list))
                                (return-from query-cursor-position
                                  (values (1+ row) (1+ column)))))))))))
      (if fd
          (let ((deadline (+ (get-internal-real-time)
                             (round (* attempts sleep-seconds
                                       internal-time-units-per-second)))))
            (loop
              (read-available)
              (let ((remaining (/ (- deadline (get-internal-real-time))
                                  internal-time-units-per-second)))
                (when (or (<= remaining 0)
                          (not (sb-sys:wait-until-fd-usable fd :input remaining nil))
                          (%input-at-eof-p *standard-input*))
                  (read-available)
                  (return)))))
          (loop repeat attempts
                do (read-available)
                   (sleep sleep-seconds))))
    (%append-read-ahead (coerce chars 'list))
    (setf (terminal-input-cursor-reports-unsupported-p state) t)
    (values nil nil)))

(defun csi-final-char-p (ch)
  "Return true when CH is a CSI final byte."
  (let ((code (char-code ch)))
    (<= #x40 code #x7e)))

(defun read-csi-sequence (&key (limit 64))
  "Read a CSI body through its final byte without consuming following input."
  (let ((chars '()))
    (loop repeat limit
          for ch = (next-input-char)
          while ch
          do (push ch chars)
          when (csi-final-char-p ch)
            do (return))
    (coerce (nreverse chars) 'string)))

(defun read-ss3-sequence (&key (limit 8))
  "Read a short SS3 body without consuming unrelated following input."
  (let ((chars '()))
    (loop repeat limit
          for ch = (next-input-char)
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
      (loop for ch = (next-input-char)
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

(defun read-escape-key-event (&key vi-mode-p)
  "Read and decode one ESC-prefixed terminal input event."
  (let ((prefix (read-available-char)))
    (cond
      ((null prefix) (make-key-event :escape))
      ((char= prefix #\[)
       (let* ((sequence (read-csi-sequence))
              (event (decode-csi-sequence sequence)))
         (case (key-event-type event)
           (:bracketed-paste-start
            (make-key-event :paste nil nil
                            (list :protocol :bracketed
                                  :text (read-bracketed-paste-text))))
           (:bracketed-paste-end (make-key-event :ignore))
           (otherwise event))))
      ((char= prefix #\O)
       (decode-ss3-sequence (read-ss3-sequence)))
      (vi-mode-p
       (push-back-input (list prefix))
       (make-key-event :escape))
      (t (or (decode-meta-key prefix)
             (progn
               (push-back-input (list prefix))
               (make-key-event :escape)))))))

(defun read-key-event (&key interrupt-predicate idle-predicate
                           vi-mode-p vi-insert-mode-p)
  "Read and decode one terminal key event from standard input.
When INTERRUPT-PREDICATE is supplied, poll the stream so a pending signal can
be converted into a Ctrl-C key event without leaving the main loop blocked in
READ-CHAR.  Recheck after reading a character and leave it unread when an
interrupt arrived during the read.  A predicate may return a decoded event to
deliver it through the same polling path.  IDLE-PREDICATE is called only when
no terminal input is ready, so buffered keys always take priority over idle
events; its returned event is delivered through the same path.  When
VI-MODE-P or VI-INSERT-MODE-P is true, a non-sequence character following ESC
is delivered by the next call instead of being decoded as Meta."
  (let ((vi-mode-p (or vi-mode-p vi-insert-mode-p)))
    (if (and (null interrupt-predicate)
             (null idle-predicate))
        (let ((ch (next-input-char)))
          (when ch
            (decode-character-key ch :vi-mode-p vi-mode-p)))
        (loop
          for interrupt = (and interrupt-predicate
                               (funcall interrupt-predicate))
          when interrupt
            return (if (eq t interrupt)
                       (make-key-event :ctrl-c)
                       interrupt)
          when (input-ready-p)
            return (let ((ch (next-input-char)))
                     (when ch
                       (let ((interrupt
                               (and interrupt-predicate
                                    (funcall interrupt-predicate))))
                         (if interrupt
                             (progn
                               (push-back-input (list ch))
                               (if (eq t interrupt)
                                   (make-key-event :ctrl-c)
                                   interrupt))
                             (decode-character-key
                              ch :vi-mode-p vi-mode-p)))))
          do (let ((idle-event
                     (and idle-predicate (funcall idle-predicate))))
               (when idle-event
                 (return idle-event)))
          do (sleep 0.001)))))
