; Token data structures, character predicates, and state operations.
(in-package #:nshell.domain.parsing)

(defstruct (token (:constructor %make-token (type value &optional (start 0) (end 0)
                                             (quote-style nil))))
  (type :word :type keyword :read-only t)
  (value "" :type string :read-only t)
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t)
  (quote-style nil :type symbol :read-only t))

;; token-type, token-value, token-start, token-end are auto-generated struct accessors

(defstruct (tokenization-result
            (:constructor %make-tokenization-result
                (tokens cursor-token incomplete-p))
            (:conc-name %tokenization-result-))
  (tokens nil :type list :read-only t)
  (cursor-token nil :read-only t)
  (incomplete-p nil :type boolean :read-only t))

(defun tokenization-result-tokens (result)
  (copy-list (%tokenization-result-tokens result)))

(defun tokenization-result-cursor-token (result)
  (%tokenization-result-cursor-token result))

(defun tokenization-result-incomplete-p (result)
  (%tokenization-result-incomplete-p result))

(defun %token-position (position)
  (or position 0))

(defun %token-value (value)
  (or value ""))

(defstruct (%token-extent
            (:constructor %make-token-extent (start end value)))
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t)
  (value "" :type string :read-only t))

(defun %token-extent (start value)
  (let* ((normalized-start (%token-position start))
         (normalized-value (%token-value value)))
    (%make-token-extent normalized-start
                        (+ normalized-start (length normalized-value))
                        normalized-value)))

(defun make-token (type value &optional (start 0) (end 0) quote-style)
  (%make-token type
               (%token-value value)
               (%token-position start)
               (%token-position end)
               quote-style))

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

(defparameter +shell-word-boundary-delimiter-characters+
  '(#\( #\) #\' #\")
  "Characters that terminate words without becoming token separators.")

(defparameter +shell-command-separator-token-types+
  '(:pipe :and :or :semicolon :newline :ampersand)
  "Token types that separate shell command segments.")

(defstruct (%shell-character-boundary
            (:constructor %make-shell-character-boundary (character kind)))
  (character nil :read-only t)
  (kind nil :type (or null keyword) :read-only t))

(defstruct (%shell-input-blankness-spec
            (:constructor %make-shell-input-blankness-spec (include-return-p)))
  (include-return-p nil :type boolean :read-only t))

(defun %shell-separator-character-p (ch separators)
  (and ch (not (null (member ch separators :test #'char=)))))

(defun shell-word-separator-p (ch)
  (%shell-separator-character-p ch +shell-word-separator-characters+))

(defun shell-operator-separator-p (ch)
  (%shell-separator-character-p ch +shell-operator-separator-characters+))

(defun shell-token-separator-p (ch)
  (or (shell-word-separator-p ch)
      (shell-operator-separator-p ch)))

(defun %shell-word-boundary-delimiter-p (ch)
  (%shell-separator-character-p ch +shell-word-boundary-delimiter-characters+))

(defun %shell-character-boundary (ch)
  (cond
    ((shell-token-separator-p ch)
     (%make-shell-character-boundary ch :token-separator))
    ((%shell-word-boundary-delimiter-p ch)
     (%make-shell-character-boundary ch :word-boundary-delimiter))))

(defun %shell-word-boundary-p (ch)
  (not (null (%shell-character-boundary ch))))

(defun shell-command-separator-token-p (token)
  (not (null (member (token-type token)
                     +shell-command-separator-token-types+
                     :test #'eq))))

(defun %shell-input-blankness-spec-from-options (&key include-return-p)
  (%make-shell-input-blankness-spec (not (null include-return-p))))

(defun %shell-input-separator-p (ch spec)
  (or (shell-token-separator-p ch)
      (and (%shell-input-blankness-spec-include-return-p spec)
           ch
           (char= ch #\Return))))

(defun shell-input-blank-p (input &key include-return-p)
  "Return true when INPUT contains only shell separators."
  (let ((spec (%shell-input-blankness-spec-from-options
               :include-return-p include-return-p)))
    (every (lambda (ch)
             (%shell-input-separator-p ch spec))
           input)))

(defun %make-tokenizer-state-for-input (input &key cursor-pos)
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
  (let ((extent (%token-extent (tokenizer-state-pos state) value)))
    (%tokenizer-state-push-token state
                                 type
                                 (%token-extent-value extent)
                                 (%token-extent-start extent)
                                 (%token-extent-end extent)
                                 quote-style)
    (setf (tokenizer-state-pos state) (%token-extent-end extent))))

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
