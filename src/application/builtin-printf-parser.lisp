(in-package #:nshell.application)

(defun %printf-read-flags (text index)
  (let ((start index))
    (loop while (and (< index (length text))
                     (find (char text index) "-+0# " :test #'char=))
          do (incf index))
    (values (subseq text start index) index)))

(defun %printf-read-decimal (text index)
  (let ((start index))
    (loop while (and (< index (length text))
                     (digit-char-p (char text index)))
          do (incf index))
    (values (when (> index start)
              (parse-integer text :start start :end index))
            index)))

(defun %printf-read-precision (text index)
  (if (and (< index (length text))
           (char= (char text index) #\.))
      (multiple-value-bind (precision next-index)
          (%printf-read-decimal text (1+ index))
        (values (or precision 0) next-index))
      (values nil index)))

(defun %printf-skip-length (text index)
  (loop while (and (< index (length text))
                   (find (char text index) "hlLjzt" :test #'char=))
        do (incf index))
  index)

(defun %printf-read-directive (text index)
  (multiple-value-bind (flags index) (%printf-read-flags text index)
    (multiple-value-bind (width index) (%printf-read-decimal text index)
      (multiple-value-bind (precision index) (%printf-read-precision text index)
        (setf index (%printf-skip-length text index))
        (if (>= index (length text))
            (values flags width precision nil index nil)
            (values flags width precision (char text index) (1+ index) t))))))

(defun %printf-conversion-p (conversion)
  (and conversion
       (find conversion "sbcdiuoxXeEfFgG" :test #'char=)))

(defun %printf-emit-directive (out format-string index arguments argument-index)
  (multiple-value-bind (flags width precision conversion next-index directive-p)
      (%printf-read-directive format-string index)
    (cond
      ((not directive-p)
       (values next-index argument-index nil nil nil))
      ((not (%printf-conversion-p conversion))
       (values next-index argument-index nil nil t))
      (t
       (let ((argument (if (< argument-index (length arguments))
                          (nth argument-index arguments)
                          "")))
         (multiple-value-bind (text value-valid-p value-stop-p)
             (%printf-format-value argument conversion flags width precision)
           (write-string text out)
           (values next-index (1+ argument-index)
                   value-valid-p value-stop-p t)))))))

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
                  (cond
                    ((char/= character #\%)
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
                           (incf format-index))))
                    (t
                     (incf format-index)
                     (cond
                       ((>= format-index (length format-string))
                        (setf valid-p nil)
                        (return))
                       ((char= (char format-string format-index) #\%)
                        (write-char #\% out)
                        (incf format-index))
                       (t
                        (multiple-value-bind (next-index next-argument-index
                                              directive-valid-p directive-stop-p
                                              directive-argument-p)
                            (%printf-emit-directive out format-string format-index
                                                     arguments argument-index)
                          (setf format-index next-index
                                argument-index next-argument-index
                                argument-conversion-p
                                (or argument-conversion-p directive-argument-p)
                                valid-p (and valid-p directive-valid-p))
                          (when (or (not directive-valid-p) directive-stop-p)
                            (setf stop-p directive-stop-p)
                            (return))))))))))
     argument-index
     argument-conversion-p
     valid-p
     stop-p)))
