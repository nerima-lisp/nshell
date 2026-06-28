(in-package #:nshell.domain.parsing)

(defstruct (token (:constructor make-token (type value &optional (start 0) (end 0)
                                            (quote-style nil))))
  (type :word :type keyword :read-only t)
  (value "" :type string :read-only t)
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t)
  (quote-style nil :type symbol :read-only t))

;; token-type, token-value, token-start, token-end are auto-generated struct accessors

(defstruct (tokenizer-state (:constructor %make-tokenizer-state))
  input
  len
  cursor-pos
  (pos 0 :type integer)
  (tokens '() :type list)
  (incomplete nil :type boolean))

(defun shell-assignment-word-p (word)
  "Return true when WORD looks like a shell assignment word."
  (and (stringp word)
       (plusp (length word))
       (let ((equals-position (position #\= word)))
         (and equals-position
              (plusp equals-position)
              (loop for index below equals-position
                    for ch = (char word index)
                    always (if (zerop index)
                               (or (alpha-char-p ch) (char= ch #\_))
                                 (or (alphanumericp ch) (char= ch #\_))))))))

(defparameter +shell-word-separator-characters+
  '(#\Space #\Tab #\Newline)
  "Characters that separate shell words.")

(defparameter +shell-operator-separator-characters+
  '(#\| #\; #\& #\< #\>)
  "Characters that separate shell operators.")

(defparameter +shell-command-separator-token-types+
  '(:pipe :and :or :semicolon :newline :ampersand)
  "Token types that separate shell command segments.")

(defun shell-word-separator-p (ch)
  (member ch +shell-word-separator-characters+ :test #'char=))

(defun shell-operator-separator-p (ch)
  (member ch +shell-operator-separator-characters+ :test #'char=))

(defun shell-token-separator-p (ch)
  (or (shell-word-separator-p ch)
      (shell-operator-separator-p ch)))

(defun shell-command-separator-token-p (token)
  (member (token-type token) +shell-command-separator-token-types+ :test #'eq))

(defun %shell-input-separator-p (ch include-return-p)
  (or (member ch +shell-word-separator-characters+ :test #'char=)
      (member ch +shell-operator-separator-characters+ :test #'char=)
      (and include-return-p (char= ch #\Return))))

(defun shell-input-blank-p (input &key include-return-p)
  "Return true when INPUT contains only shell separators."
  (every (lambda (ch)
           (%shell-input-separator-p ch include-return-p))
         input))

(defun make-tokenizer-state (input &key cursor-pos)
  (%make-tokenizer-state :input input
                         :len (length input)
                         :cursor-pos (or cursor-pos (length input))))

(defun %tokenizer-state-peek (state &optional (offset 0))
  (let ((p (+ (tokenizer-state-pos state) offset)))
    (if (< p (tokenizer-state-len state))
        (char (tokenizer-state-input state) p)
        nil)))

(defun %tokenizer-state-advance (state &optional (n 1))
  (incf (tokenizer-state-pos state) n))

(defun %tokenizer-state-take (state)
  (let ((ch (%tokenizer-state-peek state)))
    (%tokenizer-state-advance state)
    ch))

(defun %tokenizer-state-push-token (state type value start end &optional quote-style)
  (push (make-token type value start end quote-style) (tokenizer-state-tokens state)))

(defun %tokenizer-state-emit-token (state type value &optional quote-style)
  (let ((start (tokenizer-state-pos state))
        (width (length value)))
    (%tokenizer-state-push-token state type value start (+ start width) quote-style)
    (%tokenizer-state-advance state width)))

(defun %balanced-substitution-end (input start)
  (let ((depth 0)
        (quote nil)
        (escaped nil))
    (loop for index from start below (length input)
          for ch = (char input index)
          do (cond
               (escaped
                (setf escaped nil))
               ((char= ch #\\)
                (setf escaped t))
               (quote
                (when (char= ch quote)
                  (setf quote nil)))
               ((or (char= ch #\') (char= ch #\"))
                (setf quote ch))
               ((char= ch #\()
                (incf depth))
               ((char= ch #\))
                (decf depth)
                (when (zerop depth)
                  (return index)))))))

(defun %tokenizer-balanced-substitution-end (state start)
  (%balanced-substitution-end (tokenizer-state-input state) start))

(defun %tokenizer-read-balanced-command-substitution (state)
  (let* ((start (tokenizer-state-pos state))
         (end (%tokenizer-balanced-substitution-end state start)))
    (%tokenizer-state-push-token state :word
                                 (subseq (tokenizer-state-input state) start (1+ end))
                                 start
                                 (1+ end))
    (setf (tokenizer-state-pos state) (1+ end))))

(defun %tokenizer-read-balanced-process-substitution (state)
  (let ((start (tokenizer-state-pos state))
        (chars '())
        (depth 0)
        (quote-delimiter nil)
        (escaped nil))
    (push (%tokenizer-state-take state) chars)
    (push (%tokenizer-state-take state) chars)
    (setf depth 1)
    (loop while (and (< (tokenizer-state-pos state) (tokenizer-state-len state))
                     (plusp depth))
          for ch = (%tokenizer-state-take state)
          do (progn
               (push ch chars)
               (cond
                 (escaped
                  (setf escaped nil))
                 ((char= ch #\\)
                  (setf escaped t))
                 (quote-delimiter
                  (when (char= ch quote-delimiter)
                    (setf quote-delimiter nil)))
                 ((or (char= ch #\') (char= ch #\"))
                  (setf quote-delimiter ch))
                 ((char= ch #\() (incf depth))
                 ((char= ch #\)) (decf depth)))))
    (let ((value (coerce (nreverse chars) 'string)))
      (if (plusp depth)
          (progn
            (setf (tokenizer-state-incomplete state) t)
            (%tokenizer-state-push-token state :error value start (tokenizer-state-pos state)))
          (%tokenizer-state-push-token state :word value start (tokenizer-state-pos state))))))

(defun %tokenizer-read-word (state)
  (let ((start (tokenizer-state-pos state))
        (chars '()))
    (loop while (< (tokenizer-state-pos state) (tokenizer-state-len state))
          for ch = (%tokenizer-state-peek state)
          do (cond
               ;; Keep $( ... ) and $(( ... )) attached to the surrounding word so
               ;; command substitution and arithmetic expansion can be applied
               ;; during expansion instead of the parens splitting the word.
               ((and (char= ch #\$)
                     (eql (%tokenizer-state-peek state 1) #\()
                     (%tokenizer-balanced-substitution-end
                      state (1+ (tokenizer-state-pos state))))
                (push (%tokenizer-state-take state) chars) ; the $
                (let ((depth 0) (quote nil) (escaped nil))
                  (loop for c = (%tokenizer-state-peek state)
                        while c
                        do (push (%tokenizer-state-take state) chars)
                           (cond (escaped (setf escaped nil))
                                 ((char= c #\\) (setf escaped t))
                                 (quote (when (char= c quote) (setf quote nil)))
                                 ((or (char= c #\') (char= c #\")) (setf quote c))
                                 ((char= c #\() (incf depth))
                                 ((char= c #\))
                                  (decf depth)
                                  (when (zerop depth) (return)))))))
               ;; Keep fish-style command substitution attached when it appears
               ;; inside a compound word such as prefix(cmd)suffix.
               ((and (char= ch #\()
                     (%tokenizer-state-peek state 1)
                     (char/= (%tokenizer-state-peek state 1) #\))
                     (%tokenizer-balanced-substitution-end
                      state (tokenizer-state-pos state)))
                (let ((depth 0) (quote nil) (escaped nil))
                  (loop for c = (%tokenizer-state-peek state)
                        while c
                        do (push (%tokenizer-state-take state) chars)
                           (cond (escaped (setf escaped nil))
                                 ((char= c #\\) (setf escaped t))
                                 (quote (when (char= c quote) (setf quote nil)))
                                 ((or (char= c #\') (char= c #\")) (setf quote c))
                                 ((char= c #\() (incf depth))
                                 ((char= c #\))
                                  (decf depth)
                                  (when (zerop depth) (return)))))))
               ((or (char= ch #\Space) (char= ch #\Tab)
                    (char= ch #\Newline)
                    (char= ch #\|) (char= ch #\>)
                    (char= ch #\<) (char= ch #\&)
                    (char= ch #\;) (char= ch #\()
                    (char= ch #\)) (char= ch #\')
                    (char= ch #\"))
                (return))
               ((char= ch #\\)
                (let ((escape-start (tokenizer-state-pos state)))
                  (%tokenizer-state-advance state)
                  (if (< (tokenizer-state-pos state) (tokenizer-state-len state))
                      (progn
                        (push (%tokenizer-state-peek state) chars)
                        (%tokenizer-state-advance state))
                      (progn
                        (setf (tokenizer-state-incomplete state) t)
                        (when chars
                          (%tokenizer-state-push-token state :word
                                                       (coerce (nreverse chars) 'string)
                                                       start
                                                       escape-start))
                        (%tokenizer-state-push-token state :error "\\" escape-start
                                                     (tokenizer-state-pos state))
                        (return)))))
               (t
                (push ch chars)
                (%tokenizer-state-advance state))))
    (when chars
      (%tokenizer-state-push-token state :word
                                   (coerce (nreverse chars) 'string)
                                   start
                                   (tokenizer-state-pos state)))))

(defun %tokenizer-double-quoted-escape-character-p (ch)
  (or (char= ch #\\)
      (char= ch #\")
      (char= ch #\$)
      (char= ch #\`)
      (char= ch #\Newline)))

(defun %tokenizer-read-delimited (state delimiter &key escape-p quote-style)
  (let ((start (tokenizer-state-pos state))
        (chars '()))
    (%tokenizer-state-advance state)
    (loop while (< (tokenizer-state-pos state) (tokenizer-state-len state))
          for ch = (%tokenizer-state-peek state)
          do (cond
               ((char= ch delimiter)
                (return))
               ((and escape-p (char= ch #\\))
                (%tokenizer-state-advance state)
                (if (< (tokenizer-state-pos state) (tokenizer-state-len state))
                    (let ((escaped (%tokenizer-state-peek state)))
                      (unless (%tokenizer-double-quoted-escape-character-p escaped)
                        (push #\\ chars))
                      (push escaped chars)
                      (%tokenizer-state-advance state))
                    (push #\\ chars)))
               (t
                (push ch chars)
                (%tokenizer-state-advance state))))
    (if (and (< (tokenizer-state-pos state) (tokenizer-state-len state))
             (char= (%tokenizer-state-peek state) delimiter))
        (progn
          (%tokenizer-state-advance state)
          (%tokenizer-state-push-token state :word (coerce (nreverse chars) 'string)
                                       start (tokenizer-state-pos state)
                                       quote-style))
        (progn
          (setf (tokenizer-state-incomplete state) t)
          (%tokenizer-state-push-token state :error (coerce (nreverse chars) 'string) start (tokenizer-state-pos state))))))

(defun %tokenizer-read-single-quoted (state)
  (%tokenizer-read-delimited state #\' :quote-style :single))

(defun %tokenizer-read-double-quoted (state)
  ;; Double quotes suppress globbing and word-splitting but still permit
  ;; variable/command expansion, so the :DOUBLE quote-style drives glob
  ;; suppression during expansion.
  (%tokenizer-read-delimited state #\" :escape-p t :quote-style :double))

(defun %tokenizer-read-comment (state)
  (loop while (< (tokenizer-state-pos state) (tokenizer-state-len state))
        for ch = (%tokenizer-state-peek state)
        until (char= ch #\Newline)
        do (%tokenizer-state-advance state)))

(defun %tokenizer-handle-whitespace (state)
  (%tokenizer-state-advance state))

(defun %tokenizer-handle-newline (state)
  (%tokenizer-state-emit-token state :newline (string #\Newline)))

(defun %tokenizer-handle-ampersand (state)
  (let ((next (%tokenizer-state-peek state 1)))
    (cond
      ((eql next #\&) (%tokenizer-state-emit-token state :and "&&"))
      ;; &> and &>> redirect both stdout and stderr to a file.
      ((eql next #\>)
       (if (eql (%tokenizer-state-peek state 2) #\>)
           (%tokenizer-state-emit-token state :redirect "&>>")
           (%tokenizer-state-emit-token state :redirect "&>")))
      (t (%tokenizer-state-emit-token state :ampersand "&")))))

(defun %tokenizer-read-fd-redirect (state)
  "Read a file-descriptor-prefixed redirect such as 2>, 2>>, 1>, or 2>&1.
The current character is a single digit immediately followed by > or <."
  (let* ((start (tokenizer-state-pos state))
         (fd (%tokenizer-state-take state))
         (op (%tokenizer-state-take state))
         (value (coerce (list fd op) 'string)))
    (cond
      ;; N>&M : duplicate one descriptor onto another (e.g. 2>&1).
      ((and (char= op #\>)
            (eql (%tokenizer-state-peek state) #\&)
            (let ((d (%tokenizer-state-peek state 1)))
              (and d (digit-char-p d))))
       (setf value (concatenate 'string value "&"
                                (string (%tokenizer-state-peek state 1))))
       (%tokenizer-state-advance state 2))
      ;; N>> : append.
      ((and (char= op #\>) (eql (%tokenizer-state-peek state) #\>))
       (setf value (concatenate 'string value ">"))
       (%tokenizer-state-advance state)))
    (%tokenizer-state-push-token state :redirect value start
                                 (tokenizer-state-pos state))))

(defun %tokenizer-handle-pipe (state)
  (if (and (%tokenizer-state-peek state 1)
           (char= (%tokenizer-state-peek state 1) #\|))
      (%tokenizer-state-emit-token state :or "||")
      (%tokenizer-state-emit-token state :pipe "|")))

(defun %tokenizer-handle-redirect (state)
  (if (and (%tokenizer-state-peek state 1)
           (char= (%tokenizer-state-peek state 1) #\>))
      (%tokenizer-state-emit-token state :redirect ">>")
      (%tokenizer-state-emit-token state :redirect ">")))

(defun %tokenizer-handle-left-angle (state)
  (cond
    ((and (%tokenizer-state-peek state 1)
          (char= (%tokenizer-state-peek state 1) #\())
     (%tokenizer-read-balanced-process-substitution state))
    ((and (%tokenizer-state-peek state 1)
          (%tokenizer-state-peek state 2)
          (char= (%tokenizer-state-peek state 1) #\<)
          (char= (%tokenizer-state-peek state 2) #\<))
     (%tokenizer-state-emit-token state :redirect "<<<"))
    ((and (%tokenizer-state-peek state 1)
          (char= (%tokenizer-state-peek state 1) #\<))
     (%tokenizer-state-emit-token state :redirect "<<"))
    (t
     (%tokenizer-state-emit-token state :redirect "<"))))

(defun %tokenizer-handle-left-paren (state)
  (if (and (%tokenizer-state-peek state 1)
           (char/= (%tokenizer-state-peek state 1) #\))
           (%tokenizer-balanced-substitution-end state (tokenizer-state-pos state)))
      (%tokenizer-read-balanced-command-substitution state)
      (%tokenizer-state-emit-token state :lparen "(")))

(defun %tokenizer-handle-right-paren (state)
  (%tokenizer-state-emit-token state :rparen ")"))

(defun %tokenizer-handle-comment (state)
  (%tokenizer-read-comment state))

(defun %tokenizer-handle-single-quote (state)
  (%tokenizer-read-single-quoted state))

(defun %tokenizer-handle-double-quote (state)
  (%tokenizer-read-double-quoted state))

(defun %tokenizer-handle-special-character (state ch)
  (case ch
    (#\& (%tokenizer-handle-ampersand state))
    (#\| (%tokenizer-handle-pipe state))
    (#\> (%tokenizer-handle-redirect state))
    (#\< (%tokenizer-handle-left-angle state))
    (#\; (%tokenizer-state-emit-token state :semicolon ";"))
    (#\( (%tokenizer-handle-left-paren state))
    (#\) (%tokenizer-handle-right-paren state))
    (#\# (%tokenizer-handle-comment state))
    (#\' (%tokenizer-handle-single-quote state))
    (#\" (%tokenizer-handle-double-quote state))
    (t nil)))

(defun %tokenizer-cursor-token (state ordered-tokens)
  (find-if (lambda (tok)
             (and (>= (or (tokenizer-state-cursor-pos state)
                          (tokenizer-state-len state))
                      (token-start tok))
                  (< (or (tokenizer-state-cursor-pos state)
                         (tokenizer-state-len state))
                     (token-end tok))))
           ordered-tokens))

(defun tokenize-into-state (state)
  (loop while (< (tokenizer-state-pos state) (tokenizer-state-len state))
        do (let ((ch (%tokenizer-state-peek state)))
             (cond ((char= ch #\Newline)
                    (%tokenizer-handle-newline state))
                   ((or (char= ch #\Space) (char= ch #\Tab))
                    (%tokenizer-handle-whitespace state))
                   ((char= ch #\#)
                    (%tokenizer-handle-comment state))
                   ((char= ch #\()
                    (%tokenizer-handle-special-character state ch))
                   ((char= ch #\))
                    (%tokenizer-handle-special-character state ch))
                   ((char= ch #\')
                    (%tokenizer-handle-single-quote state))
                   ((char= ch #\")
                    (%tokenizer-handle-double-quote state))
                   ;; A digit glued directly to > or < is an fd redirect
                   ;; (2>file, 1>>log, 2>&1) rather than an argument word.
                   ((and (digit-char-p ch)
                         (member (%tokenizer-state-peek state 1) '(#\> #\<)
                                 :test #'eql))
                    (%tokenizer-read-fd-redirect state))
                   ((shell-operator-separator-p ch)
                    (%tokenizer-handle-special-character state ch))
                   (t (%tokenizer-read-word state)))))
  (let ((ordered-tokens (nreverse (tokenizer-state-tokens state))))
    (values ordered-tokens
            (%tokenizer-cursor-token state ordered-tokens)
            (tokenizer-state-incomplete state))))

(defun tokenize (input &key (cursor-pos nil))
  (tokenize-into-state (make-tokenizer-state input :cursor-pos cursor-pos)))
