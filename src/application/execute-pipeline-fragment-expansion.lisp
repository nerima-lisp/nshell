(in-package #:nshell.application)

(defconstant +command-fragment-escape-base+ #xe100)
(defconstant +command-fragment-escape-limit+
  (+ +command-fragment-escape-base+ 256))

(defun %protect-command-fragment-escapes (value positions)
  (let ((protected (copy-seq (nshell.domain.expansion::%encode-fragment-data value))))
    (dolist (position positions protected)
      (when (and (<= 0 position)
                 (< position (length protected)))
        (let ((code (char-code (char value position))))
          (when (< code 256)
            (setf (char protected position)
                  (code-char (+ +command-fragment-escape-base+ code)))))))))

(defun %restore-command-fragment-escapes (value)
  (when nshell.domain.expansion::*fragment-escape-context*
    (return-from %restore-command-fragment-escapes
      (nshell.domain.expansion::%decode-fragment-data value)))
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

(defun %protect-quoted-fragment-globs (fields style)
  (if (null style)
      fields
      (mapcar (lambda (field)
                (map 'string
                     (lambda (character)
                       (if (nshell.domain.expansion::glob-char-p character)
                           (code-char (+ +command-fragment-escape-base+
                                         (char-code character)))
                           character))
                     field))
              fields)))

(defun %expand-complete-fragment-fields (fields filesystem)
  ;; Globbing sees the complete word, but quoted metacharacters remain protected.
  (loop for field in fields
        append (mapcar #'%restore-command-fragment-escapes
                       (nshell.domain.expansion::%expand-glob-with-prefix
                        field filesystem))))

(defun %expand-source-fragment-fields
    (fragment environment &optional filesystem (glob-p t))
  (let* ((value (nshell.domain.parsing:command-fragment-value fragment))
         (protected
           (%protect-command-fragment-escapes
            value
            (nshell.domain.parsing:command-fragment-escaped-positions
             fragment))))
    (nshell.domain.expansion:expand-by-quote-style
     (nshell.domain.parsing:command-fragment-quote-style fragment)
     (if environment
         (nshell.domain.expansion:expand-all protected environment filesystem glob-p)
         (list protected))
     (list protected)
     (if environment
         (list
           (nshell.domain.expansion:expand-double-quoted
            protected environment))
         (list protected)))))
