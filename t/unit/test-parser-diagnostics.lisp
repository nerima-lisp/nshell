(in-package #:nshell/test)

(describe "parser-tests"
  (it "parse-result-state-classification-is-fact-based"
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
      (expect :complete :to-be (nshell.domain.parsing:parse-result-state complete))
      (expect :empty :to-be (nshell.domain.parsing:parse-result-state empty))
      (expect :error :to-be (nshell.domain.parsing:parse-result-state errored))
      (expect :incomplete :to-be (nshell.domain.parsing::%parse-result-facts-state
               (nshell.domain.parsing::%parse-result-facts-from-result
                incomplete-error)))
      (expect (nshell.domain.parsing:parse-complete-p incomplete-error) :to-be-falsy)))

  (it "parse-result-constructors-are-internal-boundaries"
    "Parse result construction should not expose legacy unprefixed helper names."
    (expect (fboundp 'nshell.domain.parsing::make-parse-result) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::make-parse-diagnostic) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::%make-normalized-parse-result) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing::%make-parse-diagnostic) :to-be-truthy))

  (it "parse-result-values-do-not-export-raw-struct-api"
    "Parse result values should expose projections, not raw struct types or generated helpers."
    (expect (nth-value 1 (find-symbol "PARSE-RESULT" :nshell.domain.parsing)) :to-be-falsy)
    (expect (nth-value 1 (find-symbol "PARSE-DIAGNOSTIC" :nshell.domain.parsing)) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::parse-result-p) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-parse-result) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-%parse-result) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::parse-diagnostic-p) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-parse-diagnostic) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-%parse-diagnostic) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-%parse-result-facts) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::%parse-result-p) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing::%parse-diagnostic-p) :to-be-truthy))

  (it "parse-result-errors-list-is-domain-owned"
    "Parse result diagnostics should not expose mutable aggregate storage."
    (let* ((diagnostic (nshell.domain.parsing::%make-parse-diagnostic
                        :error "original" 1 2))
           (result (nshell.domain.parsing::%make-normalized-parse-result
                    nil (list diagnostic)))
           (errors (nshell.domain.parsing:parse-errors result)))
      (setf (first errors)
            (nshell.domain.parsing::%make-parse-diagnostic
             :error "mutated" 3 4))
      (expect "original" :to-equal (nshell.domain.parsing:parse-diagnostic-message
                    (first (nshell.domain.parsing:parse-errors result))))))

  (it "parse-incomplete-quote"
    (with-first-parsed-diagnostic (diagnostic result "echo 'hello")
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :incomplete t
                                :kind :unterminated-quote
                                :span-start 5
                                :span-end 11)))

  (it "parse-incomplete-continuation-operators"
    (dolist (line '("echo hello |"
                    "echo hello &&"
                    "echo hello ||"))
      (with-parsed-command-line (result line)
        (with-last-parsed-diagnostic (diagnostic result line)
          (assert-parsed-diagnostic result diagnostic
                                    :present t
                                    :incomplete t
                                    :kind :trailing-continuation)
          (expect (nshell.domain.parsing:parse-complete-p result) :to-be-falsy)))))

  (it "parse-structural-diagnostics-accumulate"
    (let ((line "if true |"))
      (with-parsed-command-line (result line)
        (let ((kinds (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                             (nshell.domain.parsing:parse-errors result))))
          (expect (nshell.domain.parsing:parse-result-incomplete result) :to-be-truthy)
          (expect (member :trailing-continuation kinds) :to-be-truthy)
          (expect (member :unclosed-block kinds) :to-be-truthy)))))

  (it "structural-diagnostics-result-projects-incomplete-and-diagnostics"
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
      (expect (nshell.domain.parsing::%structural-diagnostics-p result) :to-be-truthy)
      (expect (nshell.domain.parsing::%structural-diagnostics-incomplete-p result) :to-be-truthy)
      (expect '(:trailing-continuation :unclosed-block) :to-equal (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                         (nshell.domain.parsing::%structural-diagnostics-diagnostics
                          result)))
      (expect separator-token :to-be (nshell.domain.parsing:parse-diagnostic-token
              (first
               (nshell.domain.parsing::%structural-diagnostics-diagnostics
                result))))))

  (it "structural-diagnostics-accumulator-projects-ordered-diagnostics"
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
      (expect (nshell.domain.parsing::%structural-diagnostics-incomplete-p result) :to-be-truthy)
      (expect '(:trailing-continuation :unclosed-block) :to-equal (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                         (nshell.domain.parsing::%structural-diagnostics-diagnostics
                          result)))))

  (it "structural-diagnostics-projects-stream-input-boundary"
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
      (expect (nshell.domain.parsing::%structural-diagnostics-input-p input) :to-be-truthy)
      (expect (list command) :to-equal (nshell.domain.parsing::%structural-diagnostics-input-commands
                  input))
      (expect :pipe :to-be (nshell.domain.parsing::%structural-diagnostics-input-last-separator
               input))
      (expect separator-token :to-be (nshell.domain.parsing::%structural-diagnostics-input-last-separator-token
               input))
      (expect 9 :to-equal (nshell.domain.parsing::%structural-diagnostics-input-input-length
              input))
      (expect (nshell.domain.parsing::%structural-diagnostics-incomplete-p result) :to-be-truthy)
      (expect '(:trailing-continuation :unclosed-block) :to-equal (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                         (nshell.domain.parsing::%structural-diagnostics-diagnostics
                          result)))
      (expect separator-token :to-be (nshell.domain.parsing:parse-diagnostic-token
              (first
               (nshell.domain.parsing::%structural-diagnostics-diagnostics
                result))))))

  (it "structural-diagnostics-has-no-legacy-multiple-value-wrapper"
    "Structural diagnostics should not retain the old raw-argument multiple-value API."
    (expect (fboundp 'nshell.domain.parsing::%parse-structural-diagnostics) :to-be-falsy))

  (it "parser-internal-value-objects-have-no-copy-api"
    "Parser-internal value objects should not expose generated copy helpers."
    (expect (fboundp 'nshell.domain.parsing::copy-%command-list-components) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-%reduced-command-stream) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-%structural-diagnostics) :to-be-falsy)
    (expect (fboundp
              'nshell.domain.parsing::copy-%structural-diagnostics-accumulator) :to-be-falsy)
    (expect (fboundp
              'nshell.domain.parsing::copy-%structural-diagnostics-input) :to-be-falsy))

  (it "continuation-separator-diagnostic-uses-token-boundary"
    "Trailing continuation diagnostics should preserve separator token position."
    (let* ((token (nshell.domain.parsing:make-token :pipe "|" 5 6))
           (diagnostic
             (nshell.domain.parsing::%continuation-separator-diagnostic
              :pipe token 6)))
      (expect :trailing-continuation :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic))
      (expect "Expected command after '|'" :to-equal (nshell.domain.parsing:parse-diagnostic-message diagnostic))
      (expect 5 :to-equal (nshell.domain.parsing:parse-diagnostic-start diagnostic))
      (expect 6 :to-equal (nshell.domain.parsing:parse-diagnostic-end diagnostic))
      (expect token :to-be (nshell.domain.parsing:parse-diagnostic-token diagnostic))))

  (it "continuation-separator-diagnostic-falls-back-to-input-end"
    "Synthetic trailing continuation diagnostics should point at input end."
    (let ((diagnostic
            (nshell.domain.parsing::%continuation-separator-diagnostic
             :and nil 12)))
      (expect :trailing-continuation :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic))
      (expect "Expected command after continuation operator" :to-equal (nshell.domain.parsing:parse-diagnostic-message diagnostic))
      (expect 12 :to-equal (nshell.domain.parsing:parse-diagnostic-start diagnostic))
      (expect 12 :to-equal (nshell.domain.parsing:parse-diagnostic-end diagnostic))
      (expect (nshell.domain.parsing:parse-diagnostic-token diagnostic) :to-be-null)))

  ;; Each row parses LINE and expects the first structural diagnostic to be KIND
  ;; spanning [START, END): a leading operator/redirect has no command, a
  ;; trailing redirect has no target.
  (it-each (("| grep foo"  :missing-command             0 1)
            ("> out.txt"   :missing-command             0 1)
            ("echo >"      :missing-redirection-target  5 6))
      "flags ~S with a ~S diagnostic"
      (line kind start end)
    (with-first-parsed-diagnostic (diagnostic result line)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :kind kind
                                :span-start start
                                :span-end end)))

  (it "missing-redirect-target-policy-projects-token-diagnostic"
    "Missing redirect target diagnostics should preserve redirect token position."
    (let* ((token (nshell.domain.parsing:make-token :redirect ">" 5 6))
           (policy
             (nshell.domain.parsing::%token-reduction-missing-redirect-target-policy
              token))
           (diagnostic
             (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
      (expect :missing-redirection-target :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
               policy))
      (expect "Expected target after '>'" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                  policy))
      (expect :missing-redirection-target :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic))
      (expect "Expected target after '>'" :to-equal (nshell.domain.parsing:parse-diagnostic-message diagnostic))
      (expect 5 :to-equal (nshell.domain.parsing:parse-diagnostic-start diagnostic))
      (expect 6 :to-equal (nshell.domain.parsing:parse-diagnostic-end diagnostic))
      (expect token :to-be (nshell.domain.parsing:parse-diagnostic-token diagnostic))))

  (it "parse-redirect-before-separator-diagnostic"
    (let ((line "echo > | cat"))
      (with-parsed-diagnostic-of-kind (redirect-diagnostic result line :missing-redirection-target)
        (assert-parsed-diagnostic result redirect-diagnostic
                                  :present t
                                  :kind :missing-redirection-target
                                  :span-start 5
                                  :span-end 6))))

  (it "parse-bare-parenthesis-diagnostic"
    (let ((line "("))
      (with-first-parsed-diagnostic (diagnostic result line)
        (assert-parsed-diagnostic result diagnostic
                                  :present t
                                  :kind :unexpected-token
                                  :span-start 0
                                  :span-end 1))))

  (it "parse-trailing-backslash-is-incomplete"
    (let ((line "echo \\"))
      (with-first-parsed-diagnostic (diagnostic result line)
        (assert-parsed-diagnostic result diagnostic
                                  :present t
                                  :incomplete t
                                  :kind :trailing-escape
                                  :span-start 5
                                  :span-end 6))))

  (it "token-reduction-error-diagnostic-classifies-trailing-escape"
    "Trailing escape error tokens should map to continuation diagnostics."
    (let* ((token (nshell.domain.parsing:make-token :error "\\" 5 6))
           (policy
             (nshell.domain.parsing::%token-reduction-error-policy-from-token token))
           (diagnostic
             (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
      (expect :trailing-escape :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
               policy))
      (expect "Trailing escape requires continuation" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                  policy))
      (expect :trailing-escape :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic))
      (expect "Trailing escape requires continuation" :to-equal (nshell.domain.parsing:parse-diagnostic-message diagnostic))
      (expect 5 :to-equal (nshell.domain.parsing:parse-diagnostic-start diagnostic))
      (expect 6 :to-equal (nshell.domain.parsing:parse-diagnostic-end diagnostic))
      (expect token :to-be (nshell.domain.parsing:parse-diagnostic-token diagnostic))))

  (it "token-reduction-error-policy-projects-diagnostic-policy"
    "Error token classification should be isolated from diagnostic span projection."
    (flet ((policy-for (value)
             (nshell.domain.parsing::%token-reduction-error-policy-from-token
              (nshell.domain.parsing:make-token :error value 7 12))))
      (let ((trailing-escape (policy-for "\\"))
            (process-substitution (policy-for "<(echo ok"))
            (output-process-substitution (policy-for ">(echo ok"))
            (quote (policy-for "'hello")))
        (expect :trailing-escape :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
                 trailing-escape))
        (expect "Trailing escape requires continuation" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                    trailing-escape))
        (expect :unterminated-process-substitution :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
                 process-substitution))
        (expect "Unterminated process substitution" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                    process-substitution))
        (expect :unterminated-process-substitution :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
                 output-process-substitution))
        (expect "Unterminated process substitution" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                    output-process-substitution))
        (expect :unterminated-quote :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
                 quote))
        (expect "Unterminated quoted string" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                    quote)))))

  (it "parse-unbalanced-process-substitution-is-incomplete"
    (let ((line "cat <(echo ok"))
      (with-first-parsed-diagnostic (diagnostic result line)
        (assert-parsed-diagnostic result diagnostic
                                  :present t
                                  :incomplete t
                                  :kind :unterminated-process-substitution
                                  :span-start 4
                                  :span-end 13))))

  (it "parse-unbalanced-output-process-substitution-is-incomplete"
    (let ((line "cat >(echo ok"))
      (with-first-parsed-diagnostic (diagnostic result line)
        (assert-parsed-diagnostic result diagnostic
                                  :present t
                                  :incomplete t
                                  :kind :unterminated-process-substitution
                                  :span-start 4
                                  :span-end 13))))

  (it "token-reduction-error-diagnostic-classifies-process-substitution"
    "Unbalanced process substitution error tokens should retain token span."
    (let* ((token (nshell.domain.parsing:make-token :error "<(echo ok" 4 13))
           (policy
             (nshell.domain.parsing::%token-reduction-error-policy-from-token token))
           (diagnostic
             (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
      (expect :unterminated-process-substitution :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic))
      (expect "Unterminated process substitution" :to-equal (nshell.domain.parsing:parse-diagnostic-message diagnostic))
      (expect 4 :to-equal (nshell.domain.parsing:parse-diagnostic-start diagnostic))
      (expect 13 :to-equal (nshell.domain.parsing:parse-diagnostic-end diagnostic))
      (expect token :to-be (nshell.domain.parsing:parse-diagnostic-token diagnostic))))

  (it "token-reduction-error-diagnostic-classifies-unterminated-quote"
    "Non-special error tokens should map to unterminated quote diagnostics."
    (let* ((token (nshell.domain.parsing:make-token :error "'hello" 5 11))
           (policy
             (nshell.domain.parsing::%token-reduction-error-policy-from-token token))
           (diagnostic
             (nshell.domain.parsing::%token-reduction-diagnostic token policy)))
      (expect :unterminated-quote :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic))
      (expect "Unterminated quoted string" :to-equal (nshell.domain.parsing:parse-diagnostic-message diagnostic))
      (expect 5 :to-equal (nshell.domain.parsing:parse-diagnostic-start diagnostic))
      (expect 11 :to-equal (nshell.domain.parsing:parse-diagnostic-end diagnostic))
      (expect token :to-be (nshell.domain.parsing:parse-diagnostic-token diagnostic))))

  (it "format-parse-diagnostic-lines"
    (with-parsed-command-line (result "echo |")
      (expect '("nshell: syntax error: Expected command after '|' at column 6") :to-equal (nshell.presentation::format-parse-diagnostic-lines result)))))
