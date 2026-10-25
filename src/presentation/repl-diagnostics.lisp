;;; REPL parse diagnostics
(in-package #:nshell.presentation)

(defun format-parse-diagnostic (diagnostic)
  (format nil "~a at column ~d"
          (nshell.domain.parsing:parse-diagnostic-message diagnostic)
          (1+ (nshell.domain.parsing:parse-diagnostic-start diagnostic))))

(defun format-parse-diagnostic-lines (result)
  (mapcar (lambda (diagnostic)
            (format nil "nshell: syntax error: ~a"
                    (format-parse-diagnostic diagnostic)))
          (nshell.domain.parsing:parse-errors result)))

(defun report-parse-diagnostics (result &optional (stream *error-output*))
  (dolist (line (format-parse-diagnostic-lines result))
    (format stream "~a~%" line)))
(defun format-sexpr-source-diagnostic (condition source)
  (labels ((condition-fields (condition)
             (cond
               ((typep condition 'nshell.domain.parsing:sexp-reader-error)
                (values
                 (nshell.domain.parsing:sexp-reader-error-source-path condition)
                 (nshell.domain.parsing:sexp-reader-error-source-span condition)
                 (nshell.domain.parsing:sexp-reader-error-cause condition)
                 (nshell.domain.parsing:sexp-reader-error-source-map condition)))
               ((typep condition 'nshell.application:sexp-evaluation-syntax-error)
                (values
                 (nshell.application:sexp-evaluation-syntax-error-source-path condition)
                 (nshell.application:sexp-evaluation-syntax-error-source-span condition)
                 (nshell.application:sexp-evaluation-syntax-error-cause condition)
                 nil))
               ((typep condition 'nshell.application:command-macro-syntax-error)
                (values
                 (nshell.application:command-macro-syntax-error-source-path condition)
                 (nshell.application:command-macro-syntax-error-source-span condition)
                 (nshell.application:command-macro-syntax-error-cause condition)
                 nil))
               (t (values nil nil condition nil))))
           (single-line (value)
             (let ((text (if (stringp value) value (princ-to-string value))))
               (with-output-to-string (stream)
                 (loop for character across text
                       do (write-char
                           (if (member character '(#\Newline #\Return) :test #'char=)
                               #\Space
                               character)
                           stream)))))
           (cause-text (cause)
             (cond
               ((null cause) "unknown cause")
               ((typep cause 'simple-condition)
                (let ((control (simple-condition-format-control cause))
                      (arguments (simple-condition-format-arguments cause)))
                  (if (stringp control)
                      (apply #'format nil control arguments)
                      (princ-to-string control))))
               (t (princ-to-string cause))))
           (mapped-span (source-map span)
             (let* ((start (and (consp span) (first span)))
                    (end (and (consp span) (second span)))
                    (map-length (if (vectorp source-map)
                                    (length source-map)
                                    0)))
               (if (and (vectorp source-map)
                        (integerp start)
                        (integerp end)
                        (<= 0 start end map-length)
                        (or (= start end)
                            (and (consp (aref source-map start))
                                 (consp (aref source-map (1- end))))))
                   (if (= start end)
                       (let ((anchor
                               (if (< start map-length)
                                   (first (aref source-map start))
                                   (if (plusp map-length)
                                       (second (aref source-map
                                                     (1- map-length)))
                                       0))))
                         (list anchor anchor))
                       (list (first (aref source-map start))
                             (second (aref source-map (1- end)))))
                   span))))
    (multiple-value-bind (path span cause source-map)
        (condition-fields condition)
      (let* ((source-text (if (stringp source) source ""))
             (span (mapped-span source-map span))
             (raw-start (and (consp span) (first span)))
             (raw-end (and (consp span) (second span)))
             (start (if (and (integerp raw-start) (not (minusp raw-start)))
                        raw-start
                        0))
             (end (if (and (integerp raw-end) (>= raw-end start))
                      raw-end
                      start))
             (bounded-start (min start (length source-text)))
             (line (1+ (count #\Newline source-text :end bounded-start)))
             (previous-newline
               (position #\Newline source-text :end bounded-start :from-end t))
             (column (- bounded-start (or previous-newline -1)))
             (path-text
               (typecase path
                 (null "<input>")
                 (pathname (namestring path))
                 (t (princ-to-string path))))
             (message (cause-text cause)))
        (format nil "nshell: ~a:~d:~d: syntax error [~d,~d): ~a"
                (single-line path-text)
                line column start end (single-line message))))))
(defun %read-repl-source-text (path)
  (with-open-file (stream path :direction :input)
    (format nil "~{~a~^~%~}"
            (nshell.application:collect-source-lines stream))))
(defun format-sexpr-source-diagnostic-for-input (condition fallback-source)
  (let ((source-path
          (typecase condition
            (nshell.domain.parsing:sexp-reader-error
             (nshell.domain.parsing:sexp-reader-error-source-path condition))
            (nshell.application:sexp-evaluation-syntax-error
             (nshell.application:sexp-evaluation-syntax-error-source-path condition))
            (nshell.application:command-macro-syntax-error
             (nshell.application:command-macro-syntax-error-source-path condition))
            (t nil))))
    (format-sexpr-source-diagnostic
     condition
     (if source-path
         (%read-repl-source-text source-path)
         fallback-source))))

