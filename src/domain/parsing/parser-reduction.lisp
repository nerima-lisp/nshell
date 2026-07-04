; Token reduction: collapse flat token stream into command/separator/error triples.
(in-package #:nshell.domain.parsing)

(defconstant +token-reduction-state-all-cmds+ 0)
(defconstant +token-reduction-state-current-args+ 1)
(defconstant +token-reduction-state-current-cmd+ 2)
(defconstant +token-reduction-state-current-cmd-token+ 3)
(defconstant +token-reduction-state-pending-redirect-token+ 4)
(defconstant +token-reduction-state-pending-sep+ 5)
(defconstant +token-reduction-state-pending-sep-token+ 6)
(defconstant +token-reduction-state-errors+ 7)
(defconstant +token-reduction-state-size+ 8)

(defun %make-token-reduction-state ()
  (let ((state (make-array +token-reduction-state-size+ :initial-element nil)))
    (setf (aref state +token-reduction-state-all-cmds+) '()
          (aref state +token-reduction-state-current-args+) '()
          (aref state +token-reduction-state-errors+) '())
    state))

(defun %token-reduction-state-all-cmds (state)
  (aref state +token-reduction-state-all-cmds+))

(defun (setf %token-reduction-state-all-cmds) (value state)
  (setf (aref state +token-reduction-state-all-cmds+) value))

(defun %token-reduction-state-current-args (state)
  (aref state +token-reduction-state-current-args+))

(defun (setf %token-reduction-state-current-args) (value state)
  (setf (aref state +token-reduction-state-current-args+) value))

(defun %token-reduction-state-current-cmd (state)
  (aref state +token-reduction-state-current-cmd+))

(defun (setf %token-reduction-state-current-cmd) (value state)
  (setf (aref state +token-reduction-state-current-cmd+) value))

(defun %token-reduction-state-current-cmd-token (state)
  (aref state +token-reduction-state-current-cmd-token+))

(defun (setf %token-reduction-state-current-cmd-token) (value state)
  (setf (aref state +token-reduction-state-current-cmd-token+) value))

(defun %token-reduction-state-pending-redirect-token (state)
  (aref state +token-reduction-state-pending-redirect-token+))

(defun (setf %token-reduction-state-pending-redirect-token) (value state)
  (setf (aref state +token-reduction-state-pending-redirect-token+) value))

(defun %token-reduction-state-pending-sep (state)
  (aref state +token-reduction-state-pending-sep+))

(defun (setf %token-reduction-state-pending-sep) (value state)
  (setf (aref state +token-reduction-state-pending-sep+) value))

(defun %token-reduction-state-pending-sep-token (state)
  (aref state +token-reduction-state-pending-sep-token+))

(defun (setf %token-reduction-state-pending-sep-token) (value state)
  (setf (aref state +token-reduction-state-pending-sep-token+) value))

(defun %token-reduction-state-errors (state)
  (aref state +token-reduction-state-errors+))

(defun (setf %token-reduction-state-errors) (value state)
  (setf (aref state +token-reduction-state-errors+) value))

(defstruct (%token-reduction-result
             (:constructor %make-token-reduction-result (commands errors)))
  (commands '() :type list)
  (errors '() :type list))

(defun %push-token-reduction-diagnostic (state kind message token)
  (push (%token-diagnostic kind message token)
        (%token-reduction-state-errors state)))

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
  (if (or (%token-reduction-argument-quote-style argument)
          (%token-reduction-argument-syntactic-p argument))
      (cons (%token-reduction-argument-value argument)
            (%token-reduction-argument-quote-style argument))
      (%token-reduction-argument-value argument)))

(defun %token-reduction-word-argument (tok)
  (%token-reduction-argument-raw-value
   (%token-reduction-argument-from-word-token tok)))

(defun %push-token-reduction-argument (state argument)
  (push argument (%token-reduction-state-current-args state)))

(defun %push-token-reduction-word-argument (state tok)
  (%push-token-reduction-argument state
                                  (%token-reduction-word-argument tok)))

(defun %push-token-reduction-redirect-argument (state tok)
  (%push-token-reduction-argument state
                                  (%token-reduction-argument-raw-value
                                   (%token-reduction-argument-from-redirect-token
                                    tok))))

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

(defun %token-reduction-missing-redirect-target-policy (token)
  (%make-token-reduction-diagnostic-policy
   :missing-redirection-target
   (format nil "Expected target after '~a'" (token-value token))))

(defun %record-missing-redirect-target (state)
  (let ((pending-redirect-token (%token-reduction-state-pending-redirect-token state)))
    (when pending-redirect-token
      (push (%token-reduction-diagnostic
             pending-redirect-token
             (%token-reduction-missing-redirect-target-policy
              pending-redirect-token))
            (%token-reduction-state-errors state))
      (setf (%token-reduction-state-pending-redirect-token state) nil))))

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

(defun %flush-token-reduction-command (state)
  (when (%token-reduction-state-current-cmd state)
    (%record-missing-redirect-target state)
    (push (%token-reduction-command-entry-from-state state)
          (%token-reduction-state-all-cmds state))
    (setf (%token-reduction-state-current-cmd state) nil
          (%token-reduction-state-current-cmd-token state) nil
          (%token-reduction-state-current-args state) '()
          (%token-reduction-state-pending-redirect-token state) nil
          (%token-reduction-state-pending-sep state) nil
          (%token-reduction-state-pending-sep-token state) nil)))

(defun %record-token-reduction-separator (state separator token)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%record-missing-redirect-target state)
        (setf (%token-reduction-state-pending-sep state) separator
              (%token-reduction-state-pending-sep-token state) token)
        (%flush-token-reduction-command state))
      (unless (eq (token-type token) :newline)
        (%push-token-reduction-diagnostic
         state
         :missing-command
         (format nil "Expected command before '~a'"
                 (%separator-text separator))
         token))))

(defun %token-reduction-word (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%push-token-reduction-word-argument state tok)
        (setf (%token-reduction-state-pending-redirect-token state) nil))
      (setf (%token-reduction-state-current-cmd state) (token-value tok)
            (%token-reduction-state-current-cmd-token state) tok)))

(defun %token-reduction-redirect (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%record-missing-redirect-target state)
        (%push-token-reduction-redirect-argument state tok)
        ;; Targetless redirects (e.g. 2>&1) are self-contained and do
        ;; not start a pending redirect.
        (unless (%redirect-token-targetless-p tok)
          (setf (%token-reduction-state-pending-redirect-token state) tok)))
      (%push-token-reduction-diagnostic
       state
       :missing-command
       (format nil "Expected command before '~a'" (token-value tok))
       tok)))

(defun %token-reduction-error (state tok)
  (push (%token-reduction-diagnostic
         tok
         (%token-reduction-error-policy-from-token tok))
        (%token-reduction-state-errors state)))

(defun %token-reduction-separator (state tok)
  (let ((separator (%separator-from-token-type (token-type tok))))
    (if separator
        (%record-token-reduction-separator state separator tok)
        (%push-token-reduction-diagnostic
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

(defun %token-reduction-result-from-state (state)
  (%make-token-reduction-result
   (nreverse (%token-reduction-state-all-cmds state))
   (nreverse (%token-reduction-state-errors state))))

(defun %reduce-token-stream-result (tokens)
  (let ((state (%make-token-reduction-state)))
    (dolist (tok tokens)
      (%reduce-token state tok))
    (%flush-token-reduction-command state)
    (%token-reduction-result-from-state state)))
