; Token reduction: collapse flat token stream into command/separator/error triples.
(in-package #:nshell.domain.parsing)

(defstruct (%token-reduction-state
            (:constructor %make-token-reduction-state))
  (all-cmds '() :type list)
  (current-args '() :type list)
  (current-cmd nil)
  (current-cmd-token nil)
  (pending-redirect-token nil)
  (pending-sep nil)
  (pending-sep-token nil)
  (errors '() :type list))

(defun %record-missing-redirect-target (state)
  (let ((pending-redirect-token (%token-reduction-state-pending-redirect-token state)))
    (when pending-redirect-token
      (push (%token-diagnostic
             :missing-redirection-target
             (format nil "Expected target after '~a'"
                     (token-value pending-redirect-token))
             pending-redirect-token)
            (%token-reduction-state-errors state))
      (setf (%token-reduction-state-pending-redirect-token state) nil))))

(defun %flush-token-reduction-command (state)
  (when (%token-reduction-state-current-cmd state)
    (%record-missing-redirect-target state)
    (push (list (make-command-node
                 (%token-reduction-state-current-cmd state)
                 (nreverse (%token-reduction-state-current-args state))
                 (when (%token-reduction-state-current-cmd-token state)
                   (list (token-start (%token-reduction-state-current-cmd-token state))
                         (token-end (%token-reduction-state-current-cmd-token state))))
                 (when (%token-reduction-state-current-cmd-token state)
                   (token-quote-style (%token-reduction-state-current-cmd-token state))))
                (%token-reduction-state-pending-sep state)
                (%token-reduction-state-pending-sep-token state))
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
        (push (%token-diagnostic
               :missing-command
               (format nil "Expected command before '~a'"
                       (%separator-text separator))
               token)
              (%token-reduction-state-errors state)))))

(defun %token-reduction-word (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (let ((style (token-quote-style tok)))
          (push (if style
                    (cons (token-value tok) style)
                    (token-value tok))
                (%token-reduction-state-current-args state)))
        (setf (%token-reduction-state-pending-redirect-token state) nil))
      (setf (%token-reduction-state-current-cmd state) (token-value tok)
            (%token-reduction-state-current-cmd-token state) tok)))

(defun %token-reduction-redirect (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%record-missing-redirect-target state)
        (push (cons (token-value tok) nil)
              (%token-reduction-state-current-args state))
        ;; fd-dup redirects (e.g. 2>&1) are self-contained and need no
        ;; following target, so they do not start a pending redirect.
        (let ((spec (assoc (token-value tok) +redirect-specs+ :test #'string=)))
          (unless (and spec (member (cdr spec) +redirect-fd-dup-specs+))
            (setf (%token-reduction-state-pending-redirect-token state) tok))))
      (push (%token-diagnostic
             :missing-command
             (format nil "Expected command before '~a'" (token-value tok))
             tok)
            (%token-reduction-state-errors state))))

(defun %token-reduction-error (state tok)
  (push (cond
          ((string= "\\" (token-value tok))
           (%token-diagnostic
            :trailing-escape
            "Trailing escape requires continuation"
            tok))
          ((and (>= (length (token-value tok)) 2)
                (string= "<(" (subseq (token-value tok) 0 2)))
           (%token-diagnostic
            :unterminated-process-substitution
            "Unterminated process substitution"
            tok))
          (t
           (%token-diagnostic
            :unterminated-quote
            "Unterminated quoted string"
            tok)))
        (%token-reduction-state-errors state)))

(defun %token-reduction-separator (state tok)
  (let ((separator (%separator-from-token-type (token-type tok))))
    (if separator
        (%record-token-reduction-separator state separator tok)
        (push (%token-diagnostic
               :unexpected-token
               (format nil "Unexpected token: ~a" (token-value tok))
               tok)
              (%token-reduction-state-errors state)))))

(defun %reduce-token (state tok)
  (case (token-type tok)
    (:word (%token-reduction-word state tok))
    (:redirect (%token-reduction-redirect state tok))
    (:error (%token-reduction-error state tok))
    (t (%token-reduction-separator state tok))))

(defun %reduce-token-stream (tokens)
  (let ((state (%make-token-reduction-state)))
    (dolist (tok tokens)
      (%reduce-token state tok))
    (%flush-token-reduction-command state)
    (values (nreverse (%token-reduction-state-all-cmds state))
            (nreverse (%token-reduction-state-errors state)))))
