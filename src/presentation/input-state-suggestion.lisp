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

(defstruct (suggestion-acceptance
            (:constructor %make-suggestion-acceptance (accepted remaining))
            (:conc-name %suggestion-acceptance-))
  (accepted "" :type string :read-only t)
  (remaining "" :type string :read-only t))

(defun suggestion-acceptance-accepted (acceptance)
  (%suggestion-acceptance-accepted acceptance))

(defun suggestion-acceptance-remaining (acceptance)
  (%suggestion-acceptance-remaining acceptance))

(defstruct (suggestion-append-edit
            (:constructor %make-suggestion-append-edit (splice remaining))
            (:conc-name %suggestion-append-edit-))
  splice
  (remaining nil :type (or null string) :read-only t))

(defun suggestion-append-edit-for-state (state accepted remaining)
  (let* ((buffer (input-state-buffer state))
         (end (length buffer)))
    (%make-suggestion-append-edit
     (make-buffer-splice end end accepted)
     (unless (zerop (length remaining))
       remaining))))

(defun suggestion-append-edit-buffer (edit buffer)
  (buffer-splice-result (%suggestion-append-edit-splice edit) buffer))

(defun suggestion-append-edit-cursor-pos (edit)
  (buffer-splice-cursor-pos (%suggestion-append-edit-splice edit)))

(defun suggestion-append-edit-remaining (edit)
  (%suggestion-append-edit-remaining edit))

(defun commit-suggestion-append-edit (state edit)
  (copy-input-state-clearing-completion
   state
   :buffer (suggestion-append-edit-buffer edit (input-state-buffer state))
   :cursor-pos (suggestion-append-edit-cursor-pos edit)
   :suggestion (or (suggestion-append-edit-remaining edit) :clear)))

(defun %suggestion-next-word-end (suggestion)
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

(defun next-suggestion-acceptance (suggestion)
  (let* ((accept-end (%suggestion-next-word-end suggestion))
         (accepted (subseq suggestion 0 accept-end))
         (remaining (subseq suggestion accept-end)))
    (%make-suggestion-acceptance accepted remaining)))

(defun append-suggestion-to-input-state (state suggestion)
  (commit-suggestion-append-edit
   state
   (suggestion-append-edit-for-state state suggestion "")))

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
          (let* ((acceptance (next-suggestion-acceptance suggestion))
                 (edit (suggestion-append-edit-for-state
                        state
                        (suggestion-acceptance-accepted acceptance)
                        (suggestion-acceptance-remaining acceptance))))
            (values (commit-suggestion-append-edit state edit)
                    :suggest-update))
          (move-word-right state)))))
