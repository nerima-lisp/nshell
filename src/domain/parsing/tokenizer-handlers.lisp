; Character dispatch handlers and main tokenize entry point.
(in-package #:nshell.domain.parsing)

(defun %tokenizer-handle-whitespace (state)
  (%tokenizer-state-advance state))

(defun %tokenizer-handle-newline (state)
  (%tokenizer-state-emit-token state :newline (string #\Newline)))

(defun %tokenizer-horizontal-whitespace-p (ch)
  (or (char= ch #\Space)
      (char= ch #\Tab)))

(defun %tokenizer-fd-redirect-start-p (state ch)
  (and (digit-char-p ch)
       (member (%tokenizer-state-peek state 1) '(#\> #\<) :test #'eql)))

(defstruct (%fd-redirect-token-text
            (:constructor %make-fd-redirect-token-text (value advance-count)))
  (value "" :type string :read-only t)
  (advance-count 0 :type fixnum :read-only t))

(defun %fd-redirect-token-text (fd op next after-next)
  (let ((base (coerce (list fd op) 'string)))
    (cond
      ((and (char= op #\>)
            (eql next #\&)
            after-next
            (digit-char-p after-next))
       (%make-fd-redirect-token-text
        (concatenate 'string base "&" (string after-next))
        2))
      ((and (char= op #\>) (eql next #\>))
       (%make-fd-redirect-token-text
        (concatenate 'string base ">")
        1))
      (t
       (%make-fd-redirect-token-text base 0)))))

(defparameter +tokenizer-special-reader-dispatch-characters+
  '(#\( #\) #\# #\' #\")
  "Non-operator characters that route through tokenizer special handlers.")

(defstruct (%tokenizer-special-dispatch-route
            (:constructor %make-tokenizer-special-dispatch-route (character kind)))
  (character nil :read-only t)
  (kind nil :type (or null keyword) :read-only t))

(defun %tokenizer-special-reader-dispatch-character-p (ch)
  (%shell-separator-character-p ch +tokenizer-special-reader-dispatch-characters+))

(defun %tokenizer-special-dispatch-route (ch)
  (cond
    ((shell-operator-separator-p ch)
     (%make-tokenizer-special-dispatch-route ch :operator-separator))
    ((%tokenizer-special-reader-dispatch-character-p ch)
     (%make-tokenizer-special-dispatch-route ch :reader-boundary))))

(defun %tokenizer-special-dispatch-character-p (ch)
  (not (null (%tokenizer-special-dispatch-route ch))))

(defun %tokenizer-dispatch-kind (state ch)
  (cond ((char= ch #\Newline)
         :newline)
        ((%tokenizer-horizontal-whitespace-p ch)
         :whitespace)
        ((%tokenizer-fd-redirect-start-p state ch)
         :fd-redirect)
        ((%tokenizer-special-dispatch-character-p ch)
         :special)
        (t
         :word)))

(defstruct (%tokenizer-ampersand-route
            (:constructor %make-tokenizer-ampersand-route (token-type value)))
  (token-type :ampersand :type keyword :read-only t)
  (value "&" :type string :read-only t))

(defun %tokenizer-ampersand-route-for (state)
  (let ((next (%tokenizer-state-peek state 1)))
    (cond
      ((eql next #\&)
       (%make-tokenizer-ampersand-route :and "&&"))
      ((eql next #\>)
       (if (eql (%tokenizer-state-peek state 2) #\>)
           (%make-tokenizer-ampersand-route :redirect "&>>")
           (%make-tokenizer-ampersand-route :redirect "&>")))
      (t
       (%make-tokenizer-ampersand-route :ampersand "&")))))

(defun %tokenizer-handle-ampersand (state)
  (let ((route (%tokenizer-ampersand-route-for state)))
    (%tokenizer-state-emit-token
     state
     (%tokenizer-ampersand-route-token-type route)
     (%tokenizer-ampersand-route-value route))))

(defun %tokenizer-read-fd-redirect (state)
  "Read a file-descriptor-prefixed redirect such as 2>, 2>>, 1>, or 2>&1.
The current character is a single digit immediately followed by > or <."
  (let* ((start (tokenizer-state-pos state))
          (fd (%tokenizer-state-take state))
          (op (%tokenizer-state-take state))
          (text (%fd-redirect-token-text fd op
                                         (%tokenizer-state-peek state)
                                         (%tokenizer-state-peek state 1))))
    (%tokenizer-state-advance state
                              (%fd-redirect-token-text-advance-count text))
    (%tokenizer-state-push-token state :redirect
                                  (%fd-redirect-token-text-value text)
                                  start
                                  (tokenizer-state-pos state))))

(defstruct (%tokenizer-pipe-route
            (:constructor %make-tokenizer-pipe-route (token-type value)))
  (token-type :pipe :type keyword :read-only t)
  (value "|" :type string :read-only t))

(defun %tokenizer-pipe-route-for (state)
  (if (eql (%tokenizer-state-peek state 1) #\|)
      (%make-tokenizer-pipe-route :or "||")
      (%make-tokenizer-pipe-route :pipe "|")))

(defun %tokenizer-handle-pipe (state)
  (let ((route (%tokenizer-pipe-route-for state)))
    (%tokenizer-state-emit-token
     state
     (%tokenizer-pipe-route-token-type route)
     (%tokenizer-pipe-route-value route))))

(defstruct (%tokenizer-right-redirect-route
            (:constructor %make-tokenizer-right-redirect-route (value)))
  (value ">" :type string :read-only t))

(defun %tokenizer-right-redirect-route-for (state)
  (%make-tokenizer-right-redirect-route
   (if (eql (%tokenizer-state-peek state 1) #\>)
       ">>"
       ">")))

(defun %tokenizer-handle-redirect (state)
  (let ((route (%tokenizer-right-redirect-route-for state)))
    (%tokenizer-state-emit-token
     state
     :redirect
     (%tokenizer-right-redirect-route-value route))))

(defstruct (%tokenizer-left-angle-route
            (:constructor %make-tokenizer-left-angle-route (kind value)))
  (kind :redirect :type keyword :read-only t)
  (value "<" :type (or null string) :read-only t))

(defun %tokenizer-left-angle-route-for (state)
  (cond
    ((eql (%tokenizer-state-peek state 1) #\()
     (%make-tokenizer-left-angle-route :process-substitution nil))
    ((and (eql (%tokenizer-state-peek state 1) #\<)
          (eql (%tokenizer-state-peek state 2) #\<))
     (%make-tokenizer-left-angle-route :redirect "<<<"))
    ((eql (%tokenizer-state-peek state 1) #\<)
     (%make-tokenizer-left-angle-route :redirect "<<"))
    (t
     (%make-tokenizer-left-angle-route :redirect "<"))))

(defun %tokenizer-handle-left-angle (state)
  (let ((route (%tokenizer-left-angle-route-for state)))
    (case (%tokenizer-left-angle-route-kind route)
      (:process-substitution
       (%tokenizer-read-balanced-process-substitution state))
      (t
       (%tokenizer-state-emit-token
        state
        :redirect
        (%tokenizer-left-angle-route-value route))))))

(defstruct (%tokenizer-left-paren-route
            (:constructor %make-tokenizer-left-paren-route (kind end)))
  (kind :literal :type keyword :read-only t)
  (end nil :read-only t))

(defun %tokenizer-left-paren-route-for (state)
  (let ((next (%tokenizer-state-peek state 1)))
    (if (and next
             (char/= next #\)))
        (let ((end (%tokenizer-balanced-substitution-end
                    state
                    (tokenizer-state-pos state))))
          (if end
              (%make-tokenizer-left-paren-route :command-substitution end)
              (%make-tokenizer-left-paren-route :literal nil)))
        (%make-tokenizer-left-paren-route :literal nil))))

(defun %tokenizer-handle-left-paren (state)
  (case (%tokenizer-left-paren-route-kind
         (%tokenizer-left-paren-route-for state))
    (:command-substitution
     (%tokenizer-read-balanced-command-substitution state))
    (t
     (%tokenizer-state-emit-token state :lparen "("))))

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
             (case (%tokenizer-dispatch-kind state ch)
               (:newline
                (%tokenizer-handle-newline state))
               (:whitespace
                (%tokenizer-handle-whitespace state))
               (:fd-redirect
                (%tokenizer-read-fd-redirect state))
               (:special
                (%tokenizer-handle-special-character state ch))
               (:word
                (%tokenizer-read-word state)))))
  (let ((ordered-tokens (nreverse (tokenizer-state-tokens state))))
    (%make-tokenization-result
     ordered-tokens
     (%tokenizer-cursor-token state ordered-tokens)
     (tokenizer-state-incomplete state))))

(defun tokenize (input &key (cursor-pos nil))
  (tokenize-into-state (make-tokenizer-state input :cursor-pos cursor-pos)))
