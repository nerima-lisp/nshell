; Token reduction: collapse flat token stream into command/separator/error triples.
(in-package #:nshell.domain.parsing)

(defstruct (%token-reduction-state
             (:constructor %make-token-reduction-state
                 (&key (all-cmds '())
                       (current-args '())
                       current-cmd
                       current-cmd-token
                       pending-redirect-token
                       pending-sep
                       pending-sep-token
                       (errors '()))))
  (all-cmds '() :type list)
  (current-args '() :type list)
  current-cmd
  current-cmd-token
  pending-redirect-token
  pending-sep
  pending-sep-token
  (errors '() :type list))

(defstruct (%token-reduction-result
             (:constructor %make-token-reduction-result (commands errors)))
  (commands '() :type list)
  (errors '() :type list))

(defun %redirect-token-targetless-p (tok)
  (%redirect-targetless-p (token-value tok)))

(defun %command-node-from-token-reduction-state (state)
  (let ((cmd-token (%token-reduction-state-current-cmd-token state)))
    (make-command-node
     (%token-reduction-state-current-cmd state)
     (nreverse (%token-reduction-state-current-args state))
     (when cmd-token
       (list (token-start cmd-token)
             (token-end cmd-token)))
     (when cmd-token
       (token-quote-style cmd-token)))))

(defstruct (%token-reduction-argument
            (:constructor %make-token-reduction-argument
                (value quote-style syntactic-p)))
  (value "" :type string :read-only t)
  (quote-style nil :read-only t)
  (syntactic-p nil :type boolean :read-only t))

(defun %token-reduction-argument-from-word-token (tok)
  (%make-token-reduction-argument
   (token-value tok)
   (token-quote-style tok)
   nil))

(defun %token-reduction-argument-from-redirect-token (tok)
  (%make-token-reduction-argument
   (token-value tok)
   nil
   t))

(defun %token-reduction-argument-raw-value (argument)
  (make-command-arg
   (%token-reduction-argument-value argument)
   (%token-reduction-argument-quote-style argument)))

(defun %token-reduction-word-argument (tok)
  (%token-reduction-argument-raw-value
   (%token-reduction-argument-from-word-token tok)))

(defun %token-reduction-state-append-argument (state argument)
  (push argument (%token-reduction-state-current-args state))
  state)

(defun %token-reduction-state-append-word-argument (state tok)
  (%token-reduction-state-append-argument state
                                          (%token-reduction-word-argument tok)))

(defun %token-reduction-state-append-redirect-argument (state tok)
  (%token-reduction-state-append-argument
   state
   (%token-reduction-argument-raw-value
    (%token-reduction-argument-from-redirect-token tok))))

(defun %token-reduction-state-start-command (state tok)
  (setf (%token-reduction-state-current-cmd state) (token-value tok)
        (%token-reduction-state-current-cmd-token state) tok)
  state)

(defun %token-reduction-state-clear-pending-redirect (state)
  (setf (%token-reduction-state-pending-redirect-token state) nil)
  state)

(defun %token-reduction-state-mark-pending-redirect (state tok)
  (setf (%token-reduction-state-pending-redirect-token state) tok)
  state)

(defun %token-reduction-state-mark-pending-separator (state separator token)
  (setf (%token-reduction-state-pending-sep state) separator
        (%token-reduction-state-pending-sep-token state) token)
  state)

(defun %token-reduction-state-clear-pending-separator (state)
  (setf (%token-reduction-state-pending-sep state) nil
        (%token-reduction-state-pending-sep-token state) nil)
  state)

(defstruct (%token-reduction-diagnostic-policy
            (:constructor %make-token-reduction-diagnostic-policy
                (kind message)))
  (kind nil :type keyword :read-only t)
  (message "" :type string :read-only t))

(defun %token-reduction-diagnostic (token policy)
  (%token-diagnostic
   (%token-reduction-diagnostic-policy-kind policy)
   (%token-reduction-diagnostic-policy-message policy)
   token))

(defun %token-reduction-state-record-diagnostic (state token policy)
  (push (%token-reduction-diagnostic token policy)
        (%token-reduction-state-errors state))
  state)

(defun %token-reduction-state-record-diagnostic-message (state kind message token)
  (%token-reduction-state-record-diagnostic
   state
   token
   (%make-token-reduction-diagnostic-policy kind message)))

(defun %token-reduction-missing-redirect-target-policy (token)
  (%make-token-reduction-diagnostic-policy
   :missing-redirection-target
   (format nil "Expected target after '~a'" (token-value token))))

(defun %record-missing-redirect-target (state)
  (let ((pending-redirect-token (%token-reduction-state-pending-redirect-token state)))
    (when pending-redirect-token
      (%token-reduction-state-record-diagnostic
       state
       pending-redirect-token
       (%token-reduction-missing-redirect-target-policy pending-redirect-token))
      (%token-reduction-state-clear-pending-redirect state))))

(defun %token-reduction-error-policy-from-token (token)
  (let ((value (token-value token)))
    (cond
      ((string= "\\" value)
       (%make-token-reduction-diagnostic-policy
        :trailing-escape
        "Trailing escape requires continuation"))
      ((and (>= (length value) 2)
            (string= "<(" (subseq value 0 2)))
       (%make-token-reduction-diagnostic-policy
        :unterminated-process-substitution
        "Unterminated process substitution"))
      (t
       (%make-token-reduction-diagnostic-policy
        :unterminated-quote
        "Unterminated quoted string")))))

(defun %token-reduction-command-entry-from-state (state)
  (list (%command-node-from-token-reduction-state state)
        (%token-reduction-state-pending-sep state)
        (%token-reduction-state-pending-sep-token state)))

(defun %token-reduction-state-record-command-entry (state)
  (push (%token-reduction-command-entry-from-state state)
        (%token-reduction-state-all-cmds state))
  state)

(defun %token-reduction-state-clear-command-context (state)
  (setf (%token-reduction-state-current-cmd state) nil
        (%token-reduction-state-current-cmd-token state) nil
        (%token-reduction-state-current-args state) '()
        (%token-reduction-state-pending-redirect-token state) nil)
  (%token-reduction-state-clear-pending-separator state)
  state)

(defun %flush-token-reduction-command (state)
  (when (%token-reduction-state-current-cmd state)
    (%record-missing-redirect-target state)
    (%token-reduction-state-record-command-entry state)
    (%token-reduction-state-clear-command-context state)))

(defun %record-token-reduction-separator (state separator token)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%record-missing-redirect-target state)
        (%token-reduction-state-mark-pending-separator state separator token)
        (%flush-token-reduction-command state))
      (unless (eq (token-type token) :newline)
        (%token-reduction-state-record-diagnostic-message
         state
         :missing-command
         (format nil "Expected command before '~a'"
                 (%separator-text separator))
         token))))

(defun %token-reduction-word (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%token-reduction-state-append-word-argument state tok)
        (%token-reduction-state-clear-pending-redirect state))
      (%token-reduction-state-start-command state tok)))

(defun %token-reduction-redirect (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%record-missing-redirect-target state)
        (%token-reduction-state-append-redirect-argument state tok)
        ;; Targetless redirects (e.g. 2>&1) are self-contained and do
        ;; not start a pending redirect.
        (unless (%redirect-token-targetless-p tok)
          (%token-reduction-state-mark-pending-redirect state tok)))
      (%token-reduction-state-record-diagnostic-message
       state
       :missing-command
       (format nil "Expected command before '~a'" (token-value tok))
       tok)))

(defun %token-reduction-error (state tok)
  (%token-reduction-state-record-diagnostic
   state
   tok
   (%token-reduction-error-policy-from-token tok)))

(defun %token-reduction-separator (state tok)
  (let ((separator (%separator-from-token-type (token-type tok))))
    (if separator
        (%record-token-reduction-separator state separator tok)
        (%token-reduction-state-record-diagnostic-message
         state
         :unexpected-token
         (format nil "Unexpected token: ~a" (token-value tok))
         tok))))

(defun %reduce-token (state tok)
  (case (token-type tok)
    (:word (%token-reduction-word state tok))
    (:redirect (%token-reduction-redirect state tok))
    (:error (%token-reduction-error state tok))
    (t (%token-reduction-separator state tok))))

(defun %token-reduction-state-after-token (state tok)
  (%reduce-token state tok)
  state)

(defun %token-reduction-state-from-tokens (tokens)
  (let ((state (reduce #'%token-reduction-state-after-token
                       tokens
                       :initial-value (%make-token-reduction-state))))
    (%flush-token-reduction-command state)
    state))

(defun %token-reduction-result-from-state (state)
  (%make-token-reduction-result
   (nreverse (%token-reduction-state-all-cmds state))
   (nreverse (%token-reduction-state-errors state))))

(defun %reduce-token-stream-result (tokens)
  (%token-reduction-result-from-state
   (%token-reduction-state-from-tokens tokens)))
