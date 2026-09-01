(in-package #:nshell.application)

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
         (base (case conversion
                 ((#\x #\X) 16)
                 (#\o 8)
                 (otherwise 10)))
         (digits (case base
                   (16 (format nil "~x" unsigned))
                   (8 (format nil "~o" unsigned))
                   (otherwise (format nil "~d" unsigned))))
         (digits (if (char= conversion #\X)
                     (string-upcase digits)
                     digits))
         (digits (if precision
                     (concatenate 'string
                                  (make-string (max 0 (- precision (length digits)))
                                               :initial-element #\0)
                                  digits)
                     digits))
         (prefix (if (and (%printf-flag-p flags #\#)
                         (not (zerop unsigned)))
                     (case conversion
                       (#\x "0x")
                       (#\X "0X")
                       (#\o "0")
                       (otherwise ""))
                     ""))
         (sign (cond
                 (negative "-")
                 ((%printf-flag-p flags #\+) "+")
                 ((%printf-flag-p flags #\Space) " ")
                 (t ""))))
    (concatenate 'string sign prefix digits)))

(defun %printf-format-real (argument conversion flags width precision)
  (multiple-value-bind (number valid-p) (%printf-parse-real argument)
    (let* ((digits (or precision 6))
           (directive (case conversion
                        ((#\e #\E) "e")
                        ((#\g #\G) "g")
                        (otherwise "f")))
           (text (format nil
                         (concatenate 'string "~," (princ-to-string digits) directive)
                         number))
           (text (if (and (member conversion '(#\E #\G))
                          (position #\e text))
                     (substitute #\E #\e text)
                     text))
           (text (if (and (not (minusp number))
                          (%printf-flag-p flags #\+))
                     (concatenate 'string "+" text)
                     (if (and (not (minusp number))
                              (%printf-flag-p flags #\Space))
                         (concatenate 'string " " text)
                         text))))
      (values (%printf-pad text width (%printf-flag-p flags #\-)
                           (if (and (%printf-flag-p flags #\0)
                                    (not (%printf-flag-p flags #\-)))
                               #\0
                               #\Space))
              valid-p
              nil))))

(defun %printf-format-value (argument conversion flags width precision)
  (case conversion
    (#\s
     (values (%printf-pad (if precision
                              (subseq argument 0 (min precision (length argument)))
                              argument)
                          width
                          (%printf-flag-p flags #\-))
             t
             nil))
    (#\b
     (multiple-value-bind (text stop-p) (%printf-expand-escapes argument)
       (values (%printf-pad (if precision
                              (subseq text 0 (min precision (length text)))
                              text)
                          width
                          (%printf-flag-p flags #\-))
               t
               stop-p)))
    (#\c
     (values (%printf-pad (if (plusp (length argument))
                              (string (char argument 0))
                              (string #\Null))
                          width
                          (%printf-flag-p flags #\-))
             t
             nil))
    ((#\d #\i #\u #\o #\x #\X)
     (multiple-value-bind (number valid-p) (%printf-parse-integer argument)
       (values (%printf-pad (%printf-integer-text number conversion flags precision)
                            width
                            (%printf-flag-p flags #\-)
                            (if (and (%printf-flag-p flags #\0)
                                     (not (%printf-flag-p flags #\-))
                                     (null precision))
                                #\0
                                #\Space))
               valid-p
               nil)))
    ((#\e #\E #\f #\g #\G)
     (%printf-format-real argument conversion flags width precision))
    (otherwise (values "" nil nil))))

(defun %printf-format-once (format-string arguments)
  (let ((format-index 0)
        (argument-index 0)
        (argument-conversion-p nil)
        (valid-p t)
        (stop-p nil))
    (values
     (with-output-to-string (out)
       (loop while (< format-index (length format-string))
             do (let ((character (char format-string format-index)))
                  (if (char/= character #\%)
                      (if (char= character #\\)
                          (multiple-value-bind (replacement next-index escape-stop-p)
                              (%printf-read-escape format-string (1+ format-index))
                            (write-string replacement out)
                            (setf format-index next-index
                                  stop-p escape-stop-p)
                            (when stop-p
                              (return)))
                          (progn
                            (write-char character out)
                            (incf format-index)))
                      (progn
                        (incf format-index)
                        (if (>= format-index (length format-string))
                            (progn
                              (setf valid-p nil)
                              (return))
                            (if (char= (char format-string format-index) #\%)
                                (progn
                                  (write-char #\% out)
                                  (incf format-index))
                                (let ((flags ""))
                                  (loop while (and (< format-index (length format-string))
                                                   (find (char format-string format-index)
                                                         "-+0# "
                                                         :test #'char=))
                                        do (setf flags
                                                 (concatenate 'string
                                                              flags
                                                              (string (char format-string format-index)))
                                             format-index (1+ format-index)))
                                  (let ((width-start format-index)
                                        (precision nil))
                                    (loop while (and (< format-index (length format-string))
                                                     (digit-char-p (char format-string format-index)))
                                          do (incf format-index))
                                    (let ((width (when (> format-index width-start)
                                                   (parse-integer format-string
                                                                  :start width-start
                                                                  :end format-index))))
                                      (when (and (< format-index (length format-string))
                                                 (char= (char format-string format-index) #\.))
                                        (incf format-index)
                                        (let ((precision-start format-index))
                                          (loop while (and (< format-index (length format-string))
                                                           (digit-char-p (char format-string format-index)))
                                                do (incf format-index))
                                          (setf precision
                                                (if (= precision-start format-index)
                                                    0
                                                    (parse-integer format-string
                                                                   :start precision-start
                                                                   :end format-index)))))
                                      (loop while (and (< format-index (length format-string))
                                                       (find (char format-string format-index)
                                                             "hlLjzt"
                                                             :test #'char=))
                                            do (incf format-index))
                                      (if (>= format-index (length format-string))
                                          (progn
                                            (setf valid-p nil)
                                            (return))
                                          (let ((conversion (char format-string format-index)))
                                            (incf format-index)
                                            (setf argument-conversion-p t)
                                            (if (find conversion "sbcdiuoxXeEfFgG"
                                                      :test #'char=)
                                                (let ((argument
                                                        (if (< argument-index (length arguments))
                                                            (nth argument-index arguments)
                                                            "")))
                                                  (incf argument-index)
                                                  (multiple-value-bind (text value-valid-p value-stop-p)
                                                      (%printf-format-value argument conversion flags width precision)
                                                    (write-string text out)
                                                    (unless value-valid-p
                                                      (setf valid-p nil))
                                                    (when value-stop-p
                                                      (setf stop-p t)
                                                      (return))))
                                                (progn
                                                  (setf valid-p nil)
                                                  (return)))))))))))))))
     argument-index
     argument-conversion-p
     valid-p
     stop-p)))

(define-builtin %builtin-printf (context args) (context)
  (let ((arguments (if (and args (string= (first args) "--"))
                       (rest args)
                       args)))
    (if (null arguments)
        (values nil 0)
        (let* ((format-string (first arguments))
              (remaining (rest arguments))
              (valid-p t)
              (output
                (with-output-to-string (out)
                  (loop
                    (multiple-value-bind (text consumed argument-conversion-p once-valid-p stop-p)
                        (%printf-format-once format-string remaining)
                      (write-string text out)
                      (setf valid-p (and valid-p once-valid-p)
                            remaining (nthcdr consumed remaining))
                      (when (or stop-p
                                (not once-valid-p)
                                (null remaining)
                                (not argument-conversion-p))
                        (return)))))))
          (values output (if valid-p 0 1))))))
