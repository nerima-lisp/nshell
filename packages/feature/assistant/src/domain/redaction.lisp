(in-package #:nshell.feature.assistant)

(defparameter +assistant-redacted-token+ "[REDACTED]")

(defparameter +assistant-known-token-prefixes+
  '("sk-" "ghp_" "AKIA" "xox")
  "Known credential prefixes that require token-shaped redaction.")

(defun %assistant-token-char-p (character)
  (or (alphanumericp character)
      (char= character #\_)
      (char= character #\-)))

(defun %assistant-prefix-at-p (prefix text position)
  (and (<= (+ position (length prefix)) (length text))
       (string= prefix text
                :start2 position
                :end2 (+ position (length prefix)))))

(defun %assistant-redact-pem-blocks (text)
  (with-output-to-string (output)
    (loop with position = 0
          for begin = (search "-----BEGIN " text :start2 position)
          do (if (null begin)
                 (progn
                   (write-string (subseq text position) output)
                   (return))
                 (let* ((end-marker
                          (search "-----END " text
                                  :start2 (+ begin (length "-----BEGIN "))))
                        (end
                          (and end-marker
                               (search "-----" text
                                       :start2 (+ end-marker (length "-----END "))))))
                   (write-string (subseq text position begin) output)
                   (write-string +assistant-redacted-token+ output)
                   (setf position (if end (+ end (length "-----"))
                                      (length text))))))))

(defun %assistant-redact-token-stream (text)
  (with-output-to-string (output)
    (loop with position = 0
          while (< position (length text))
          do (cond
               ((%assistant-prefix-at-p "Bearer " text position)
                (let ((token-start (+ position (length "Bearer "))))
                  (if (and (< token-start (length text))
                           (%assistant-token-char-p (char text token-start)))
                      (let ((token-end token-start))
                        (loop while (and (< token-end (length text))
                                          (%assistant-token-char-p
                                           (char text token-end)))
                              do (incf token-end))
                        (write-string "Bearer " output)
                        (write-string +assistant-redacted-token+ output)
                        (setf position token-end))
                      (progn
                        (write-char (char text position) output)
                        (incf position)))))
               ((some (lambda (prefix)
                       (%assistant-prefix-at-p prefix text position))
                     +assistant-known-token-prefixes+)
                (let* ((prefix
                         (find-if (lambda (candidate)
                                    (%assistant-prefix-at-p candidate text position))
                                  +assistant-known-token-prefixes+))
                       (token-end (+ position (length prefix))))
                  (loop while (and (< token-end (length text))
                                    (%assistant-token-char-p (char text token-end)))
                        do (incf token-end))
                  (if (>= (- token-end (+ position (length prefix))) 20)
                      (progn
                        (write-string +assistant-redacted-token+ output)
                        (setf position token-end))
                      (progn
                        (write-char (char text position) output)
                        (incf position)))))
               ((%assistant-token-char-p (char text position))
                (let ((token-end position))
                  (loop while (and (< token-end (length text))
                                    (%assistant-token-char-p (char text token-end)))
                        do (incf token-end))
                  (if (>= (- token-end position) 20)
                      (progn
                        (write-string +assistant-redacted-token+ output)
                        (setf position token-end))
                      (progn
                        (write-string (subseq text position token-end) output)
                        (setf position token-end)))))
               (t
                (write-char (char text position) output)
                (incf position))))))

(defun redact-text (text)
  "Redact credential-shaped text without changing host or home paths."
  (if (stringp text)
      (%assistant-redact-token-stream (%assistant-redact-pem-blocks text))
      text))

(defun %assistant-whitespace-p (character)
  (member character '(#\Space #\Tab #\Newline #\Return) :test #'char=))

(defun %assistant-split-words (line)
  (loop with words = nil
        with start = nil
        for position from 0 below (length line)
        for character = (char line position)
        do (if (%assistant-whitespace-p character)
               (when start
                 (push (subseq line start position) words)
                 (setf start nil))
               (unless start (setf start position)))
        finally (when start
                  (push (subseq line start) words))
                (return (nreverse words))))

(defun %assistant-glob-match-p (pattern text)
  (labels ((match (pattern-position text-position)
             (cond
               ((= pattern-position (length pattern))
                (= text-position (length text)))
               ((char= (char pattern pattern-position) #\*)
                (or (match (1+ pattern-position) text-position)
                    (and (< text-position (length text))
                         (match pattern-position (1+ text-position)))))
               ((and (< text-position (length text))
                     (or (char= (char pattern pattern-position) #\?)
                         (char= (char pattern pattern-position)
                                (char text text-position))))
                (match (1+ pattern-position) (1+ text-position)))
               (t nil))))
    (match 0 0)))

(defun %assistant-denylisted-line-p (line denylist-paths denylist-commands)
  (let* ((words (%assistant-split-words line))
         (command (first words))
         (command-name (and command
                            (let ((slash (position #\/ command :from-end t)))
                              (if slash (subseq command (1+ slash)) command)))))
    (or (some (lambda (pattern)
                (or (%assistant-glob-match-p pattern line)
                    (some (lambda (word)
                            (%assistant-glob-match-p pattern word))
                          words)
                    (and (not (position #\* pattern))
                         (not (position #\? pattern))
                         (search pattern line))))
              denylist-paths)
        (and command-name
             (some (lambda (name) (string= name command-name))
                   denylist-commands)))))

(defun redact-lines (text &key denylist-paths denylist-commands)
  "Drop denylisted lines and redact token-shaped values in the remaining text."
  (if (stringp text)
      (let ((lines
              (with-input-from-string (input text)
                (loop for line = (read-line input nil nil)
                      while line
                      unless (%assistant-denylisted-line-p
                              line denylist-paths denylist-commands)
                        collect line))))
        (redact-text (format nil "~{~a~^~%~}" lines)))
      text))

(defun %assistant-environment-name (entry)
  (cond
    ((stringp entry)
     (let ((separator (position #\= entry)))
       (if separator (subseq entry 0 separator) entry)))
    ((consp entry)
     (%assistant-environment-name (first entry)))
    ((symbolp entry) (symbol-name entry))
    (t nil)))

(defun %assistant-environment-names (entries)
  (remove-duplicates
   (remove nil (mapcar #'%assistant-environment-name entries))
   :test #'string=))

(defun %assistant-environment-key-p (key)
  (let ((name (cond ((keywordp key) (symbol-name key))
                    ((stringp key) key)
                    (t ""))))
    (member (string-downcase name)
            '("environment" "env" "environment-entries")
            :test #'string=)))

(defun %assistant-plist-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (or (keywordp (first tail))
                        (and (stringp (first tail))
                             (second tail))))))

(defun %assistant-alist-p (value)
  (and (listp value)
       (every (lambda (entry)
                (and (consp entry)
                     (or (keywordp (car entry))
                         (stringp (car entry)))))
              value)))

(defun %assistant-redact-value (value key denylist-paths denylist-commands)
  (cond
    ((%assistant-environment-key-p key)
     (%assistant-environment-names value))
    ((stringp value)
     (redact-lines value
                   :denylist-paths denylist-paths
                   :denylist-commands denylist-commands))
    ((vectorp value)
     (map 'vector (lambda (item)
                    (%assistant-redact-value item key denylist-paths
                                             denylist-commands))
          value))
    ((%assistant-plist-p value)
     (loop for tail on value by #'cddr
           for item-key = (first tail)
           for item-value = (second tail)
           append (list item-key
                        (%assistant-redact-value item-value item-key
                                                 denylist-paths
                                                 denylist-commands))))
    ((%assistant-alist-p value)
     (mapcar (lambda (entry)
               (cons (car entry)
                     (%assistant-redact-value (cdr entry) (car entry)
                                              denylist-paths
                                              denylist-commands)))
             value))
    ((consp value)
     (mapcar (lambda (item)
               (%assistant-redact-value item key denylist-paths
                                        denylist-commands))
             value))
    (t value)))

(defun redact-payload (payload &key denylist-paths denylist-commands)
  "Redact a payload recursively, including environment values and denylisted lines."
  (%assistant-redact-value payload nil denylist-paths denylist-commands))
