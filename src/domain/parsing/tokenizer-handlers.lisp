; Character dispatch handlers and main tokenize entry point.
(in-package #:nshell.domain.parsing)

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
