(in-package #:nshell.domain.history)

(defstruct (command-history (:constructor %make-command-history (&key (max-entries 10000))))
  "In-memory command history plus transient navigation state."
  (entries nil :type list)
  (max-entries 10000 :type integer :read-only t)
  (navigate-index -1 :type integer)
  (navigate-prefix nil :type (or null string))
  (navigate-origin nil :type (or null string)))

(defun make-command-history (&key (max-entries 10000))
  (%make-command-history :max-entries max-entries))

(defun history-capacity (history)
  "Return the maximum number of entries retained by HISTORY."
  (command-history-max-entries history))

(defstruct (history-word (:constructor %make-history-word (start end)))
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t))

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

(defun %history-clear-navigation (history)
  "Clear transient navigation state."
  (setf (command-history-navigate-index history) -1
        (command-history-navigate-prefix history) nil
        (command-history-navigate-origin history) nil)
  history)

(declaim (ftype (function (t integer) (or null string))
                history-last-argument-at))

(defun command-line-last-argument (line)
  "Return the source text of the last argument in LINE, or NIL.

Command words and redirection targets are not considered arguments. For
pipelines and command lists, the result is scoped to the final command segment."
  (when (and (stringp line) (plusp (length line)))
    (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                   (nshell.domain.parsing:tokenize line))))
      (loop with last-argument = nil
            with skip-redirect-target = nil
            with seen-command-word = nil
            with logical-words = (%history-logical-words tokens)
            for remaining on tokens
            for token = (first remaining)
            for next-token = (second remaining)
            do (cond
                 ((and skip-redirect-target
                       (eq (nshell.domain.parsing:token-type token) :ampersand))
                  nil)
                 ((nshell.domain.parsing:shell-command-separator-token-p token)
                  (setf last-argument nil
                        skip-redirect-target nil
                        seen-command-word nil))
                 ((%history-redirect-token-p token)
                  (setf skip-redirect-target t))
                 ((%history-word-token-p token)
                  (let ((word (first logical-words)))
                    (when (and word
                               (= (nshell.domain.parsing:token-start token)
                                  (history-word-start word)))
                      (pop logical-words)
                      (cond
                        ((%history-fd-redirection-designator-p token next-token)
                         nil)
                        (skip-redirect-target
                         (setf skip-redirect-target nil))
                        ((and (not seen-command-word)
                              (nshell.domain.parsing:shell-assignment-word-p
                               (%history-word-source line word)))
                         nil)
                        ((not seen-command-word)
                         (setf seen-command-word t))
                        (t
                         (setf last-argument (%history-word-source line word))))))))
            finally (return last-argument)))))

(defun history-last-argument-at (history index)
  "Return INDEX-th most recent insertable last argument in HISTORY, or NIL."
  (when (and (integerp index) (not (minusp index)))
    (loop for entry in (command-history-entries history)
          for argument = (command-line-last-argument (entry-text entry))
          when argument
            if (zerop index)
              return argument
            else
              do (decf index))))
