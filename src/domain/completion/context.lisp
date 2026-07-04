(in-package #:nshell.domain.completion)

(defstruct (completion-context
            (:constructor %make-completion-context
                (&key (command "") (argument-prefix "") command-position-p
                      (argument-words '()) redirection-target-p)))
  (command "" :type string :read-only t)
  (argument-prefix "" :type string :read-only t)
  (argument-words '() :type list :read-only t)
  (command-position-p nil :type boolean :read-only t)
  (redirection-target-p nil :type boolean :read-only t))

(defstruct (%completion-word
            (:constructor %make-completion-word (value start end))
            (:conc-name %completion-word-))
  (value "" :type string :read-only t)
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t))

(defstruct (%completion-input-analysis
            (:constructor %make-completion-input-analysis
                (partial-input cursor segment-tokens words current-word command-word))
            (:conc-name %completion-input-analysis-))
  (partial-input "" :type string :read-only t)
  (cursor 0 :type integer :read-only t)
  (segment-tokens '() :type list :read-only t)
  (words '() :type list :read-only t)
  (current-word nil :read-only t)
  (command-word nil :read-only t))

(defun %starts-with-p (prefix text)
  (and (>= (length text) (length prefix))
       (string-equal prefix text :end2 (length prefix))))

(defun %word-like-token-p (token)
  (not (null (member (nshell.domain.parsing:token-type token)
                     '(:word :error)
                     :test #'eq))))

(defun %redirection-token-p (token)
  (eq :redirect (nshell.domain.parsing:token-type token)))

(defun %command-segment-tokens (tokens)
  "Return tokens in the command segment currently being completed."
  (let ((last-separator (position-if #'nshell.domain.parsing:shell-command-separator-token-p
                                     tokens
                                     :from-end t)))
    (if last-separator
        (subseq tokens (1+ last-separator))
        tokens)))

(defun %shell-completion-words (tokens)
  "Coalesce adjacent parser word tokens into shell words.

The tokenizer already emits escaped-space words as single tokens, but quoted
fragments can still be split across adjacent word-like tokens. Completion wants
the logical shell word at the cursor, so adjacent word-like tokens with no
intervening whitespace are merged."
  (let ((words nil)
        (current-value nil)
        (current-start 0)
        (current-end 0))
    (labels ((flush-current ()
               (when current-value
                 (push (%make-completion-word current-value
                                              current-start
                                              current-end)
                       words)
                 (setf current-value nil))))
      (dolist (token tokens)
        (if (%word-like-token-p token)
            (let ((value (nshell.domain.parsing:token-value token))
                  (start (nshell.domain.parsing:token-start token))
                  (end (nshell.domain.parsing:token-end token)))
              (cond
                ((null current-value)
                 (setf current-value value
                       current-start start
                       current-end end))
                ((= start current-end)
                 (setf current-value (concatenate 'string current-value value)
                       current-end end))
                (t
                 (flush-current)
                 (setf current-value value
                       current-start start
                       current-end end))))
            (flush-current)))
      (flush-current))
    (nreverse words)))

(defun %token-ending-before-position (tokens position)
  (find-if (lambda (token)
             (<= (nshell.domain.parsing:token-end token) position))
           tokens
           :from-end t))

(defun %redirection-target-position-p (tokens current-word cursor)
  (let ((previous-token
          (%token-ending-before-position
           tokens
           (if current-word
               (%completion-word-start current-word)
               cursor))))
    (and previous-token
         (%redirection-token-p previous-token))))

(defun %command-word (partial-input words)
  "Return the first non-assignment completion word in WORDS."
  (loop for word in words
        for source = (subseq partial-input
                             (%completion-word-start word)
                             (%completion-word-end word))
        unless (nshell.domain.parsing:shell-assignment-word-p source)
          return word))

(defun %argument-word-values-after-command (words command-word)
  (when command-word
    (loop with seen-command-p = nil
          for word in words
          if (eq word command-word)
            do (setf seen-command-p t)
          else
            when seen-command-p
              collect (%completion-word-value word))))

(defun %latest-completion-word (words)
  (loop for word in words
        finally (return word)))

(defun %current-completion-word-at-cursor (words cursor)
  (let ((last-word (%latest-completion-word words)))
    (and last-word
         (= cursor (%completion-word-end last-word))
         last-word)))

(defun %analyze-completion-input (partial-input)
  (let* ((tokenization (nshell.domain.parsing:tokenize partial-input))
         (tokens (nshell.domain.parsing:tokenization-result-tokens tokenization))
         (cursor (length partial-input))
         (segment-tokens (%command-segment-tokens tokens))
         (words (%shell-completion-words segment-tokens))
         (current-word (%current-completion-word-at-cursor words cursor))
         (command-word (%command-word partial-input words)))
    (%make-completion-input-analysis partial-input
                                     cursor
                                     segment-tokens
                                     words
                                     current-word
                                     command-word)))

(defun %completion-command-position-p (command-word current-word cursor)
  (or (null command-word)
      (and (eq current-word command-word)
           (= cursor (%completion-word-end command-word)))))

(defun %completion-analysis-command-position-p (analysis)
  (%completion-command-position-p
   (%completion-input-analysis-command-word analysis)
   (%completion-input-analysis-current-word analysis)
   (%completion-input-analysis-cursor analysis)))

(defun %completion-analysis-command (analysis)
  (let ((command-word (%completion-input-analysis-command-word analysis)))
    (if command-word
        (%completion-word-value command-word)
        "")))

(defun %completion-analysis-argument-prefix (analysis command-position-p)
  (let ((current-word (%completion-input-analysis-current-word analysis)))
    (if (and current-word
             (not command-position-p))
        (%completion-word-value current-word)
        "")))

(defun %completion-analysis-argument-words (analysis)
  (%argument-word-values-after-command
   (%completion-input-analysis-words analysis)
   (%completion-input-analysis-command-word analysis)))

(defun %completion-analysis-redirection-target-p (analysis)
  (%redirection-target-position-p
   (%completion-input-analysis-segment-tokens analysis)
   (%completion-input-analysis-current-word analysis)
   (%completion-input-analysis-cursor analysis)))

(defun %completion-context-from-analysis (analysis)
  (let* ((command-position-p (%completion-analysis-command-position-p analysis))
         (command (%completion-analysis-command analysis))
         (argument-prefix
           (%completion-analysis-argument-prefix analysis command-position-p))
         (argument-words (%completion-analysis-argument-words analysis))
         (redirection-target-p
           (%completion-analysis-redirection-target-p analysis)))
    (%make-completion-context
     :command command
     :argument-prefix argument-prefix
     :argument-words argument-words
     :command-position-p command-position-p
     :redirection-target-p redirection-target-p)))

(defun completion-context-for (partial-input)
  (%completion-context-from-analysis
   (%analyze-completion-input partial-input)))
