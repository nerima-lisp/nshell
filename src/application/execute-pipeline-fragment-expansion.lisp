(in-package #:nshell.application)

(defparameter +command-fragment-escape-base+ #xe100)
(defparameter +command-fragment-escape-limit+
  (+ +command-fragment-escape-base+ 256))

(defun %protect-command-fragment-escapes (value positions)
  (let ((protected (copy-seq value)))
    (dolist (position positions protected)
      (when (and (<= 0 position)
                 (< position (length protected)))
        (let ((code (char-code (char protected position))))
          (when (< code 256)
            (setf (char protected position)
                  (code-char (+ +command-fragment-escape-base+ code)))))))))

(defun %restore-command-fragment-escapes (value)
  (with-output-to-string (out)
    (loop for character across value
          for code = (char-code character)
          do (if (and (>= code +command-fragment-escape-base+)
                      (< code +command-fragment-escape-limit+))
                 (write-char
                  (code-char (- code +command-fragment-escape-base+))
                  out)
                 (write-char character out)))))

(defun %append-expanded-fragment-fields (prefixes fields)
  (loop for prefix in prefixes
        append (loop for field in (or fields (list ""))
                     collect (concatenate 'string prefix field))))

(defun %expand-source-fragment-fields (fragment environment &optional filesystem)
  (let* ((value (nshell.domain.parsing:command-fragment-value fragment))
         (protected
           (%protect-command-fragment-escapes
            value
            (nshell.domain.parsing:command-fragment-escaped-positions
             fragment))))
    (nshell.domain.expansion:expand-by-quote-style
     (nshell.domain.parsing:command-fragment-quote-style fragment)
     (if environment
         (nshell.domain.expansion:expand-all protected environment filesystem)
         (list protected))
     (list protected)
     (if environment
         (list
           (nshell.domain.expansion:expand-double-quoted
            protected environment))
         (list protected)))))
