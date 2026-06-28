; Low-level character readers for words, quotes, balanced substitutions.
(in-package #:nshell.domain.parsing)

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
