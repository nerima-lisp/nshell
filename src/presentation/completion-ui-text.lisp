(in-package #:nshell.presentation)

(defun %completion-escape-character-p (ch)
  (or (<= 0 (char-code ch) 31)
      (= (char-code ch) 127)
      (member ch '(#\Space #\\ #\' #\" #\; #\| #\& #\(
                   #\) #\< #\> #\$ #\` #\* #\? #\[ #\] #\{
                   #\} #\! #\#)
              :test #'char=)))

(defun %completion-double-quoted-escape-character-p (ch)
  (or (char= ch #\\)
      (char= ch #\")
      (char= ch #\$)
      (char= ch #\`)))

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

(defun %completion-unquoted-insertion-text (text)
  (if (position #\Newline text)
      (concatenate 'string
                   "'"
                   (%completion-single-quoted-insertion-text text)
                   "'")
      (with-output-to-string (out)
        (loop for ch across text
              do (when (%completion-escape-character-p ch)
                   (write-char #\\ out))
                 (write-char ch out)))))

(%define-escape-formatter %completion-double-quoted-insertion-text
  %completion-double-quoted-escape-character-p)

(defun %completion-insertion-text (text &key quote-context)
  (ecase quote-context
    ((nil) (%completion-unquoted-insertion-text text))
    (:single (%completion-single-quoted-insertion-text text))
    (:double (%completion-double-quoted-insertion-text text))))
(defun %completion-candidate-insertion-text
    (text kind raw-token &key quote-context)
  (if (eq kind :variable)
      text
      (let ((prefix-end
              (when (null quote-context)
                (let* ((length (length raw-token))
                       (braced-p
                         (and (> length 2)
                              (char= (char raw-token 0) #\$)
                              (char= (char raw-token 1) #\{)))
                       (name-start (if braced-p 2 1))
                       (name-end
                         (if braced-p
                             (position #\} raw-token :start name-start)
                             (position-if-not
                              (lambda (character)
                                (or (alphanumericp character)
                                    (char= character #\_)))
                              raw-token
                              :start (min name-start length))))
                       (slash-position
                         (if braced-p
                             (and name-end (1+ name-end))
                             name-end)))
                  (and name-end
                       (> name-end name-start)
                       slash-position
                       (< slash-position length)
                       (char= (char raw-token slash-position) #\/)
                       (1+ slash-position))))))
        (if (and prefix-end
                 (>= (length text) prefix-end)
                 (string= raw-token text :end1 prefix-end :end2 prefix-end))
            (concatenate 'string
                         (subseq text 0 prefix-end)
                         (%completion-insertion-text
                          (subseq text prefix-end)
                          :quote-context quote-context))
            (%completion-insertion-text text :quote-context quote-context)))))

(defun %completion-unescape-token (text &key quote-context)
  (with-output-to-string (out)
    (let ((escaped nil)
          (index 0)
          (limit (length text)))
      (loop while (< index limit)
            for ch = (char text index)
            do (cond
                 ((and (eq quote-context :single)
                       (<= (+ index 4) limit)
                       (char= ch #\')
                       (char= (char text (1+ index)) #\\)
                       (char= (char text (+ index 2)) #\')
                       (char= (char text (+ index 3)) #\'))
                  (write-char #\' out)
                  (incf index 4))
                 (escaped
                  (unless (char= ch #\Newline)
                    (if (or (null quote-context)
                            (and (eq quote-context :double)
                                 (%completion-double-quoted-escape-character-p ch)))
                        (write-char ch out)
                        (progn
                          (write-char #\\ out)
                          (write-char ch out))))
                  (setf escaped nil)
                  (incf index))
                 ((and (char= ch #\\) (not (eq quote-context :single)))
                  (setf escaped t)
                  (incf index))
                 (t
                  (write-char ch out)
                  (incf index))))
      (when escaped (write-char #\\ out)))))
