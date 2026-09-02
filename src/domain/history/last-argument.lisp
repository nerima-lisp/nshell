;;; The `!$`/Alt-. last-argument feature: extracting the final insertable
;;; argument from a recorded history line. This is shell-specific (it walks
;;; the tokenizer's AST to skip command words, redirect targets, and leading
;;; assignments), unlike generic recall/search/navigation, which are the
;;; responsibility of the history-kit library.
(in-package #:nshell.domain.history)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (define-value-struct history-word
      ((start 0 :type (integer 0 *))
       (end 0 :type (integer 0 *)))
    :constructor %allocate-history-word
    :predicate nil))

(defun %make-history-word (start end)
  (check-type start (integer 0 *))
  (check-type end (integer 0 *))
  (assert (<= start end) (start end)
          "History word start must not exceed end.")
  (%allocate-history-word start end))

(define-value-struct %history-token-window
    ((current nil)
     (next nil))
  :constructor %make-history-token-window
  :predicate nil)

(define-value-struct %history-logical-word-cursor
    ((remaining nil :type list :copy :list))
  :constructor %make-history-logical-word-cursor
  :predicate nil)

(define-value-struct %history-last-argument-scan-state
    ((last-argument nil :type (or null string))
     (skip-redirect-target nil :type boolean)
     (seen-command-word nil :type boolean)
     (logical-word-cursor nil :type %history-logical-word-cursor))
  :constructor %make-history-last-argument-scan-state
  :predicate nil)

(defun %history-token-window-from-remaining (remaining)
  (%make-history-token-window (first remaining) (second remaining)))

(defun %history-word-token-p (token)
  (not (null (member (nshell.domain.parsing:token-type token) '(:word :error) :test #'eq))))

(defun %history-redirect-token-p (token)
  (eq (nshell.domain.parsing:token-type token) :redirect))

(defun %history-fd-redirection-designator-p (token next-token)
  (and token next-token
       (%history-word-token-p token)
       (%history-redirect-token-p next-token)
       (= (nshell.domain.parsing:token-end token)
          (nshell.domain.parsing:token-start next-token))
       (every #'digit-char-p (nshell.domain.parsing:token-value token))))

(defun %history-logical-words-flush-current (words current)
  (if current
      (values (cons current words) nil)
      (values words nil)))

(defun %history-logical-words (tokens)
  "Coalesce adjacent parser word tokens into shell words.

The tokenizer already normalizes escaped-space words into a single token, but
quoted fragments can still arrive as adjacent word-like tokens. History
expansion wants the source span of the logical shell word, so adjacent
word-like tokens are merged before command/argument classification."
  (let ((words nil)
        (current nil))
    (dolist (token tokens)
      (if (%history-word-token-p token)
          (let ((start (nshell.domain.parsing:token-start token))
                (end (nshell.domain.parsing:token-end token)))
            (if (and current (= start (history-word-end current)))
                (setf current (%make-history-word (history-word-start current) end))
                (progn
                  (multiple-value-setq (words current)
                    (%history-logical-words-flush-current words current))
                  (setf current (%make-history-word start end)))))
          (multiple-value-setq (words current)
            (%history-logical-words-flush-current words current))))
    (multiple-value-setq (words current)
      (%history-logical-words-flush-current words current))
    (nreverse words)))

(defun %history-word-source (line word)
  (subseq line (history-word-start word) (history-word-end word)))

(defun %history-logical-word-cursor-current (cursor)
  (first (%history-logical-word-cursor-remaining cursor)))

(defun %history-logical-word-cursor-consume-current (cursor)
  (%make-history-logical-word-cursor
   (rest (%history-logical-word-cursor-remaining cursor))))

(defun %history-logical-word-cursor-consume-matching-token (cursor token)
  (let ((word (%history-logical-word-cursor-current cursor)))
    (when (and word
               (= (nshell.domain.parsing:token-start token)
                  (history-word-start word)))
      (values word (%history-logical-word-cursor-consume-current cursor)))))

(defun %history-last-argument-reset-for-separator (state)
  (%make-history-last-argument-scan-state
   nil nil nil
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-note-command-word (state)
  (%make-history-last-argument-scan-state
   (%history-last-argument-scan-state-last-argument state)
   (%history-last-argument-scan-state-skip-redirect-target state)
   t
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-note-argument (state argument)
  (%make-history-last-argument-scan-state
   argument
   (%history-last-argument-scan-state-skip-redirect-target state)
   (%history-last-argument-scan-state-seen-command-word state)
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-clear-redirect-target (state)
  (%make-history-last-argument-scan-state
   (%history-last-argument-scan-state-last-argument state)
   nil
   (%history-last-argument-scan-state-seen-command-word state)
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-handle-word (state line token token-window)
  (multiple-value-bind (word cursor)
      (%history-logical-word-cursor-consume-matching-token
       (%history-last-argument-scan-state-logical-word-cursor state)
       token)
    (if (null word)
        state
        (let ((state
                (%make-history-last-argument-scan-state
                 (%history-last-argument-scan-state-last-argument state)
                 (%history-last-argument-scan-state-skip-redirect-target state)
                 (%history-last-argument-scan-state-seen-command-word state)
                 cursor)))
          (cond
            ((%history-fd-redirection-designator-p
              token
              (%history-token-window-next token-window))
             state)
            ((%history-last-argument-scan-state-skip-redirect-target state)
             (%history-last-argument-clear-redirect-target state))
            ((and (not (%history-last-argument-scan-state-seen-command-word state))
                  (nshell.domain.parsing:shell-assignment-word-p
                   (%history-word-source line word)))
             state)
            ((not (%history-last-argument-scan-state-seen-command-word state))
             (%history-last-argument-note-command-word state))
            (t
             (%history-last-argument-note-argument
              state
              (%history-word-source line word))))))))

(defun %history-last-argument-handle-token (state line token token-window)
  (cond
    ((and (%history-last-argument-scan-state-skip-redirect-target state)
          (eq (nshell.domain.parsing:token-type token) :ampersand))
     state)
    ((nshell.domain.parsing:shell-command-separator-token-p token)
     (%history-last-argument-reset-for-separator state))
    ((%history-redirect-token-p token)
     (%make-history-last-argument-scan-state
      (%history-last-argument-scan-state-last-argument state)
      t
      (%history-last-argument-scan-state-seen-command-word state)
      (%history-last-argument-scan-state-logical-word-cursor state)))
    ((%history-word-token-p token)
     (%history-last-argument-handle-word state line token token-window))
    (t
     state)))

(declaim (ftype (function (t integer) (or null string))
                history-last-argument-at))

(defun command-line-last-argument (line)
  "Return the source text of the last argument in LINE, or NIL.

Command words and redirection targets are not considered arguments. For
pipelines and command lists, the result is scoped to the final command segment."
  (when (and (stringp line) (plusp (length line)))
    (let* ((tokens (nshell.domain.parsing:tokenization-result-tokens
                    (nshell.domain.parsing:tokenize line)))
           (state (%make-history-last-argument-scan-state
                   nil nil nil
                   (%make-history-logical-word-cursor
                    (%history-logical-words tokens)))))
      (do ((remaining tokens (rest remaining)))
          ((endp remaining)
           (%history-last-argument-scan-state-last-argument state))
        (let* ((token-window (%history-token-window-from-remaining remaining))
               (token (%history-token-window-current token-window)))
          (setf state
                (%history-last-argument-handle-token
                 state line token token-window)))))))

(defun history-last-argument-at (history index)
  "Return INDEX-th most recent insertable last argument in HISTORY, or NIL."
  (when (and (integerp index) (not (minusp index)))
    (do ((entries (history-kit:history-entries history) (rest entries)))
        ((endp entries) nil)
      (let ((argument (command-line-last-argument
                        (history-kit:history-entry-text (first entries)))))
        (when argument
          (if (zerop index)
              (return argument)
              (decf index)))))))
