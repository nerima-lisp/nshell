; Character dispatch handlers and main tokenize entry point.
(in-package #:nshell.domain.parsing)

(defun %tokenizer-handle-whitespace (state)
  (%tokenizer-state-advance state))

(defun %tokenizer-handle-newline (state)
  (%tokenizer-state-emit-token state :newline (string #\Newline)))

(defun %tokenizer-handle-ampersand (state)
  (let ((route (%tokenizer-ampersand-route-for state)))
    (%tokenizer-state-emit-token
     state
     (%tokenizer-ampersand-route-token-type route)
     (%tokenizer-ampersand-route-value route))))

(defun %tokenizer-read-fd-redirect (state)
  "Read a file-descriptor-prefixed redirect such as 2>, 2>>, 1>, or 2>&1."
  (let* ((start (tokenizer-state-pos state))
         (source-length (%tokenizer-fd-redirect-source-length state)))
    (%tokenizer-state-advance state source-length)
    (let ((op (%tokenizer-state-peek state)))
      (%tokenizer-state-advance state)
      (cond
        ((and (char= op #\>) (eql (%tokenizer-state-peek state) #\>))
         (%tokenizer-state-advance state))
        ((and (member op '(#\> #\<))
              (eql (%tokenizer-state-peek state) #\&))
         (%tokenizer-state-advance state)
         (loop while (and (%tokenizer-state-peek state)
                          (or (digit-char-p (%tokenizer-state-peek state))
                              (char= (%tokenizer-state-peek state) #\-)))
               do (%tokenizer-state-advance state)))
        ((and (char= op #\<)
              (eql (%tokenizer-state-peek state) #\<))
         (%tokenizer-state-advance state)
         (cond
           ((char= (%tokenizer-state-peek state) #\-)
            (%tokenizer-state-advance state))
           ((eql (%tokenizer-state-peek state) #\<)
            (%tokenizer-state-advance state))))
        (t
         nil)))
    (%tokenizer-state-push-token state :redirect
                                  (subseq (tokenizer-state-input state)
                                          start
                                          (tokenizer-state-pos state))
                                  start
                                  (tokenizer-state-pos state))))

(defun %tokenizer-handle-pipe (state)
  (let ((route (%tokenizer-pipe-route-for state)))
    (%tokenizer-state-emit-token
     state
     (%tokenizer-pipe-route-token-type route)
     (%tokenizer-pipe-route-value route))))

(defun %tokenizer-handle-right-angle (state)
  (let ((route (%tokenizer-right-angle-route-for state)))
    (case (%tokenizer-right-angle-route-kind route)
      (:process-substitution
       (%tokenizer-read-balanced-process-substitution state))
      (t
       (%tokenizer-state-emit-token
        state
        :redirect
        (%tokenizer-right-angle-route-value route))))))

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
    (#\> (%tokenizer-handle-right-angle state))
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
  (tokenize-into-state (%make-tokenizer-state-for-input input :cursor-pos cursor-pos)))
