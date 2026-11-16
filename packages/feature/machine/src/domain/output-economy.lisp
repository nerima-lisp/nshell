(in-package #:nshell.feature.machine)

;;; Output economy of ux/U6: the text a response carries is cleaned of
;;; terminal control and cut to its head and tail when it is too long.

(defconstant +default-max-output-bytes+ 32768)
(defconstant +default-head-lines+ 10)
(defconstant +default-tail-lines+ 10)

;;; Cleaning

(defun %csi-final-p (char)
  (char<= (code-char #x40) char (code-char #x7e)))

(defun %escape-intermediate-p (char)
  (char<= (code-char #x20) char (code-char #x2f)))

(defun %skip-control-string (text start)
  "Return the index after the terminator (BEL, ESC \\ or ST) of the control
string whose body starts at START, or the length of TEXT when it is
unterminated."
  (loop with length = (length text)
        for index from start below length
        for char = (char text index)
        do (case (char-code char)
             ((#x07 #x9c) (return (1+ index)))
             (#x1b (when (and (< (1+ index) length)
                              (char= #\\ (char text (1+ index))))
                     (return (+ index 2)))))
        finally (return length)))

(defun %skip-csi (text start)
  "Return the index after the CSI sequence whose parameters start at START. A
character that cannot occur in the sequence ends it and is kept."
  (let ((end (or (position-if-not (lambda (char)
                                    (char<= (code-char #x20) char (code-char #x3f)))
                                  text :start start)
                 (length text))))
    (if (and (< end (length text)) (%csi-final-p (char text end)))
        (1+ end)
        end)))

(defun %skip-escape (text index)
  "Return the index after the escape sequence whose ESC is at INDEX."
  (let ((length (length text))
        (next (1+ index)))
    (if (>= next length)
        length
        (case (char text next)
          (#\[ (%skip-csi text (1+ next)))
          ((#\] #\P #\X #\^ #\_) (%skip-control-string text (1+ next)))
          (t (let ((final (or (position-if-not #'%escape-intermediate-p text
                                               :start next)
                              length)))
               (if (and (< final length)
                        (char<= (code-char #x30) (char text final) (code-char #x7e)))
                   (1+ final)
                   final)))))))

(defun %removed-control-p (char)
  (let ((code (char-code char)))
    (and (or (< code #x20) (<= #x7f code #x9f))
         (not (member code '(#x09 #x0a))))))

(defun clean-output-text (string)
  "Return STRING without ANSI escape sequences and control characters other
than newline and tab. On each line, a carriage return discards the text before
it once more text follows; a CR LF pair is a newline."
  (let ((line (make-string-output-stream))
        (overwrite-pending nil)
        (length (length string))
        (index 0))
    (with-output-to-string (out)
      (flet ((visible (char)
               (when overwrite-pending
                 (get-output-stream-string line)
                 (setf overwrite-pending nil))
               (write-char char line))
             (end-line ()
               (write-string (get-output-stream-string line) out)
               (write-char #\Newline out)
               (setf overwrite-pending nil)))
        (loop while (< index length)
              do (let ((char (char string index)))
                   (case (char-code char)
                     (#x1b (setf index (%skip-escape string index)))
                     (#x9b (setf index (%skip-csi string (1+ index))))
                     ((#x90 #x98 #x9d #x9e #x9f)
                      (setf index (%skip-control-string string (1+ index))))
                     (#x0d
                      (if (and (< (1+ index) length)
                               (char= #\Newline (char string (1+ index))))
                          (progn (end-line) (incf index 2))
                          (progn (setf overwrite-pending t) (incf index))))
                     (#x0a (end-line) (incf index))
                     (t (unless (%removed-control-p char)
                          (visible char))
                        (incf index))))))
      (write-string (get-output-stream-string line) out))))

;;; Truncation

(defun %char-utf-8-length (char)
  (let ((code (char-code char)))
    (cond ((< code #x80) 1)
          ((< code #x800) 2)
          ((< code #x10000) 3)
          (t 4))))

(defun %utf-8-length (text)
  (loop for char across text sum (%char-utf-8-length char)))

(defun %split-lines (text)
  "Return the lines of TEXT, each with its newline; the last one lacks it when
TEXT does not end in a newline."
  (loop with length = (length text)
        for start = 0 then (1+ end)
        while (< start length)
        for end = (or (position #\Newline text :start start) (1- length))
        collect (subseq text start (1+ end))))

(defun %utf-8-prefix (text limit)
  "Return the longest prefix of TEXT whose UTF-8 encoding fits in LIMIT bytes."
  (loop with bytes = 0
        for index from 0 below (length text)
        do (incf bytes (%char-utf-8-length (char text index)))
           (when (> bytes limit)
             (return (subseq text 0 index)))
        finally (return text)))

(defun %utf-8-suffix (text limit)
  "Return the longest suffix of TEXT whose UTF-8 encoding fits in LIMIT bytes."
  (loop with bytes = 0
        for index from (1- (length text)) downto 0
        do (incf bytes (%char-utf-8-length (char text index)))
           (when (> bytes limit)
             (return (subseq text (1+ index))))
        finally (return text)))

(defun economize-output-text (text &key (max-bytes +default-max-output-bytes+)
                                        (head-lines +default-head-lines+)
                                        (tail-lines +default-tail-lines+))
  "Return the part of cleaned TEXT a response shows, and whether it was cut.
Over MAX-BYTES, keep HEAD-LINES lines from the start and TAIL-LINES from the
end, each part cut to MAX-BYTES/2 bytes, joined by an omission marker line. A
single line keeps up to MAX-BYTES/2 bytes from each end."
  (let ((total-bytes (%utf-8-length text)))
    (when (<= total-bytes max-bytes)
      (return-from economize-output-text (values text nil)))
    (let* ((lines (%split-lines text))
           (count (length lines))
           ;; With fewer lines than HEAD-LINES + TAIL-LINES, split them so
           ;; the end of the output is still shown.
           (tail-count (min tail-lines (floor count 2)))
           (head-count (min head-lines (- count tail-count)))
           (omitted-lines (- count head-count tail-count))
           (part-limit (floor max-bytes 2))
           ;; A single line cannot be split into head and tail lines, so its
           ;; two ends are kept by bytes instead.
           (single-line-p (and (= count 1) (plusp head-lines) (plusp tail-lines)))
           (head (%utf-8-prefix
                  (apply #'concatenate 'string (subseq lines 0 head-count))
                  part-limit))
           (tail (%utf-8-suffix
                  (if single-line-p
                      (subseq text (length head))
                      (apply #'concatenate 'string (last lines tail-count)))
                  part-limit))
           (marker (if (plusp omitted-lines)
                       (format nil "… ~:D lines omitted …~%" omitted-lines)
                       (format nil "… ~:D bytes omitted …~%"
                               (- total-bytes
                                  (%utf-8-length head)
                                  (%utf-8-length tail))))))
      (values (concatenate 'string
                           head
                           (if (and (plusp (length head))
                                    (char/= #\Newline (char head (1- (length head)))))
                               (string #\Newline)
                               "")
                           marker
                           tail)
              t))))

(defun envelope-output-for-text (raw-text &key path
                                               (max-bytes +default-max-output-bytes+)
                                               (head-lines +default-head-lines+)
                                               (tail-lines +default-tail-lines+))
  "Return the ENVELOPE-OUTPUT for RAW-TEXT: cleaned and economized text, with
BYTES and LINES counting the whole cleaned text. PATH, where the caller saved
that cleaned text, is kept only when the text was cut."
  (let ((cleaned (clean-output-text raw-text)))
    (multiple-value-bind (shown truncated)
        (economize-output-text cleaned :max-bytes max-bytes
                                       :head-lines head-lines
                                       :tail-lines tail-lines)
      (make-envelope-output :text shown
                            :bytes (length (sb-ext:string-to-octets
                                            cleaned :external-format :utf-8))
                            :lines (%line-count cleaned)
                            :truncated truncated
                            :path (and truncated path)))))
