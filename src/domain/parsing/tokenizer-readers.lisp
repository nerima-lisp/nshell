; Low-level character readers for words, quotes, balanced substitutions.
(in-package #:nshell.domain.parsing)

(defstruct (%tokenizer-balanced-token-boundary
            (:constructor %make-tokenizer-balanced-token-boundary
                (substitution-end token-end)))
  (substitution-end nil :read-only t)
  (token-end 0 :type integer :read-only t))

(defun %tokenizer-balanced-token-boundary-for (state paren-pos)
  (let ((end (%tokenizer-balanced-substitution-end state paren-pos)))
    (%make-tokenizer-balanced-token-boundary
     end
     (or (and end (1+ end))
         (tokenizer-state-len state)))))

(defun %tokenizer-input-slice (state start end)
  (subseq (tokenizer-state-input state) start end))

(defun %tokenizer-read-balanced-command-substitution (state)
  (let* ((start (tokenizer-state-pos state))
         (end (%tokenizer-balanced-substitution-end state start)))
    (%tokenizer-state-push-token state :word
                                 (%tokenizer-input-slice state start (1+ end))
                                 start
                                 (1+ end))
    (setf (tokenizer-state-pos state) (1+ end))))

(defun %tokenizer-read-prefixed-balanced-substitution (state paren-offset)
  (let ((start (tokenizer-state-pos state)))
    (let* ((boundary
             (%tokenizer-balanced-token-boundary-for state (+ start paren-offset)))
           (token-end (%tokenizer-balanced-token-boundary-token-end boundary))
           (value (%tokenizer-input-slice state start token-end)))
      (setf (tokenizer-state-pos state) token-end)
      (if (%tokenizer-balanced-token-boundary-substitution-end boundary)
          (%tokenizer-state-push-token state :word value start token-end)
          (progn
            (setf (tokenizer-state-incomplete state) t)
            (%tokenizer-state-push-token state :error value start token-end))))))

(defun %tokenizer-read-balanced-process-substitution (state)
  (%tokenizer-read-prefixed-balanced-substitution state 1))

(defun %tokenizer-word-dollar-substitution-end (state ch)
  (and (char= ch #\$)
       (eql (%tokenizer-state-peek state 1) #\()
       (%tokenizer-balanced-substitution-end
        state (1+ (tokenizer-state-pos state)))))

(defun %tokenizer-word-fish-substitution-end (state ch)
  (and (char= ch #\()
       (%tokenizer-state-peek state 1)
       (char/= (%tokenizer-state-peek state 1) #\))
       (%tokenizer-balanced-substitution-end state (tokenizer-state-pos state))))

(defun %tokenizer-append-balanced-substitution (state chars end)
  (let* ((start (tokenizer-state-pos state))
         (input (tokenizer-state-input state)))
    (loop for index from start to end
          do (push (char input index) chars))
    (setf (tokenizer-state-pos state) (1+ end))
    chars))

(defstruct (%tokenizer-word-scan-action
            (:constructor %make-tokenizer-word-scan-action (kind end)))
  (kind :character :type keyword :read-only t)
  (end nil :read-only t))

(defun %tokenizer-word-scan-action-for (state ch)
  (let* ((dollar-end (%tokenizer-word-dollar-substitution-end state ch))
         (fish-end (and (not dollar-end)
                        (%tokenizer-word-fish-substitution-end state ch))))
    (cond (dollar-end
           (%make-tokenizer-word-scan-action :dollar-substitution dollar-end))
           (fish-end
           (%make-tokenizer-word-scan-action :fish-substitution fish-end))
           ((%shell-word-boundary-p ch)
           (%make-tokenizer-word-scan-action :boundary nil))
           ((char= ch #\\)
           (%make-tokenizer-word-scan-action :escape nil))
           (t
           (%make-tokenizer-word-scan-action :character nil)))))

(defun %tokenizer-read-word (state)
  (let ((start (tokenizer-state-pos state))
        (chars '()))
    (loop while (< (tokenizer-state-pos state) (tokenizer-state-len state))
          for ch = (%tokenizer-state-peek state)
          do (let ((action (%tokenizer-word-scan-action-for state ch)))
               (case (%tokenizer-word-scan-action-kind action)
                 (:dollar-substitution
                  (push (%tokenizer-state-take state) chars)
                  (setf chars (%tokenizer-append-balanced-substitution
                               state chars
                               (%tokenizer-word-scan-action-end action))))
                 (:fish-substitution
                  (setf chars (%tokenizer-append-balanced-substitution
                               state chars
                               (%tokenizer-word-scan-action-end action))))
                 (:boundary
                  (return))
                 (:escape
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
                 (:character
                  (push ch chars)
                  (%tokenizer-state-advance state)))))
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
          (%tokenizer-state-push-token state :error
                                       (coerce (nreverse chars) 'string)
                                       start
                                       (tokenizer-state-pos state))))))

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
