; Token reduction: collapse flat token stream into command/separator/error triples.
(in-package #:nshell.domain.parsing)

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
       (token-quote-style cmd-token))
     (%token-reduction-state-current-cmd-fragments state))))

(defun %token-reduction-argument-from-word-token (tok)
  (%make-token-reduction-argument
   (token-value tok)
   (token-quote-style tok)
   nil
   (token-fragments tok)))

(defun %token-reduction-argument-from-redirect-token (tok)
  (%make-token-reduction-argument
   (token-value tok)
   nil
   t
   (token-fragments tok)))

(defun %token-reduction-argument-raw-value (argument)
  (make-command-arg
   (%token-reduction-argument-value argument)
   (%token-reduction-argument-quote-style argument)
   (%token-reduction-argument-syntactic-p argument)
   (%token-reduction-argument-fragments argument)))

(defun %token-reduction-word-argument (tok)
  (%token-reduction-argument-raw-value
   (%token-reduction-argument-from-word-token tok)))

(defun %token-reduction-state-append-argument (state argument)
  (%update-token-reduction-state
   state
   (current-args (cons argument (%token-reduction-state-current-args state)))))

(defun %token-reduction-state-append-word-argument (state tok)
  (%token-reduction-state-append-argument state
                                          (%token-reduction-word-argument tok)))

(defun %token-reduction-merge-argument-token (argument tok)
  (make-command-arg
   (concatenate 'string
                (command-arg-value argument)
                (token-value tok))
   nil
   (command-arg-here-doc-literal-p argument)
   (append (copy-list (command-arg-fragments argument))
           (copy-list (token-fragments tok)))))

(defun %token-reduction-merge-current-argument (state tok)
  (let ((argument (first (%token-reduction-state-current-args state))))
    (%update-token-reduction-state
     state
     (current-args
      (cons (%token-reduction-merge-argument-token argument tok)
            (rest (%token-reduction-state-current-args state)))))))

(defun %token-reduction-merge-current-command (state tok)
  (%update-token-reduction-state
   state
   (current-cmd
    (concatenate 'string
                 (%token-reduction-state-current-cmd state)
                 (token-value tok)))
   (current-cmd-fragments
    (append (copy-list (%token-reduction-state-current-cmd-fragments state))
            (copy-list (token-fragments tok))))))

(defun %token-reduction-state-append-redirect-argument (state tok)
  (%token-reduction-state-append-argument
   state
   (%token-reduction-argument-raw-value
    (%token-reduction-argument-from-redirect-token tok))))

(defun %token-reduction-state-start-command (state tok)
  (%update-token-reduction-state
   state
   (current-cmd (token-value tok))
   (current-cmd-token tok)
   (current-cmd-fragments (copy-list (token-fragments tok)))
   (last-word-token tok)))

(define-token-reduction-transition
    %token-reduction-state-clear-pending-redirect (state)
  (pending-redirect-token nil))

(defun %token-reduction-state-mark-pending-redirect (state tok)
  (%update-token-reduction-state state (pending-redirect-token tok)))

(defun %token-reduction-state-mark-pending-separator (state separator token)
  (%update-token-reduction-state
   state
   (pending-sep separator)
   (pending-sep-token token)))

(define-token-reduction-transition
    %token-reduction-state-clear-pending-separator (state)
  (pending-sep nil)
  (pending-sep-token nil))

(defun %token-reduction-command-entry-from-state (state)
  (list (%command-node-from-token-reduction-state state)
        (%token-reduction-state-pending-sep state)
        (%token-reduction-state-pending-sep-token state)))

(defun %token-reduction-state-record-command-entry (state)
  (%update-token-reduction-state
   state
   (all-cmds (cons (%token-reduction-command-entry-from-state state)
                   (%token-reduction-state-all-cmds state)))))

(defun %token-reduction-state-clear-command-context (state)
  (%update-token-reduction-state
   (%token-reduction-state-clear-pending-separator
    (%token-reduction-state-clear-pending-redirect state))
   (current-cmd nil)
   (current-cmd-token nil)
   (current-cmd-fragments nil)
   (last-word-token nil)
   (current-args '())))

(defun %flush-token-reduction-command (state)
  (when (%token-reduction-state-current-cmd state)
    (setf state (%record-missing-redirect-target state))
    (setf state (%token-reduction-state-record-command-entry state))
    (setf state (%token-reduction-state-clear-command-context state)))
  state)

(defun %record-token-reduction-separator (state separator token)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (setf state (%record-missing-redirect-target state))
        (setf state (%token-reduction-state-mark-pending-separator state separator token))
        (%flush-token-reduction-command state))
      (unless (eq (token-type token) :newline)
        (%token-reduction-state-record-diagnostic
         state
         token
         (%token-reduction-missing-command-policy
          (%separator-text separator))))))

(defun %token-reduction-word (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (if (and (%token-reduction-state-last-word-token state)
                 (= (token-end (%token-reduction-state-last-word-token state))
                    (token-start tok)))
            (if (%token-reduction-state-current-args state)
                (setf state (%token-reduction-merge-current-argument state tok))
                (setf state (%token-reduction-merge-current-command state tok)))
            (setf state (%token-reduction-state-append-word-argument state tok)))
        (setf state (%token-reduction-state-clear-pending-redirect state))
        (%update-token-reduction-state state (last-word-token tok)))
      (%token-reduction-state-start-command state tok)))

(defun %token-reduction-redirect (state tok)
  (setf state (%update-token-reduction-state state (last-word-token nil)))
  (if (%token-reduction-state-current-cmd state)
      (progn
        (setf state (%record-missing-redirect-target state))
        (setf state (%token-reduction-state-append-redirect-argument state tok))
        (unless (%redirect-token-targetless-p tok)
          (setf state (%token-reduction-state-mark-pending-redirect state tok)))
        state)
      (%token-reduction-state-record-diagnostic
       state
       tok
       (%token-reduction-missing-command-policy (token-value tok)))))

(defun %token-reduction-error (state tok)
  (setf state (%update-token-reduction-state state (last-word-token nil)))
  (%token-reduction-state-record-diagnostic
   state
   tok
   (%token-reduction-error-policy-from-token tok)))

(defun %token-reduction-separator (state tok)
  (setf state (%update-token-reduction-state state (last-word-token nil)))
  (let ((separator (%separator-from-token-type (token-type tok))))
    (if separator
        (progn
          (when (and (eq (token-type tok) :pipe)
                     (string= (token-value tok) "|&")
                     (%token-reduction-state-current-cmd state))
            (setf state
                  (%token-reduction-state-append-argument
                   state
                   (make-command-arg "2>&1"))))
          (%record-token-reduction-separator state separator tok))
        (%token-reduction-state-record-diagnostic
         state
         tok
         (%token-reduction-unexpected-token-policy tok)))))

(defun %reduce-token (state tok)
  (case (token-type tok)
    (:word (%token-reduction-word state tok))
    (:redirect (%token-reduction-redirect state tok))
    (:error (%token-reduction-error state tok))
    (t (%token-reduction-separator state tok))))

(defun %token-reduction-state-from-tokens (tokens)
  (let ((state (reduce #'%reduce-token
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
