(in-package #:nshell.presentation)

(defun %completion-escape-character-p (ch)
  (or (member ch '(#\Space #\Tab #\\ #\' #\" #\; #\| #\& #\(
                   #\) #\< #\> #\$ #\` #\* #\? #\[ #\] #\{
                   #\} #\! #\#)
              :test #'char=)
      (char= ch #\Newline)))

(defun %completion-double-quoted-escape-character-p (ch)
  (or (char= ch #\\)
      (char= ch #\")
      (char= ch #\$)
      (char= ch #\`)
      (char= ch #\Newline)))

(defun %completion-quote-context (input start end)
  (declare (ignore end))
  (when (and (< start (length input))
             (member (char input start) '(#\" #\') :test #'char=))
    (if (char= (char input start) #\') :single :double)))

(defun %completion-quote-delimiters (input start end)
  (let ((quote-char (and (< start (length input))
                         (member (char input start) '(#\" #\') :test #'char=)
                         (char input start))))
    (if quote-char
        (values (string quote-char)
                (if (and (< start (1- end))
                         (char= (char input (1- end)) quote-char))
                    (string quote-char) ""))
        (values "" ""))))

(defun %completion-splice-with-quote-context (input start end replacement
                                                   &key quote-context)
  (multiple-value-bind (quote-prefix quote-suffix)
      (if quote-context (%completion-quote-delimiters input start end)
          (values "" ""))
    (values (concatenate 'string (subseq input 0 start) quote-prefix
                         replacement quote-suffix (subseq input end))
            (+ start (length quote-prefix) (length replacement)))))

(defun %completion-single-quoted-insertion-text (text)
  (with-output-to-string (out)
    (loop with start = 0
          for index from 0 below (length text)
          for ch = (char text index)
          do (when (char= ch #\')
               (when (< start index) (write-string text out :start start :end index))
               (write-string "'\\''" out)
               (setf start (1+ index)))
          finally (when (< start (length text))
                    (write-string text out :start start)))))

(defmacro %define-escape-formatter (name predicate)
  "Generate a function NAME that writes TEXT with matching characters escaped."
  `(defun ,name (text)
     (with-output-to-string (out)
       (loop for ch across text
             do (when (,predicate ch) (write-char #\\ out))
                (write-char ch out)))))

(%define-escape-formatter %completion-unquoted-insertion-text
  %completion-escape-character-p)

(%define-escape-formatter %completion-double-quoted-insertion-text
  %completion-double-quoted-escape-character-p)

(defun %completion-insertion-text (text &key quote-context)
  (ecase quote-context
    ((nil) (%completion-unquoted-insertion-text text))
    (:single (%completion-single-quoted-insertion-text text))
    (:double (%completion-double-quoted-insertion-text text))))

(defun %completion-unescape-token (text &key quote-context)
  (with-output-to-string (out)
    (let ((escaped nil))
      (loop for ch across text
            do (cond
                 (escaped
                  (if (or (null quote-context)
                          (and (eq quote-context :double)
                               (%completion-double-quoted-escape-character-p ch)))
                      (write-char ch out)
                      (progn (write-char #\\ out) (write-char ch out)))
                  (setf escaped nil))
                 ((and (char= ch #\\) (not (eq quote-context :single)))
                  (setf escaped t))
                 (t (write-char ch out))))
      (when escaped (write-char #\\ out)))))
