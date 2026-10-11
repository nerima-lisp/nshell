(in-package #:nshell.feature.assistant)

(defparameter +assistant-redacted-token+ "[REDACTED]")

(defparameter +assistant-default-denylist-paths+
  '("~/.ssh/**" "*/.ssh/*" "~/.aws/**" "*/.aws/*"
    "~/.config/gh/**" "*/.config/gh/*" "~/.netrc" "*/.netrc"
    "~/.gnupg/**" "*/.gnupg/*" "*/*.pem" "*/*.key" "*/.env*" "*.env")
  "Built-in paths whose command and output lines must not reach the assistant.")

(defparameter +assistant-default-denylist-commands+
  ;; Denylisted commands can expose credentials and must be matched only at command boundaries.
  '("pass" "gpg" "ssh-add" "op" "aws configure" "gh auth token" "security")
  "Built-in commands whose command and output lines must not reach the assistant.")

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

(defun %assistant-bearer-prefix-at-p (text position)
  (and (<= (+ position (length "Bearer ")) (length text))
       (string-equal "Bearer " text
                     :start2 position
                     :end2 (+ position (length "Bearer ")))))

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
               ((%assistant-bearer-prefix-at-p text position)
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
                  (let ((suffix-length
                          (- token-end (+ position (length prefix)))))
                    (if (or (and (string= prefix "AKIA") (= suffix-length 16))
                            (and (not (string= prefix "AKIA"))
                                 (>= suffix-length 20)))
                      (progn
                        (write-string +assistant-redacted-token+ output)
                        (setf position token-end))
                      (progn
                        (write-char (char text position) output)
                        (incf position))))))
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

(defun %assistant-replace-all (text needle replacement)
  (if (or (null text) (null needle) (zerop (length needle)))
      text
      (with-output-to-string (output)
        (loop with start = 0
              for position = (search needle text :start2 start)
              do (if position
                     (progn
                       (write-string (subseq text start position) output)
                       (write-string replacement output)
                       (setf start (+ position (length needle))))
                     (progn
                       (write-string (subseq text start) output)
                       (return)))))))

(defun %assistant-redact-literal-values (text values)
  (reduce (lambda (result value)
            (if (and (stringp value) (plusp (length value)))
                (%assistant-replace-all result value +assistant-redacted-token+)
                result))
          values
          :initial-value text))

(defun redact-text (text &key denylist-values)
  "Redact credential-shaped text without changing host or home paths."
  (if (stringp text)
      (%assistant-redact-token-stream
       (%assistant-redact-pem-blocks
        (%assistant-redact-literal-values text denylist-values)))
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

(defun %assistant-command-token-separator-p (token)
  (keywordp token))

(defun %assistant-split-command-tokens (line)
  (let ((tokens nil)
        (substitutions nil)
        (word-end nil))
    (dolist (token (nshell.domain.parsing:tokenization-result-tokens
                    (nshell.domain.parsing:tokenize line)))
      (let ((type (nshell.domain.parsing:token-type token))
            (value (nshell.domain.parsing:token-value token)))
        (cond
          ((eq type :word)
           ;; The parser joins adjacent quoted and unquoted word fragments.
           (if (eql word-end (nshell.domain.parsing:token-start token))
               (setf (first tokens) (concatenate 'string (first tokens) value))
               (push value tokens))
           (setf word-end (nshell.domain.parsing:token-end token))
           (unless (eq (nshell.domain.parsing:token-quote-style token) :single)
             (dolist (marker '("$(" "<(" ">(" "("))
               (dolist (text (nshell.domain.parsing:parenthesized-substitution-texts
                              value marker))
                 ;; Partial command lines still need their denylisted bodies removed.
                 (let ((body (if (eq text :incomplete)
                                 (subseq value (+ (search marker value)
                                                  (length marker)))
                                 text)))
                   (push (cons :substitution
                               (%assistant-split-command-tokens body))
                         substitutions))))))
          ((member type '(:pipe :and :or :semicolon :newline :ampersand
                          :lparen :rparen))
           (push type tokens)
           (setf word-end nil))
          (t (setf word-end nil)))))
    (append (nreverse tokens)
            (loop for substitution in (nreverse substitutions)
                  append (append substitution (list :substitution))))))

(defun %assistant-command-token-name (token)
  (let ((slash (position #\/ token :from-end t)))
    (if slash (subseq token (1+ slash)) token)))

(defun %assistant-wrapper-name-p (token)
  (member (%assistant-command-token-name token)
          '("sudo" "env" "command" "exec" "nice" "nohup" "stdbuf")
          :test #'string=))

(defun %assistant-wrapper-option-takes-argument-p (wrapper option)
  (multiple-value-bind (short-options long-options)
      (cond
        ((string= wrapper "sudo")
         (values "ughpCDRrt" '("--user" "--group" "--host" "--prompt"
                               "--close-from" "--chdir" "--chroot" "--role" "--type")))
        ((string= wrapper "env")
         (values "uCS" '("--unset" "--chdir" "--split-string")))
        ((string= wrapper "nice") (values "n" '("--adjustment")))
        ((string= wrapper "stdbuf") (values "ioe" '("--input" "--output" "--error"))))
    (or (member option long-options :test #'string=)
        ;; An attached short-option value does not consume the following command.
        (and short-options (> (length option) 1)
             (char= (char option 0) #\-)
             (not (char= (char option 1) #\-))
             (let ((position (position-if (lambda (character)
                                            (find character short-options))
                                          option :start 1)))
               (and position (= position (1- (length option)))))))))

(defun %assistant-command-index-after-wrappers (tokens start)
  (loop with position = start
        while (< position (length tokens))
        for token = (nth position tokens)
        do (cond
             ((%assistant-command-token-separator-p token)
              (return nil))
             ((nshell.domain.parsing:shell-assignment-word-p token)
              (incf position))
             ((not (%assistant-wrapper-name-p token))
              (return position))
             (t
              (let ((wrapper (%assistant-command-token-name token)))
                (incf position)
                (loop while (< position (length tokens))
                      for option = (nth position tokens)
                      while (and (stringp option)
                                 (or (and (string= wrapper "env")
                                          (nshell.domain.parsing:shell-assignment-word-p option))
                                     (and (plusp (length option))
                                          (char= (char option 0) #\-))))
                      do (incf position)
                         (when (string= option "--") (return))
                         (when (%assistant-wrapper-option-takes-argument-p wrapper option)
                           (if (and (< position (length tokens))
                                    (stringp (nth position tokens)))
                               (incf position)
                               (return-from %assistant-command-index-after-wrappers nil)))))))))

(defun %assistant-command-pattern-match-p (pattern tokens position)
  (let ((pattern-tokens (%assistant-split-command-tokens pattern)))
    (and (plusp (length pattern-tokens))
         (stringp (first pattern-tokens))
         (<= (+ position (length pattern-tokens)) (length tokens))
         (string= (%assistant-command-token-name (first pattern-tokens))
                  (%assistant-command-token-name (nth position tokens)))
         (loop for offset from 1 below (length pattern-tokens)
               always (equal (nth offset pattern-tokens)
                             (nth (+ position offset) tokens))))))

(defun %assistant-denylisted-command-p (tokens denylist-commands)
  (loop for position = 0 then (1+ separator)
        for separator = (position-if #'%assistant-command-token-separator-p
                                    tokens :start position)
        for command-position = (%assistant-command-index-after-wrappers tokens position)
        thereis (and command-position
                      (some (lambda (pattern)
                              (%assistant-command-pattern-match-p
                               pattern tokens command-position))
                            denylist-commands))
        while separator))

(defun %assistant-denylisted-line-p (line denylist-paths denylist-commands)
  (let ((words (%assistant-split-words line))
        (command-tokens (%assistant-split-command-tokens line)))
    (or (some (lambda (pattern)
                (or (%assistant-glob-match-p pattern line)
                    (some (lambda (word)
                            (%assistant-glob-match-p pattern word))
                          words)
                    (and (not (position #\* pattern))
                         (not (position #\? pattern))
                         (search pattern line))))
              denylist-paths)
        (%assistant-denylisted-command-p command-tokens denylist-commands))))

(defun redact-lines
    (text &key (denylist-paths +assistant-default-denylist-paths+)
              (denylist-commands +assistant-default-denylist-commands+)
              denylist-values)
  "Drop denylisted lines and redact token-shaped values in the remaining text."
  (if (stringp text)
      (let ((lines
              (with-input-from-string (input text)
                (loop for line = (read-line input nil nil)
                      while line
                      unless (%assistant-denylisted-line-p
                              line denylist-paths denylist-commands)
                        collect line))))
        (redact-text (format nil "~{~a~^~%~}"
                             lines)
                     :denylist-values denylist-values))
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

(defun %assistant-redact-value
    (value key denylist-paths denylist-commands denylist-values)
  (cond
    ((%assistant-environment-key-p key)
     (%assistant-environment-names value))
    ((stringp value)
     (redact-lines value
                   :denylist-paths denylist-paths
                   :denylist-commands denylist-commands
                   :denylist-values denylist-values))
    ((vectorp value)
     (map 'vector (lambda (item)
                    (%assistant-redact-value item key denylist-paths
                                             denylist-commands
                                             denylist-values))
          value))
    ((%assistant-plist-p value)
     (loop for tail on value by #'cddr
           for item-key = (first tail)
           for item-value = (second tail)
           append (list item-key
                        (%assistant-redact-value item-value item-key
                                                 denylist-paths
                                                 denylist-commands
                                                 denylist-values))))
    ((%assistant-alist-p value)
     (mapcar (lambda (entry)
               (cons (car entry)
                     (%assistant-redact-value (cdr entry) (car entry)
                                              denylist-paths
                                              denylist-commands
                                              denylist-values)))
             value))
    ((consp value)
     (mapcar (lambda (item)
               (%assistant-redact-value item key denylist-paths
                                        denylist-commands
                                        denylist-values))
             value))
    (t value)))

(defun redact-payload
    (payload &key (denylist-paths +assistant-default-denylist-paths+)
                    (denylist-commands +assistant-default-denylist-commands+)
                    denylist-values)
  "Redact a payload recursively, including environment values and denylisted lines."
  (%assistant-redact-value payload nil denylist-paths denylist-commands
                          denylist-values))
