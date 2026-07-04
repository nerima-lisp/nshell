(in-package #:nshell/test)

(in-suite parser-tests)

(test parse-result-state-classification-is-fact-based
  "Parse result state should be derived from normalized result facts."
  (let* ((ast (nshell.domain.parsing:make-command-node "echo" nil))
         (diagnostic (nshell.domain.parsing::%make-parse-diagnostic
                      :missing-command "Expected command" 0 1))
         (complete (nshell.domain.parsing::%make-normalized-parse-result ast))
         (empty (nshell.domain.parsing::%make-normalized-parse-result nil))
         (errored (nshell.domain.parsing::%make-normalized-parse-result
                   nil (list diagnostic)))
         (incomplete-error
           (nshell.domain.parsing::%make-normalized-parse-result
            nil (list diagnostic) t)))
    (is (eq :complete (nshell.domain.parsing:parse-result-state complete)))
    (is (eq :empty (nshell.domain.parsing:parse-result-state empty)))
    (is (eq :error (nshell.domain.parsing:parse-result-state errored)))
    (is (eq :incomplete
            (nshell.domain.parsing::%parse-result-facts-state
             (nshell.domain.parsing::%parse-result-facts-from-result
              incomplete-error))))
    (is (not (nshell.domain.parsing:parse-complete-p incomplete-error)))))

(test parse-result-constructors-are-internal-boundaries
  "Parse result construction should not expose legacy unprefixed helper names."
  (is (not (fboundp 'nshell.domain.parsing::make-parse-result)))
  (is (not (fboundp 'nshell.domain.parsing::make-parse-diagnostic)))
  (is (fboundp 'nshell.domain.parsing::%make-normalized-parse-result))
  (is (fboundp 'nshell.domain.parsing::%make-parse-diagnostic)))

(test parse-incomplete-quote
  (with-first-parsed-diagnostic (diagnostic result "echo 'hello")
    (assert-parsed-diagnostic result diagnostic
                              :present t
                              :incomplete t
                              :kind :unterminated-quote
                              :span-start 5
                              :span-end 11)))

(test parse-incomplete-continuation-operators
  (dolist (line '("echo hello |"
                  "echo hello &&"
                  "echo hello ||"))
    (with-parsed-command-line (result line)
      (with-last-parsed-diagnostic (diagnostic result line)
        (assert-parsed-diagnostic result diagnostic
                                  :present t
                                  :incomplete t
                                  :kind :trailing-continuation)
        (is (not (nshell.domain.parsing:parse-complete-p result))
            "~s should explain the continuation point" line)))))

(test parse-structural-diagnostics-accumulate
  (let ((line "if true |"))
    (with-parsed-command-line (result line)
      (let ((kinds (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                           (nshell.domain.parsing:parse-errors result))))
        (is (nshell.domain.parsing:parse-result-incomplete result))
        (is (member :trailing-continuation kinds))
        (is (member :unclosed-block kinds))))))

(test structural-diagnostics-result-projects-incomplete-and-diagnostics
  "Structural diagnostics should be one parser-domain result, not value plumbing."
  (let* ((command (nshell.domain.parsing:make-command-node "if" '("true")))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 8 9))
         (result
           (nshell.domain.parsing::%parse-structural-diagnostics-for-input
            (nshell.domain.parsing::%make-structural-diagnostics-input
             (list command)
             :pipe
             separator-token
             9))))
    (is (nshell.domain.parsing::%structural-diagnostics-p result))
    (is (nshell.domain.parsing::%structural-diagnostics-incomplete-p result))
    (is (equal '(:trailing-continuation :unclosed-block)
               (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                       (nshell.domain.parsing::%structural-diagnostics-diagnostics
                        result))))
    (is (eq separator-token
            (nshell.domain.parsing:parse-diagnostic-token
            (first
             (nshell.domain.parsing::%structural-diagnostics-diagnostics
              result)))))))

(test structural-diagnostics-accumulator-projects-ordered-diagnostics
  "Structural diagnostics accumulation should own order and incomplete state."
  (let* ((accumulator
           (nshell.domain.parsing::%empty-structural-diagnostics-accumulator))
         (continuation
           (nshell.domain.parsing::%continuation-separator-diagnostic
            :pipe
            (nshell.domain.parsing:make-token :pipe "|" 8 9)
            9))
         (unclosed
           (nshell.domain.parsing::%unclosed-control-flow-diagnostic 9))
         (result
           (progn
             (nshell.domain.parsing::%structural-diagnostics-accumulator-add-diagnostic
              accumulator continuation :incomplete-p t)
             (nshell.domain.parsing::%structural-diagnostics-accumulator-add-diagnostic
              accumulator unclosed)
             (nshell.domain.parsing::%structural-diagnostics-from-accumulator
              accumulator))))
    (is (nshell.domain.parsing::%structural-diagnostics-incomplete-p result))
    (is (equal '(:trailing-continuation :unclosed-block)
               (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                       (nshell.domain.parsing::%structural-diagnostics-diagnostics
                        result))))))

(test structural-diagnostics-projects-stream-input-boundary
  "Parser structural diagnostics should consume one projected stream input."
  (let* ((command (nshell.domain.parsing:make-command-node "if" '("true")))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 8 9))
         (stream
           (nshell.domain.parsing::%reduced-command-stream-from-reducer-entries
            (list (list command :pipe separator-token))))
         (input
           (nshell.domain.parsing::%structural-diagnostics-input-from-stream
            stream 9))
         (result
           (nshell.domain.parsing::%parse-structural-diagnostics-for-input
            input)))
    (is (nshell.domain.parsing::%structural-diagnostics-input-p input))
    (is (equal (list command)
               (nshell.domain.parsing::%structural-diagnostics-input-commands
                input)))
    (is (eq :pipe
            (nshell.domain.parsing::%structural-diagnostics-input-last-separator
             input)))
    (is (eq separator-token
            (nshell.domain.parsing::%structural-diagnostics-input-last-separator-token
             input)))
    (is (= 9
           (nshell.domain.parsing::%structural-diagnostics-input-input-length
            input)))
    (is (nshell.domain.parsing::%structural-diagnostics-incomplete-p result))
    (is (equal '(:trailing-continuation :unclosed-block)
               (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                       (nshell.domain.parsing::%structural-diagnostics-diagnostics
                        result))))
    (is (eq separator-token
            (nshell.domain.parsing:parse-diagnostic-token
            (first
             (nshell.domain.parsing::%structural-diagnostics-diagnostics
              result)))))))

(test structural-diagnostics-has-no-legacy-multiple-value-wrapper
  "Structural diagnostics should not retain the old raw-argument multiple-value API."
  (is (not (fboundp 'nshell.domain.parsing::%parse-structural-diagnostics))))

(test continuation-separator-diagnostic-uses-token-boundary
  "Trailing continuation diagnostics should preserve separator token position."
  (let* ((token (nshell.domain.parsing:make-token :pipe "|" 5 6))
         (diagnostic
           (nshell.domain.parsing::%continuation-separator-diagnostic
            :pipe token 6)))
    (is (eq :trailing-continuation
            (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))
    (is (equal "Expected command after '|'"
               (nshell.domain.parsing:parse-diagnostic-message diagnostic)))
    (is (= 5 (nshell.domain.parsing:parse-diagnostic-start diagnostic)))
    (is (= 6 (nshell.domain.parsing:parse-diagnostic-end diagnostic)))
    (is (eq token
            (nshell.domain.parsing:parse-diagnostic-token diagnostic)))))

(test continuation-separator-diagnostic-falls-back-to-input-end
  "Synthetic trailing continuation diagnostics should point at input end."
  (let ((diagnostic
          (nshell.domain.parsing::%continuation-separator-diagnostic
           :and nil 12)))
    (is (eq :trailing-continuation
            (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))
    (is (equal "Expected command after continuation operator"
               (nshell.domain.parsing:parse-diagnostic-message diagnostic)))
    (is (= 12 (nshell.domain.parsing:parse-diagnostic-start diagnostic)))
    (is (= 12 (nshell.domain.parsing:parse-diagnostic-end diagnostic)))
    (is (null (nshell.domain.parsing:parse-diagnostic-token diagnostic)))))

(test parse-leading-operator-diagnostic
  (let ((line "| grep foo"))
    (with-first-parsed-diagnostic (diagnostic result line)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :kind :missing-command
                                :span-start 0
                                :span-end 1))))

(test parse-leading-redirect-diagnostic
  (let ((line "> out.txt"))
    (with-first-parsed-diagnostic (diagnostic result line)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :kind :missing-command
                                :span-start 0
                                :span-end 1))))

(test parse-trailing-redirect-diagnostic
  (let ((line "echo >"))
    (with-first-parsed-diagnostic (diagnostic result line)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :kind :missing-redirection-target
                                :span-start 5
                                :span-end 6))))

(test missing-redirect-target-policy-projects-token-diagnostic
  "Missing redirect target diagnostics should preserve redirect token position."
  (let* ((token (nshell.domain.parsing:make-token :redirect ">" 5 6))
         (policy
           (nshell.domain.parsing::%token-reduction-missing-redirect-target-policy
            token))
         (diagnostic
           (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
    (is (eq :missing-redirection-target
            (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
             policy)))
    (is (equal "Expected target after '>'"
               (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                policy)))
    (is (eq :missing-redirection-target
            (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))
    (is (equal "Expected target after '>'"
               (nshell.domain.parsing:parse-diagnostic-message diagnostic)))
    (is (= 5 (nshell.domain.parsing:parse-diagnostic-start diagnostic)))
    (is (= 6 (nshell.domain.parsing:parse-diagnostic-end diagnostic)))
    (is (eq token
            (nshell.domain.parsing:parse-diagnostic-token diagnostic)))))

(test parse-redirect-before-separator-diagnostic
  (let ((line "echo > | cat"))
    (with-parsed-diagnostic-of-kind (redirect-diagnostic result line :missing-redirection-target)
      (assert-parsed-diagnostic result redirect-diagnostic
                                :present t
                                :kind :missing-redirection-target
                                :span-start 5
                                :span-end 6))))

(test parse-bare-parenthesis-diagnostic
  (let ((line "("))
    (with-first-parsed-diagnostic (diagnostic result line)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :kind :unexpected-token
                                :span-start 0
                                :span-end 1))))

(test parse-trailing-backslash-is-incomplete
  (let ((line "echo \\"))
    (with-first-parsed-diagnostic (diagnostic result line)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :incomplete t
                                :kind :trailing-escape
                                :span-start 5
                                :span-end 6))))

(test token-reduction-error-diagnostic-classifies-trailing-escape
  "Trailing escape error tokens should map to continuation diagnostics."
  (let* ((token (nshell.domain.parsing:make-token :error "\\" 5 6))
         (policy
           (nshell.domain.parsing::%token-reduction-error-policy-from-token token))
         (diagnostic
           (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
    (is (eq :trailing-escape
            (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
             policy)))
    (is (equal "Trailing escape requires continuation"
               (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                policy)))
    (is (eq :trailing-escape
            (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))
    (is (equal "Trailing escape requires continuation"
               (nshell.domain.parsing:parse-diagnostic-message diagnostic)))
    (is (= 5 (nshell.domain.parsing:parse-diagnostic-start diagnostic)))
    (is (= 6 (nshell.domain.parsing:parse-diagnostic-end diagnostic)))
    (is (eq token
            (nshell.domain.parsing:parse-diagnostic-token diagnostic)))))

(test token-reduction-error-policy-projects-diagnostic-policy
  "Error token classification should be isolated from diagnostic span projection."
  (flet ((policy-for (value)
           (nshell.domain.parsing::%token-reduction-error-policy-from-token
            (nshell.domain.parsing:make-token :error value 7 12))))
    (let ((trailing-escape (policy-for "\\"))
          (process-substitution (policy-for "<(echo ok"))
          (quote (policy-for "'hello")))
      (is (eq :trailing-escape
              (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
               trailing-escape)))
      (is (equal "Trailing escape requires continuation"
                 (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                  trailing-escape)))
      (is (eq :unterminated-process-substitution
              (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
               process-substitution)))
      (is (equal "Unterminated process substitution"
                 (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                  process-substitution)))
      (is (eq :unterminated-quote
              (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
               quote)))
      (is (equal "Unterminated quoted string"
                 (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                  quote))))))

(test parse-unbalanced-process-substitution-is-incomplete
  (let ((line "cat <(echo ok"))
    (with-first-parsed-diagnostic (diagnostic result line)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :incomplete t
                                :kind :unterminated-process-substitution
                                :span-start 4
                                :span-end 13))))

(test token-reduction-error-diagnostic-classifies-process-substitution
  "Unbalanced process substitution error tokens should retain token span."
  (let* ((token (nshell.domain.parsing:make-token :error "<(echo ok" 4 13))
         (policy
           (nshell.domain.parsing::%token-reduction-error-policy-from-token token))
         (diagnostic
           (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
    (is (eq :unterminated-process-substitution
            (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))
    (is (equal "Unterminated process substitution"
               (nshell.domain.parsing:parse-diagnostic-message diagnostic)))
    (is (= 4 (nshell.domain.parsing:parse-diagnostic-start diagnostic)))
    (is (= 13 (nshell.domain.parsing:parse-diagnostic-end diagnostic)))
    (is (eq token
            (nshell.domain.parsing:parse-diagnostic-token diagnostic)))))

(test token-reduction-error-diagnostic-classifies-unterminated-quote
  "Non-special error tokens should map to unterminated quote diagnostics."
  (let* ((token (nshell.domain.parsing:make-token :error "'hello" 5 11))
         (policy
           (nshell.domain.parsing::%token-reduction-error-policy-from-token token))
         (diagnostic
           (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
    (is (eq :unterminated-quote
            (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))
    (is (equal "Unterminated quoted string"
               (nshell.domain.parsing:parse-diagnostic-message diagnostic)))
    (is (= 5 (nshell.domain.parsing:parse-diagnostic-start diagnostic)))
    (is (= 11 (nshell.domain.parsing:parse-diagnostic-end diagnostic)))
    (is (eq token
            (nshell.domain.parsing:parse-diagnostic-token diagnostic)))))

(test format-parse-diagnostic-lines
  (with-parsed-command-line (result "echo |")
    (is (equal '("nshell: syntax error: Expected command after '|' at column 6")
               (nshell.presentation::format-parse-diagnostic-lines result)))))
