; Pure tokenizer dispatch and route classification.
(in-package #:nshell.domain.parsing)

(defun %tokenizer-horizontal-whitespace-p (ch)
  (or (char= ch #\Space) (char= ch #\Tab)))

(defun %tokenizer-fd-redirect-source-length (state)
  (loop with length = 0
        for ch = (%tokenizer-state-peek state length)
        while (and ch (digit-char-p ch))
        do (incf length)
        finally (return length)))

(defun %tokenizer-fd-redirect-start-p (state ch)
  (and (digit-char-p ch)
       (let ((source-length (%tokenizer-fd-redirect-source-length state)))
         (member (%tokenizer-state-peek state source-length)
                 '(#\> #\<)
                 :test #'eql))))

(defun %fd-redirect-token-text (fd op next after-next)
  (let ((base (coerce (list fd op) 'string)))
    (cond
      ((and (member op '(#\> #\<)) (eql next #\&) after-next
            (or (digit-char-p after-next) (char= after-next #\-)))
       (%make-fd-redirect-token-text
        (concatenate 'string base "&" (string after-next)) 2))
      ((and (char= op #\>) (eql next #\>))
       (%make-fd-redirect-token-text (concatenate 'string base ">") 1))
      (t (%make-fd-redirect-token-text base 0)))))

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
  (cond ((char= ch #\Newline) :newline)
        ((%tokenizer-horizontal-whitespace-p ch) :whitespace)
        ((%tokenizer-fd-redirect-start-p state ch) :fd-redirect)
        ((%tokenizer-special-dispatch-character-p ch) :special)
        (t :word)))

(defun %tokenizer-ampersand-route-for (state)
  (let ((next (%tokenizer-state-peek state 1)))
    (cond
      ((eql next #\&) (%make-tokenizer-ampersand-route :and "&&"))
      ((eql next #\>)
       (if (eql (%tokenizer-state-peek state 2) #\>)
           (%make-tokenizer-ampersand-route :redirect "&>>")
           (%make-tokenizer-ampersand-route :redirect "&>")))
      (t (%make-tokenizer-ampersand-route :ampersand "&")))))

(defun %tokenizer-pipe-route-for (state)
  (cond
    ((eql (%tokenizer-state-peek state 1) #\|)
     (%make-tokenizer-pipe-route :or "||"))
    ((eql (%tokenizer-state-peek state 1) #\&)
     (%make-tokenizer-pipe-route :pipe "|&"))
    (t (%make-tokenizer-pipe-route :pipe "|"))))

(defun %tokenizer-right-angle-route-for (state)
  (cond
    ((eql (%tokenizer-state-peek state 1) #\()
     (%make-tokenizer-right-angle-route :process-substitution nil))
    ((eql (%tokenizer-state-peek state 1) #\>)
     (%make-tokenizer-right-angle-route :redirect ">>"))
    (t (%make-tokenizer-right-angle-route :redirect ">"))))

(defun %tokenizer-left-angle-route-for (state)
  (cond
    ((eql (%tokenizer-state-peek state 1) #\()
     (%make-tokenizer-left-angle-route :process-substitution nil))
    ((and (eql (%tokenizer-state-peek state 1) #\<)
          (eql (%tokenizer-state-peek state 2) #\-))
     (%make-tokenizer-left-angle-route :redirect "<<-"))
    ((and (eql (%tokenizer-state-peek state 1) #\<)
          (eql (%tokenizer-state-peek state 2) #\<))
     (%make-tokenizer-left-angle-route :redirect "<<<"))
    ((eql (%tokenizer-state-peek state 1) #\<)
     (%make-tokenizer-left-angle-route :redirect "<<"))
    (t (%make-tokenizer-left-angle-route :redirect "<"))))

(defun %tokenizer-left-paren-route-for (state)
  (let ((next (%tokenizer-state-peek state 1)))
    (if (and next (char/= next #\)))
        (let ((end (%tokenizer-balanced-substitution-end
                    state (tokenizer-state-pos state))))
          (if end
              (%make-tokenizer-left-paren-route :command-substitution end)
              (%make-tokenizer-left-paren-route :literal nil)))
        (%make-tokenizer-left-paren-route :literal nil))))
