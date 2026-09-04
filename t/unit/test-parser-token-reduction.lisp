(in-package #:nshell/test)

(describe "parser-token-reduction-tests"
+  (it "token-reduction-error-policy-classifies-terminal-errors"
    "Terminal token forms map to stable domain diagnostic kinds."
    (flet ((policy-for (value)
             (nshell.domain.parsing::%token-reduction-error-policy-from-token
              (nshell.domain.parsing:make-token :error value 0 (length value)))))
      (let ((escape-policy (policy-for "\\"))
            (input-policy (policy-for "<("))
            (output-policy (policy-for ">("))
            (quote-policy (policy-for "unterminated")))
        (expect :trailing-escape
                :to-be
                (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind escape-policy))
        (expect :unterminated-process-substitution
                :to-be
                (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind input-policy))
        (expect :unterminated-process-substitution
                :to-be
                (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind output-policy))
        (expect :unterminated-quote
                :to-be
                (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind quote-policy)))))

  (it "token-reduction-process-substitution-boundary-is-exact"
    "Only the two process-substitution prefixes are classified as such."
    (expect (nshell.domain.parsing::%unterminated-process-substitution-token-p "<(")
            :to-be-truthy)
    (expect (nshell.domain.parsing::%unterminated-process-substitution-token-p ">(")
            :to-be-truthy)
    (expect (nshell.domain.parsing::%unterminated-process-substitution-token-p "<")
            :to-be-falsy)
    (expect (nshell.domain.parsing::%unterminated-process-substitution-token-p "$(")
            :to-be-falsy))

  (it "token-reduction-covers-direct-state-transitions"
    "Reducer transitions preserve command, argument, redirect, and diagnostic invariants."
    (let* ((command (nshell.domain.parsing:make-token :word "ec" 0 2))
           (command-tail (nshell.domain.parsing:make-token :word "ho" 2 4))
           (argument (nshell.domain.parsing:make-token :word "ok" 5 7))
           (argument-tail (nshell.domain.parsing:make-token :word "!" 7 8))
           (redirect (nshell.domain.parsing:make-token :redirect ">" 9 10))
           (targetless (nshell.domain.parsing:make-token :redirect "2>&1" 11 15))
           (state (nshell.domain.parsing::%make-token-reduction-state)))
      (nshell.domain.parsing::%token-reduction-word state command)
      (nshell.domain.parsing::%token-reduction-word state command-tail)
      (nshell.domain.parsing::%token-reduction-word state argument)
      (nshell.domain.parsing::%token-reduction-word state argument-tail)
      (nshell.domain.parsing::%token-reduction-redirect state redirect)
      (expect (nshell.domain.parsing::%token-reduction-state-pending-redirect-token state)
              :to-be redirect)
      (nshell.domain.parsing::%token-reduction-redirect state targetless)
      (expect (nshell.domain.parsing::%token-reduction-state-pending-redirect-token state)
              :to-be-null)
      (expect "echo" :to-equal (nshell.domain.parsing::%token-reduction-state-current-cmd state))
      (expect '("2>&1" ">" "ok!") :to-equal
              (mapcar #'nshell.domain.parsing:arg-value
                      (nshell.domain.parsing::%token-reduction-state-current-args state)))
      (nshell.domain.parsing::%token-reduction-error
       state
       (nshell.domain.parsing:make-token :error "unterminated" 16 28))
      (expect 2 :to-equal (length (nshell.domain.parsing::%token-reduction-state-errors state))))))

  (it "token-reduction-reports-standalone-unexpected-tokens"
    "Tokens without a command are diagnosed without creating command entries."
    (let* ((state (nshell.domain.parsing::%make-token-reduction-state))
           (token (nshell.domain.parsing:make-token :unknown "@" 0 1)))
      (nshell.domain.parsing::%token-reduction-separator state token)
      (expect (nshell.domain.parsing::%token-reduction-state-current-cmd state) :to-be-null)
      (expect 1 :to-equal (length (nshell.domain.parsing::%token-reduction-state-errors state)))
      (expect :unexpected-token
              :to-be
              (nshell.domain.parsing:parse-diagnostic-kind
               (first (nshell.domain.parsing::%token-reduction-state-errors state))))))

  (it "token-reduction-normalizes-pipe-and-stderr"
    "Pipe-and-stderr shares the ordinary pipeline AST with an explicit redirect."
    (let* ((state (nshell.domain.parsing::%make-token-reduction-state))
           (command (nshell.domain.parsing:make-token :word "echo" 0 4))
           (pipe-and-stderr (nshell.domain.parsing:make-token :pipe "|&" 5 7)))
      (nshell.domain.parsing::%token-reduction-word state command)
      (nshell.domain.parsing::%token-reduction-separator state pipe-and-stderr)
      (expect '("2>&1") :to-equal
              (mapcar #'nshell.domain.parsing:arg-value
                      (nshell.domain.parsing:command-node-args
                       (first (first (nshell.domain.parsing::%token-reduction-state-all-cmds state))))))
      (expect :pipe :to-be
              (second (first (nshell.domain.parsing::%token-reduction-state-all-cmds state))))))
