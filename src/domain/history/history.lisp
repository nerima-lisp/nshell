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

(defstruct (%history-token-window
            (:constructor %make-history-token-window (current next)))
  (current nil :read-only t)
  (next nil :read-only t))

(defstruct (%history-logical-word-cursor
            (:constructor %make-history-logical-word-cursor (remaining)))
  (remaining nil :type list))

(defstruct (%history-last-argument-scan-state
            (:constructor %make-history-last-argument-scan-state (logical-word-cursor)))
  (last-argument nil :type (or null string))
  (skip-redirect-target nil :type boolean)
  (seen-command-word nil :type boolean)
  (logical-word-cursor nil :type %history-logical-word-cursor :read-only t))

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
  (setf (%history-logical-word-cursor-remaining cursor)
        (rest (%history-logical-word-cursor-remaining cursor))))

(defun %history-logical-word-cursor-consume-matching-token (cursor token)
  (let ((word (%history-logical-word-cursor-current cursor)))
    (when (and word
               (= (nshell.domain.parsing:token-start token)
                  (history-word-start word)))
      (%history-logical-word-cursor-consume-current cursor)
      word)))

(defun %history-clear-navigation (history)
  "Clear transient navigation state."
  (setf (command-history-navigate-index history) -1
        (command-history-navigate-prefix history) nil
        (command-history-navigate-origin history) nil)
  history)

(defun %history-text-case-sensitive-p (text)
  (some #'upper-case-p text))

(defun %history-text-prefix-p (text prefix &key case-sensitive)
  (let ((prefix-length (length prefix)))
    (and (<= prefix-length (length text))
         (if case-sensitive
             (string= text prefix :end1 prefix-length)
             (string-equal text prefix :end1 prefix-length)))))

(defun %history-text-equal-p (text query &key case-sensitive)
  (if case-sensitive
      (string= text query)
      (string-equal text query)))

(defun %history-text-contains-p (text query &key case-sensitive)
  (if case-sensitive
      (search query text)
      (search query text :test #'char-equal)))

(defun %history-line-prefix-p (text query &key case-sensitive)
  (let ((query-length (length query)))
    (loop with line-start = 0
          for newline = (position #\Newline text :start line-start)
          for line-end = (or newline (length text))
          thereis (and (<= (+ line-start query-length) line-end)
                       (if case-sensitive
                           (string= text query
                                    :start1 line-start
                                    :end1 (+ line-start query-length))
                           (string-equal text query
                                         :start1 line-start
                                         :end1 (+ line-start query-length))))
          while newline
          do (setf line-start (1+ newline)))))

(defun %history-last-argument-reset-for-separator (state)
  (setf (%history-last-argument-scan-state-last-argument state) nil
        (%history-last-argument-scan-state-skip-redirect-target state) nil
        (%history-last-argument-scan-state-seen-command-word state) nil)
  state)

(defun %history-last-argument-note-command-word (state)
  (setf (%history-last-argument-scan-state-seen-command-word state) t)
  state)

(defun %history-last-argument-note-argument (state argument)
  (setf (%history-last-argument-scan-state-last-argument state) argument)
  state)

(defun %history-last-argument-clear-redirect-target (state)
  (setf (%history-last-argument-scan-state-skip-redirect-target state) nil)
  state)

(defun %history-last-argument-handle-word (state line token token-window)
  (let ((word (%history-logical-word-cursor-consume-matching-token
               (%history-last-argument-scan-state-logical-word-cursor state)
               token)))
    (when word
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
          (%history-word-source line word)))))))

(defun %history-last-argument-handle-token (state line token token-window)
  (cond
    ((and (%history-last-argument-scan-state-skip-redirect-target state)
          (eq (nshell.domain.parsing:token-type token) :ampersand))
     state)
    ((nshell.domain.parsing:shell-command-separator-token-p token)
     (%history-last-argument-reset-for-separator state))
    ((%history-redirect-token-p token)
     (setf (%history-last-argument-scan-state-skip-redirect-target state) t)
     state)
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
                   (%make-history-logical-word-cursor
                    (%history-logical-words tokens)))))
      (do ((remaining tokens (rest remaining)))
          ((endp remaining)
           (%history-last-argument-scan-state-last-argument state))
        (let* ((token-window (%history-token-window-from-remaining remaining))
               (token (%history-token-window-current token-window)))
          (%history-last-argument-handle-token state line token token-window))))))

(defun history-last-argument-at (history index)
  "Return INDEX-th most recent insertable last argument in HISTORY, or NIL."
  (when (and (integerp index) (not (minusp index)))
    (do ((entries (command-history-entries history) (rest entries)))
        ((endp entries) nil)
      (let ((argument (command-line-last-argument (entry-text (first entries)))))
        (when argument
          (if (zerop index)
              (return argument)
              (decf index)))))))
