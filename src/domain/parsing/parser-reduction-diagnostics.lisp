(in-package #:nshell.domain.parsing)

(defun %token-reduction-diagnostic (token policy)
  (%token-diagnostic
   (%token-reduction-diagnostic-policy-kind policy)
   (%token-reduction-diagnostic-policy-message policy)
   token))

(defun %token-reduction-state-record-diagnostic (state token policy)
  (%update-token-reduction-state
   state
   (errors (cons (%token-reduction-diagnostic token policy)
                 (%token-reduction-state-errors state)))))

(defun %token-reduction-missing-redirect-target-policy (token)
  (%make-token-reduction-diagnostic-policy
   :missing-redirection-target
   (format nil "Expected target after '~a'" (token-value token))))

(defun %token-reduction-missing-command-policy (text)
  (%make-token-reduction-diagnostic-policy
   :missing-command
   (format nil "Expected command before '~a'" text)))

(defun %token-reduction-unexpected-token-policy (token)
  (%make-token-reduction-diagnostic-policy
   :unexpected-token
   (format nil "Unexpected token: ~a" (token-value token))))

(defun %unterminated-process-substitution-token-p (value)
  (and (>= (length value) 2)
       (or (string= "<(" (subseq value 0 2))
           (string= ">(" (subseq value 0 2)))))

(defun %token-reduction-error-policy-from-token (token)
  (let ((value (token-value token)))
    (cond
      ((string= "\\" value)
       (%make-token-reduction-diagnostic-policy
        :trailing-escape
        "Trailing escape requires continuation"))
      ((%unterminated-process-substitution-token-p value)
       (%make-token-reduction-diagnostic-policy
        :unterminated-process-substitution
        "Unterminated process substitution"))
      (t
       (%make-token-reduction-diagnostic-policy
        :unterminated-quote
        "Unterminated quoted string")))))

(defun %record-missing-redirect-target (state)
  (let ((pending-redirect-token
          (%token-reduction-state-pending-redirect-token state)))
    (when pending-redirect-token
      (setf state
            (%token-reduction-state-record-diagnostic
             state
             pending-redirect-token
             (%token-reduction-missing-redirect-target-policy
              pending-redirect-token)))
      (setf state (%token-reduction-state-clear-pending-redirect state)))
    state))
