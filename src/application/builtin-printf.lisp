(in-package #:nshell.application)

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
                                            (if (find conversion *printf-conversions*
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
