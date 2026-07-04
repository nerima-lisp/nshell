(in-package #:nshell.presentation)


(defun %candidate-text (candidate)
  (if (stringp candidate)
      candidate
      (nshell.domain.completion:candidate-text candidate)))

(defun %candidate-kind (candidate)
  (if (stringp candidate)
      :command
      (or (nshell.domain.completion:candidate-kind candidate) :command)))

(defun %candidate-description (candidate)
  (and (not (stringp candidate))
       (nshell.domain.completion:candidate-description candidate)))

(defun %common-prefix-two (left right)
  (let* ((limit (min (length left) (length right)))
         (index 0))
    (loop while (and (< index limit)
                     (char= (char left index) (char right index)))
          do (incf index))
    (subseq left 0 index)))

(defun completion-common-prefix (candidates)
  (when candidates
    (reduce #'%common-prefix-two
            (mapcar #'%candidate-text candidates))))

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
    (if (char= (char input start) #\')
        :single
        :double)))

(defun %completion-quote-delimiters (input start end)
  (let ((quote-char (and (< start (length input))
                         (member (char input start) '(#\" #\') :test #'char=)
                         (char input start))))
    (if quote-char
        (values (string quote-char)
                (if (and (< start (1- end))
                         (char= (char input (1- end)) quote-char))
                    (string quote-char)
                    ""))
        (values "" ""))))

(defun %completion-splice-with-quote-context (input start end replacement
                                                   &key quote-context)
  (multiple-value-bind (quote-prefix quote-suffix)
      (if quote-context
          (%completion-quote-delimiters input start end)
          (values "" ""))
    (values (concatenate 'string
                         (subseq input 0 start)
                         quote-prefix
                         replacement
                         quote-suffix
                         (subseq input end))
            (+ start
               (length quote-prefix)
               (length replacement)))))

(defun %completion-single-quoted-insertion-text (text)
  (with-output-to-string (out)
    (loop with start = 0
          for index from 0 below (length text)
          for ch = (char text index)
          do (when (char= ch #\')
               (when (< start index)
                 (write-string text out :start start :end index))
               (write-string "'\\''" out)
               (setf start (1+ index)))
          finally (when (< start (length text))
                    (write-string text out :start start)))))

(defmacro %define-escape-formatter (name predicate)
  "Generate a function NAME that writes TEXT with each char matching PREDICATE
preceded by a backslash."
  `(defun ,name (text)
     (with-output-to-string (out)
       (loop for ch across text
             do (when (,predicate ch)
                  (write-char #\\ out))
                (write-char ch out)))))

(%define-escape-formatter %completion-unquoted-insertion-text
  %completion-escape-character-p)

(%define-escape-formatter %completion-double-quoted-insertion-text
  %completion-double-quoted-escape-character-p)

(defun %completion-insertion-text (text &key quote-context)
  (ecase quote-context
    ((nil)    (%completion-unquoted-insertion-text text))
    (:single  (%completion-single-quoted-insertion-text text))
    (:double  (%completion-double-quoted-insertion-text text))))

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
                      (progn
                        (write-char #\\ out)
                        (write-char ch out)))
                  (setf escaped nil))
                 ((and (char= ch #\\)
                       (not (eq quote-context :single)))
                  (setf escaped t))
                 (t
                  (write-char ch out))))
      (when escaped
        (write-char #\\ out)))))

(defun %completion-escaped-position-p (input position)
  (let ((count 0)
        (index (1- position)))
    (loop while (and (>= index 0)
                     (char= (char input index) #\\))
          do (incf count)
             (decf index))
    (oddp count)))

(defun %completion-token-separator-at-p (input position)
  (and (nshell.domain.parsing:shell-token-separator-p (char input position))
       (not (%completion-escaped-position-p input position))))

(defun %completion-token-bounds (input cursor)
  (let* ((limit (length input))
         (cursor (max 0 (min cursor limit))))
    (cond
      ((and (< cursor limit)
            (%completion-token-separator-at-p input cursor))
       (let ((range (shell-token-range-before-position input cursor)))
         (if range
             (values (shell-token-range-start range)
                     (shell-token-range-end range))
             (values cursor cursor))))
      ((and (= cursor limit)
            (plusp limit)
            (%completion-token-separator-at-p input (1- limit)))
       (values cursor cursor))
      (t
       (let ((range (shell-token-range-at-or-after-cursor input cursor)))
         (if (null range)
             (values cursor cursor)
             (values (shell-token-range-start range)
                     (shell-token-range-end range))))))))

(defun %completion-token-body-bounds (input start end)
  (let ((body-start start)
        (body-end end)
        (quote-char (and (< start end)
                         (member (char input start) '(#\" #\') :test #'char=)
                         (char input start))))
    (when quote-char
      (incf body-start))
    (when (and quote-char
               (< body-start body-end)
               (char= (char input (1- body-end)) quote-char))
      (decf body-end))
    (values body-start body-end)))

(defun maybe-extend-completion-common-prefix (state candidates)
  "Apply an unambiguous completion prefix, if CANDIDATES advance the token."
  (with-normalized-input-state (state state)
    (let ((buffer (input-state-buffer state))
          (cursor (input-state-cursor-pos state))
          (prefix (completion-common-prefix candidates)))
      (if (null prefix)
        (values state nil)
          (multiple-value-bind (start end) (%completion-token-bounds buffer cursor)
            (multiple-value-bind (body-start body-end)
                (%completion-token-body-bounds buffer start end)
              (let* ((token (subseq buffer body-start body-end))
                     (quote-context (%completion-quote-context buffer start end))
                     (raw-token (%completion-unescape-token
                                 token
                                 :quote-context quote-context)))
                (if (and (> (length prefix) (length raw-token))
                         (<= (length raw-token) (length prefix))
                         (string= raw-token (subseq prefix 0 (length raw-token))))
                  (let* ((insertion (%completion-insertion-text prefix
                                                                :quote-context quote-context))
                         (new-buffer (%completion-splice-with-quote-context
                                      buffer start end insertion
                                      :quote-context quote-context)))
                      (values (copy-input-state-clearing-completion
                               state
                               :buffer new-buffer
                               :cursor-pos (+ start
                                              (if quote-context 1 0)
                                              (length insertion)))
                              t))
                    (values state nil)))))))))

(defun cycle-completion (candidates current)
  (let ((n (length candidates)))
    (if (zerop n) 0 (mod (1+ current) n))))

(defun apply-completion (input candidate &key (cursor (length input)))
  (multiple-value-bind (start end) (%completion-token-bounds input cursor)
    (let* ((quote-context (%completion-quote-context input start end))
           (text (%completion-insertion-text (%candidate-text candidate)
                                             :quote-context quote-context))
           (new-buffer (%completion-splice-with-quote-context
                        input start end text
                        :quote-context quote-context)))
      (values new-buffer
              (+ start
                 (if quote-context 1 0)
                 (length text))))))
