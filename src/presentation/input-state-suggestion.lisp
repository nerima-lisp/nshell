;;; Autosuggestion acceptance helpers for the input reducer.

(in-package #:nshell.presentation)


(defun suggestion-word-like-token-p (token)
  (not (null (member (nshell.domain.parsing:token-type token)
                     '(:word :error)
                     :test #'eq))))

(defun suggestion-first-token-at-or-after (tokens position)
  (find-if (lambda (token)
             (>= (nshell.domain.parsing:token-start token) position))
           tokens))

(defun suggestion-token-accept-end (tokens first-token)
  (let ((accept-end (nshell.domain.parsing:token-end first-token)))
    (when (suggestion-word-like-token-p first-token)
      (dolist (token (rest (member first-token tokens)))
        (if (and (suggestion-word-like-token-p token)
                 (= (nshell.domain.parsing:token-start token) accept-end))
            (setf accept-end (nshell.domain.parsing:token-end token))
            (return))))
    accept-end))

(defun suggestion-redirection-operator-end (suggestion position)
  (let ((end (length suggestion)))
    (when (< position end)
      (let ((ch (char suggestion position)))
        (cond
          ((and (char= ch #\&)
                (< (1+ position) end)
                (char= (char suggestion (1+ position)) #\>))
           (+ position 2))
          ((or (char= ch #\<) (char= ch #\>))
           (if (and (char= ch #\>)
                    (< (1+ position) end)
                    (char= (char suggestion (1+ position)) #\>))
               (+ position 2)
               (1+ position))))))))

(defun suggestion-compact-redirection-end (suggestion position)
  "Return the end of a compact redirection starting at POSITION, or NIL.

This keeps autosuggestion word acceptance from splitting shell forms such as
\"2>&1\" and \">out.txt\" into lexer-sized pieces."
  (let* ((end (length suggestion))
         (operator-position position))
    (loop while (and (< operator-position end)
                     (digit-char-p (char suggestion operator-position)))
          do (incf operator-position))
    (when (or (= operator-position position)
              (and (< operator-position end)
                   (member (char suggestion operator-position)
                           '(#\< #\>)
                           :test #'char=)))
      (let ((operator-end
              (suggestion-redirection-operator-end suggestion operator-position)))
        (when operator-end
          (cond
            ((and (< operator-end end)
                  (char= (char suggestion operator-end) #\&))
             (let ((target-position (1+ operator-end)))
               (if (and (< target-position end)
                        (or (digit-char-p (char suggestion target-position))
                            (char= (char suggestion target-position) #\-)))
                   (let ((target-end (1+ target-position)))
                     (loop while (and (< target-end end)
                                      (digit-char-p
                                       (char suggestion target-end)))
                           do (incf target-end))
                     target-end)
                   operator-end)))
            ((and (< operator-end end)
                  (not (nshell.domain.parsing:shell-token-separator-p
                        (char suggestion operator-end))))
             (shell-token-end suggestion operator-end))
            (t operator-end)))))))

(defun suggestion-next-word-end (suggestion)
  "Return the end index of the next shell token or operator in SUGGESTION.

Leading shell word separators are accepted with the following token, matching
fish-style autosuggestion word acceptance for tails such as \" status --short\"."
  (let ((pos 0)
        (end (length suggestion)))
    (loop while (and (< pos end)
                     (nshell.domain.parsing:shell-word-separator-p
                      (char suggestion pos)))
          do (incf pos))
    (if (= pos end)
        end
        (or (suggestion-compact-redirection-end suggestion pos)
            (handler-case
                (let* ((tokenization
                         (nshell.domain.parsing:tokenize suggestion))
                       (tokens
                         (nshell.domain.parsing:tokenization-result-tokens
                          tokenization))
                       (first-token
                         (suggestion-first-token-at-or-after tokens pos)))
                  (if first-token
                      (suggestion-token-accept-end tokens first-token)
                      end))
              (error ()
                (shell-token-end suggestion pos)))))))

(defun append-suggestion-to-input-state (state suggestion)
  (let* ((buffer (input-state-buffer state))
         (new-buffer (concatenate 'string buffer suggestion))
         (new-cursor (length new-buffer)))
    (copy-input-state-clearing-completion state
                                          :buffer new-buffer
                                          :cursor-pos new-cursor)))

(defun accept-suggestion-at-eol (state)
  (with-normalized-input-state (state state)
    (let ((suggestion (input-state-suggestion state)))
      (if (and suggestion (input-state-at-eol-p state))
          (values (append-suggestion-to-input-state state suggestion)
                  :suggest-update)
          (move-cursor-clearing-suggestion state 1)))))

(defun accept-suggestion-word-at-eol (state)
  (with-normalized-input-state (state state)
    (let ((suggestion (input-state-suggestion state)))
      (if (and suggestion (input-state-at-eol-p state))
          (let* ((accept-end (suggestion-next-word-end suggestion))
                 (accepted (subseq suggestion 0 accept-end))
                 (remaining (subseq suggestion accept-end))
                 (new-state (append-suggestion-to-input-state state accepted)))
            (values (if (zerop (length remaining))
                        (copy-input-state-with new-state
                                               :suggestion :clear)
                        (copy-input-state-with new-state
                                               :suggestion remaining))
                    :suggest-update))
          (move-word-right state)))))
