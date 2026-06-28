(in-package #:nshell.domain.completion)

(defstruct (completion-context
            (:constructor make-completion-context
                (&key (command "") (argument-prefix "") command-position-p
                      (argument-words '()) redirection-target-p)))
  (command "" :type string :read-only t)
  (argument-prefix "" :type string :read-only t)
  (argument-words '() :type list :read-only t)
  (command-position-p nil :type boolean :read-only t)
  (redirection-target-p nil :type boolean :read-only t))

(defstruct (completion-word
            (:constructor make-completion-word (value start end)))
  (value "" :type string :read-only t)
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t))

(defun starts-with-p (prefix text)
  (and (>= (length text) (length prefix))
       (string-equal prefix text :end2 (length prefix))))

(defun word-like-token-p (token)
  (not (null (member (nshell.domain.parsing:token-type token)
                     '(:word :error)
                     :test #'eq))))

(defun redirection-token-p (token)
  (eq :redirect (nshell.domain.parsing:token-type token)))

(defun command-segment-tokens (tokens)
  "Return tokens in the command segment currently being completed."
  (let ((last-separator (position-if #'nshell.domain.parsing:shell-command-separator-token-p
                                     tokens
                                     :from-end t)))
    (if last-separator
        (subseq tokens (1+ last-separator))
        tokens)))

(defun shell-completion-words (tokens)
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
                 (push (make-completion-word current-value
                                             current-start
                                             current-end)
                       words)
                 (setf current-value nil))))
      (dolist (token tokens)
        (if (word-like-token-p token)
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

(defun token-ending-before-position (tokens position)
  (find-if (lambda (token)
             (<= (nshell.domain.parsing:token-end token) position))
           tokens
           :from-end t))

(defun redirection-target-position-p (tokens current-word cursor)
  (let ((previous-token
          (token-ending-before-position
           tokens
           (if current-word
               (completion-word-start current-word)
               cursor))))
    (and previous-token
         (redirection-token-p previous-token))))

(defun command-word (partial-input words)
  "Return the first non-assignment completion word in WORDS."
  (loop for word in words
        for source = (subseq partial-input
                             (completion-word-start word)
                             (completion-word-end word))
        unless (nshell.domain.parsing:shell-assignment-word-p source)
          return word))

(defun argument-word-values-after-command (words command-word)
  (when command-word
    (loop with seen-command-p = nil
          for word in words
          if (eq word command-word)
            do (setf seen-command-p t)
          else
            when seen-command-p
              collect (completion-word-value word))))

(defun completion-context-for (partial-input)
  (multiple-value-bind (tokens cursor-token incomplete-p)
      (nshell.domain.parsing:tokenize partial-input)
    (declare (ignore cursor-token incomplete-p))
    (let* ((cursor (length partial-input))
           (segment-tokens (command-segment-tokens tokens))
           (words (shell-completion-words segment-tokens))
           (last-word (car (last words)))
           (current-word (and last-word
                              (= cursor (completion-word-end last-word))
                              last-word))
           (command-word (command-word partial-input words))
           (command-position-p
             (or (null command-word)
                 (and (eq current-word command-word)
                      (= cursor (completion-word-end command-word)))))
           (command (if command-word
                        (completion-word-value command-word)
                        ""))
           (argument-prefix
             (if (and current-word
                      (not command-position-p))
                 (completion-word-value current-word)
                 ""))
           (argument-words
             (argument-word-values-after-command words command-word))
           (redirection-target-p
             (redirection-target-position-p segment-tokens current-word cursor)))
      (make-completion-context
       :command command
       :argument-prefix argument-prefix
       :argument-words argument-words
       :command-position-p command-position-p
       :redirection-target-p redirection-target-p))))
