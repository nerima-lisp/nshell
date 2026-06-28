; Token data structures, character predicates, and state operations.
(in-package #:nshell.domain.parsing)

(defstruct (token (:constructor make-token (type value &optional (start 0) (end 0)
                                            (quote-style nil))))
  (type :word :type keyword :read-only t)
  (value "" :type string :read-only t)
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t)
  (quote-style nil :type symbol :read-only t))

;; token-type, token-value, token-start, token-end are auto-generated struct accessors

(defstruct (tokenizer-state (:constructor %make-tokenizer-state))
  input
  len
  cursor-pos
  (pos 0 :type integer)
  (tokens '() :type list)
  (incomplete nil :type boolean))

(defun shell-assignment-word-p (word)
  "Return true when WORD looks like a shell assignment word."
  (and (stringp word)
       (plusp (length word))
       (let ((equals-position (position #\= word)))
         (and equals-position
              (plusp equals-position)
              (loop for index below equals-position
                    for ch = (char word index)
                    always (if (zerop index)
                               (or (alpha-char-p ch) (char= ch #\_))
                                 (or (alphanumericp ch) (char= ch #\_))))))))

(defparameter +shell-word-separator-characters+
  '(#\Space #\Tab #\Newline)
  "Characters that separate shell words.")

(defparameter +shell-operator-separator-characters+
  '(#\| #\; #\& #\< #\>)
  "Characters that separate shell operators.")

(defparameter +shell-command-separator-token-types+
  '(:pipe :and :or :semicolon :newline :ampersand)
  "Token types that separate shell command segments.")

(defun shell-word-separator-p (ch)
  (member ch +shell-word-separator-characters+ :test #'char=))

(defun shell-operator-separator-p (ch)
  (member ch +shell-operator-separator-characters+ :test #'char=))

(defun shell-token-separator-p (ch)
  (or (shell-word-separator-p ch)
      (shell-operator-separator-p ch)))

(defun shell-command-separator-token-p (token)
  (member (token-type token) +shell-command-separator-token-types+ :test #'eq))

(defun %shell-input-separator-p (ch include-return-p)
  (or (member ch +shell-word-separator-characters+ :test #'char=)
      (member ch +shell-operator-separator-characters+ :test #'char=)
      (and include-return-p (char= ch #\Return))))

(defun shell-input-blank-p (input &key include-return-p)
  "Return true when INPUT contains only shell separators."
  (every (lambda (ch)
           (%shell-input-separator-p ch include-return-p))
         input))

(defun make-tokenizer-state (input &key cursor-pos)
  (%make-tokenizer-state :input input
                         :len (length input)
                         :cursor-pos (or cursor-pos (length input))))

(defun %tokenizer-state-peek (state &optional (offset 0))
  (let ((p (+ (tokenizer-state-pos state) offset)))
    (if (< p (tokenizer-state-len state))
        (char (tokenizer-state-input state) p)
        nil)))

(defun %tokenizer-state-advance (state &optional (n 1))
  (incf (tokenizer-state-pos state) n))

(defun %tokenizer-state-take (state)
  (let ((ch (%tokenizer-state-peek state)))
    (%tokenizer-state-advance state)
    ch))

(defun %tokenizer-state-push-token (state type value start end &optional quote-style)
  (push (make-token type value start end quote-style) (tokenizer-state-tokens state)))

(defun %tokenizer-state-emit-token (state type value &optional quote-style)
  (let ((start (tokenizer-state-pos state))
        (width (length value)))
    (%tokenizer-state-push-token state type value start (+ start width) quote-style)
    (%tokenizer-state-advance state width)))

(defun %balanced-substitution-end (input start)
  (let ((depth 0)
        (quote nil)
        (escaped nil))
    (loop for index from start below (length input)
          for ch = (char input index)
          do (cond
               (escaped
                (setf escaped nil))
               ((char= ch #\\)
                (setf escaped t))
               (quote
                (when (char= ch quote)
                  (setf quote nil)))
               ((or (char= ch #\') (char= ch #\"))
                (setf quote ch))
               ((char= ch #\()
                (incf depth))
               ((char= ch #\))
                (decf depth)
                (when (zerop depth)
                  (return index)))))))

(defun %tokenizer-balanced-substitution-end (state start)
  (%balanced-substitution-end (tokenizer-state-input state) start))
