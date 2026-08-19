(in-package #:nshell.application)

(defun %printf-pad (text width left-p &optional (pad-character #\Space))
  (let ((padding (max 0 (- (or width 0) (length text)))))
    (if (zerop padding)
        text
        (let ((padding-text (make-string padding :initial-element pad-character)))
          (if left-p
              (concatenate 'string text padding-text)
              (concatenate 'string padding-text text))))))

(defun %printf-flag-p (flags flag)
  (find flag flags :test #'char=))

(defun %printf-read-escape (text index)
  (if (>= index (length text))
      (values "\\" index nil)
      (let ((character (char text index)))
        (case character
          (#\a (values (string (code-char 7)) (1+ index) nil))
          (#\b (values (string #\Backspace) (1+ index) nil))
          (#\c (values "" (1+ index) t))
          (#\e (values (string (code-char 27)) (1+ index) nil))
          (#\f (values (string #\Page) (1+ index) nil))
          (#\n (values (string #\Newline) (1+ index) nil))
          (#\r (values (string #\Return) (1+ index) nil))
          (#\t (values (string #\Tab) (1+ index) nil))
          (#\v (values (string (code-char 11)) (1+ index) nil))
          (#\\ (values (string #\\) (1+ index) nil))
          (#\0
           (let ((cursor (1+ index))
                 (value 0)
                 (digits 0))
             (loop while (and (< cursor (length text))
                              (< digits 3)
                              (find (char text cursor) "01234567" :test #'char=))
                   do (setf value (+ (* value 8)
                                      (- (char-code (char text cursor))
                                         (char-code #\0)))
                          cursor (1+ cursor)
                          digits (1+ digits)))
             (values (string (or (code-char value) #\Null)) cursor nil)))
          (otherwise (values (string character) (1+ index) nil))))))

(defun %printf-expand-escapes (text)
  (let* ((stop nil)
         (result
           (with-output-to-string (out)
             (loop with index = 0
                   while (< index (length text))
                   do (if (char= (char text index) #\\)
                          (multiple-value-bind (replacement next-index stop-p)
                              (%printf-read-escape text (1+ index))
                            (write-string replacement out)
                            (setf index next-index
                                  stop stop-p)
                            (when stop
                              (return)))
                          (progn
                            (write-char (char text index) out)
                            (incf index)))))))
    (values result stop)))

(defun %printf-parse-integer (argument)
  (handler-case
      (values (parse-integer argument :junk-allowed nil) t)
    (error () (values 0 nil))))

(defun %printf-parse-real (argument)
  (handler-case
      (let ((*read-eval* nil))
        (multiple-value-bind (value position)
            (read-from-string argument nil nil)
          (if (and (realp value)
                   (= position (length argument)))
              (values (coerce value 'double-float) t)
              (values 0d0 nil))))
    (error () (values 0d0 nil))))

(defun %printf-integer-text (number conversion flags precision)
  (let* ((negative (minusp number))
         (unsigned (if negative (abs number) number))
         (base (cond
                 ((or (char= conversion #\x) (char= conversion #\X)) 16)
                 ((char= conversion #\o) 8)
                 (t 10)))
         (digits (case base
                   (16 (format nil "~x" unsigned))
                   (8 (format nil "~o" unsigned))
                   (otherwise (format nil "~d" unsigned))))
         (digits (cond
                   ((char= conversion #\X) (string-upcase digits))
                   ((char= conversion #\x) (string-downcase digits))
                   (t digits)))
         (digits (if precision
                     (concatenate 'string
                                  (make-string (max 0 (- precision (length digits)))
                                               :initial-element #\0)
                                  digits)
                     digits))
         (prefix (if (and (%printf-flag-p flags #\#)
                          (not (zerop unsigned)))
                     (cond
                       ((char= conversion #\x) "0x")
                       ((char= conversion #\X) "0X")
                       ((char= conversion #\o) "0")
                       (t ""))
                     ""))
         (sign (cond
                 (negative "-")
                 ((%printf-flag-p flags #\+) "+")
                 ((%printf-flag-p flags #\Space) " ")
                 (t ""))))
    (concatenate 'string sign prefix digits)))

(defun %printf-truncate (text precision)
  (if precision
      (subseq text 0 (min precision (length text)))
      text))

(defun %printf-format-text-value (argument flags width precision)
  (%printf-pad (%printf-truncate argument precision)
               width
               (%printf-flag-p flags #\-)))

(defun %printf-format-binary-value (argument flags width precision)
  (multiple-value-bind (text stop-p) (%printf-expand-escapes argument)
    (values (%printf-pad (%printf-truncate text precision)
                         width
                         (%printf-flag-p flags #\-))
            stop-p)))

(defun %printf-format-character-value (argument flags width)
  (%printf-pad (if (plusp (length argument))
                   (string (char argument 0))
                   (string #\Null))
               width
               (%printf-flag-p flags #\-)))

(defun %printf-zero-pad-p (flags precision)
  (and (%printf-flag-p flags #\0)
       (not (%printf-flag-p flags #\-))
       (null precision)))

(defun %printf-format-integer-value (argument conversion flags width precision)
  (multiple-value-bind (number valid-p) (%printf-parse-integer argument)
    (values (%printf-pad (%printf-integer-text number conversion flags precision)
                         width
                         (%printf-flag-p flags #\-)
                         (if (%printf-zero-pad-p flags precision)
                             #\0
                             #\Space))
            valid-p)))

(defun %printf-real-text (number conversion flags precision)
  (let* ((digits (or precision 6))
         (text (cond
                 ((or (char= conversion #\e) (char= conversion #\E))
                  (format nil "~,vE" digits number))
                 ((or (char= conversion #\g) (char= conversion #\G))
                  (format nil "~,vG" digits number))
                 (t
                  (format nil "~,vF" digits number))))
         (text (if (or (char= conversion #\E) (char= conversion #\G))
                   (substitute #\E #\d (substitute #\E #\e text))
                   text)))
    (if (and (not (minusp number))
             (%printf-flag-p flags #\+))
        (concatenate 'string "+" text)
        (if (and (not (minusp number))
                 (%printf-flag-p flags #\Space))
            (concatenate 'string " " text)
            text))))

(defun %printf-format-real-value (argument conversion flags width precision)
  (multiple-value-bind (number valid-p) (%printf-parse-real argument)
    (values (%printf-pad (%printf-real-text number conversion flags precision)
                         width
                         (%printf-flag-p flags #\-)
                         (if (and (%printf-flag-p flags #\0)
                                  (not (%printf-flag-p flags #\-)))
                             #\0
                             #\Space))
            valid-p)))

(defun %printf-format-value (argument conversion flags width precision)
  (cond
    ((char= conversion #\s)
     (values (%printf-format-text-value argument flags width precision)
             t
             nil))
    ((char= conversion #\b)
     (multiple-value-bind (text stop-p)
         (%printf-format-binary-value argument flags width precision)
       (values text t stop-p)))
    ((char= conversion #\c)
     (values (%printf-format-character-value argument flags width)
             t
             nil))
    ((find conversion "diuoxX" :test #'char=)
     (multiple-value-bind (text valid-p)
         (%printf-format-integer-value argument conversion flags width precision)
       (values text valid-p nil)))
    ((find conversion "eEfgG" :test #'char=)
     (multiple-value-bind (text valid-p)
         (%printf-format-real-value argument conversion flags width precision)
       (values text valid-p nil)))
    (t (values "" nil nil))))
