(in-package #:nshell/test)

(describe "parser-tests"
  (it "parser-here-doc-target-replacement-is-here-doc-specific"
    "Here-doc body replacement is limited to << target words."
    (let* ((tokens (list (nshell.domain.parsing:make-token :word "cat" 0 3)
                         (nshell.domain.parsing:make-token :redirect "<<<" 4 7)
                         (nshell.domain.parsing:make-token :word "inline" 8 14)
                         (nshell.domain.parsing:make-token :redirect "<<" 15 17)
                         (nshell.domain.parsing:make-token :word "EOF" 18 21 :single)
                         (nshell.domain.parsing:make-token :redirect ">" 22 23)
                         (nshell.domain.parsing:make-token :word "out" 24 27)))
           (updated (nshell.domain.parsing::%replace-here-doc-targets
                     tokens
                     (list (format nil "body~%")))))
      (expect `("cat" "<<<" "inline" "<<" ,(format nil "body~%") ">" "out") :to-equal (mapcar #'nshell.domain.parsing:token-value updated))
      (expect :single :to-be (nshell.domain.parsing::token-quote-style (fifth updated)))))

  (it "parser-command-node-marks-quoted-here-document-targets"
    "Quoted here-document delimiters retain a literal-body marker in the AST."
    (let* ((quoted (nshell.domain.parsing:make-command-node
                    "cat"
                    (list (nshell.domain.parsing:make-command-arg "<<")
                          (nshell.domain.parsing:make-command-arg "EOF" :double))))
           (plain (nshell.domain.parsing:make-command-node
                   "cat"
                   (list (nshell.domain.parsing:make-command-arg "<<")
                         (nshell.domain.parsing:make-command-arg "EOF"))))
           (quoted-target (second (nshell.domain.parsing:command-node-args quoted)))
           (plain-target (second (nshell.domain.parsing:command-node-args plain))))
      (expect t :to-be (nshell.domain.parsing:arg-here-doc-literal-p quoted-target))
      (expect :double :to-be (nshell.domain.parsing:arg-quote-style quoted-target))
      (expect nil :to-be (nshell.domain.parsing:arg-here-doc-literal-p plain-target))))

  (it "parser-here-doc-line-projects-text-position-and-newline"
    "Here-doc line scanning returns one explicit line value."
    (let ((line (nshell.domain.parsing::%read-here-doc-line
                 (format nil "body~%tail")
                 0)))
      (expect (nshell.domain.parsing::%here-doc-line-p line) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%here-doc-line) :to-be-falsy)
      (expect "body" :to-equal (nshell.domain.parsing::%here-doc-line-text line))
      (expect 5 :to-equal (nshell.domain.parsing::%here-doc-line-next-position line))
      (expect (nshell.domain.parsing::%here-doc-line-newline-p line) :to-be-truthy)))

  (it "parser-here-doc-body-projects-body-position-and-missing-delimiter"
    "Here-doc body consumption returns one explicit body value."
    (let ((body (nshell.domain.parsing::%consume-here-doc-body
                 (format nil "one~%EOF~%tail")
                 0
                 "EOF")))
      (expect (nshell.domain.parsing::%here-doc-body-p body) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%here-doc-body) :to-be-falsy)
      (expect (format nil "one~%") :to-equal (nshell.domain.parsing::%here-doc-body-body body))
      (expect 8 :to-equal (nshell.domain.parsing::%here-doc-body-next-position body))
      (expect (nshell.domain.parsing::%here-doc-body-missing-delimiter-p body) :to-be-falsy))
  (it "parser-here-doc-body-strips-leading-tabs-for-tabbed-delimiter"
    "Tabbed here-document bodies normalize leading tabs before delimiter matching."
    (let ((body (nshell.domain.parsing::%consume-here-doc-body
                 (format nil "~c~cbody~%~cEOF~%tail"
                         #\Tab #\Tab #\Tab)
                 0
                 "EOF"
                 t)))
      (expect (format nil "body~%")
              :to-equal (nshell.domain.parsing::%here-doc-body-body body))
      (expect 12 :to-equal (nshell.domain.parsing::%here-doc-body-next-position body))
      (expect (nshell.domain.parsing::%here-doc-body-missing-delimiter-p body)
              :to-be-falsy)))

  (it "parser-here-doc-covers-terminal-and-incomplete-boundaries"
    "Here-document scanning preserves terminal cursors and missing delimiters."
    (let* ((terminal-line (nshell.domain.parsing::%read-here-doc-line "tail" 0))
           (empty-body (nshell.domain.parsing::%consume-here-doc-body "" 0 "EOF"))
           (partial (nshell.domain.parsing::%consume-here-docs-result
                     (format nil "one~%A~%two")
                     0
                     '("A" "B"))))
      (expect "tail" :to-equal (nshell.domain.parsing::%here-doc-line-text terminal-line))
      (expect 4 :to-equal (nshell.domain.parsing::%here-doc-line-next-position terminal-line))
      (expect nil :to-be (nshell.domain.parsing::%here-doc-line-newline-p terminal-line))
      (expect "" :to-equal (nshell.domain.parsing::%here-doc-body-body empty-body))
      (expect 0 :to-equal (nshell.domain.parsing::%here-doc-body-next-position empty-body))
      (expect t :to-be (nshell.domain.parsing::%here-doc-body-missing-delimiter-p empty-body))
      (expect (list (format nil "one~%"))
              :to-equal (nshell.domain.parsing::%here-doc-consumption-bodies partial))
      (expect t :to-be (nshell.domain.parsing::%here-doc-consumption-incomplete-p partial))))

  (it "parser-here-doc-covers-empty-tail-and-redirect-metadata"
    "Here-document metadata and blank tails remain explicit at the tokenizer boundary."
    (let* ((redirect (nshell.domain.parsing:make-token :redirect "<<-" 0 3))
           (target (nshell.domain.parsing:make-token :word "EOF" 4 7))
           (tokens (list redirect target))
           (result (nshell.domain.parsing::%tokenize-here-doc-tail "   " 3 tokens nil nil)))
      (expect '(("EOF" . t))
              :to-equal (nshell.domain.parsing::%here-doc-delimiters tokens t))
      (expect tokens :to-equal (nshell.domain.parsing:tokenization-result-tokens result))
      (expect nil :to-be (nshell.domain.parsing:tokenization-result-incomplete-p result))))

  (it "parser-here-doc-delimiter-scan-projects-left-to-right-delimiters"
    "Here-doc delimiter scanning owns accumulation order."
    (let ((scan (nshell.domain.parsing::%here-doc-delimiter-scan-add
                 (nshell.domain.parsing::%here-doc-delimiter-scan-add
                  (nshell.domain.parsing::%empty-here-doc-delimiter-scan)
                  "EOF")
                  "NEXT")))
      (expect (nshell.domain.parsing::%here-doc-delimiter-scan-p scan) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%here-doc-delimiter-scan) :to-be-falsy)
      (expect '("EOF" "NEXT") :to-equal (nshell.domain.parsing::%here-doc-delimiter-scan-result
                  scan))))

  (it "parser-here-doc-consumption-state-projects-fold-result"
    "Here-doc consumption state owns body accumulation and cursor movement."
    (let* ((input (format nil "one~%A~%two~%B~%"))
           (state
             (nshell.domain.parsing::%here-doc-consumption-state-consume-delimiter
              input
              (nshell.domain.parsing::%here-doc-consumption-state-consume-delimiter
               input
               (nshell.domain.parsing::%empty-here-doc-consumption-state 0)
               "A")
              "B"))
           (consumption
             (nshell.domain.parsing::%here-doc-consumption-from-state state)))
      (expect (nshell.domain.parsing::%here-doc-consumption-state-p state) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%here-doc-consumption-state) :to-be-falsy)
      (expect (list (format nil "one~%") (format nil "two~%")) :to-equal (nshell.domain.parsing::%here-doc-consumption-bodies
                  consumption))
      (expect (length input) :to-equal (nshell.domain.parsing::%here-doc-consumption-next-position
              consumption))
      (expect (nshell.domain.parsing::%here-doc-consumption-incomplete-p
                consumption) :to-be-falsy)))

  (it "parser-here-doc-consumption-projects-body-position-and-incomplete-state"
    "Here-doc consumption returns one explicit domain result for tokenizer assembly."
    (let* ((consumed-prefix (format nil "one~%A~%two~%B~%"))
           (input (concatenate 'string consumed-prefix "echo tail"))
           (consumption
             (nshell.domain.parsing::%consume-here-docs-result
              input
              0
              '("A" "B"))))
      (expect (nshell.domain.parsing::%here-doc-consumption-p consumption) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%here-doc-consumption) :to-be-falsy)
      (expect (list (format nil "one~%") (format nil "two~%")) :to-equal (nshell.domain.parsing::%here-doc-consumption-bodies
                  consumption))
      (expect (length consumed-prefix) :to-equal (nshell.domain.parsing::%here-doc-consumption-next-position
              consumption))
      (expect (nshell.domain.parsing::%here-doc-consumption-incomplete-p
                consumption) :to-be-falsy)))

  (it "parser-here-doc-tokenization-projects-result-boundary"
    "Here-doc aware tokenization returns one explicit tokenizer result."
    (let* ((input (format nil "cat << EOF~%hello~%EOF~%echo done"))
           (result (nshell.domain.parsing::%tokenize-here-doc-aware input nil))
           (tokens (nshell.domain.parsing:tokenization-result-tokens result))
           (token-values (mapcar #'nshell.domain.parsing:token-value tokens)))
      (expect (nshell.domain.parsing:tokenization-result-p result) :to-be-truthy)
      (expect (nshell.domain.parsing:tokenization-result-incomplete-p
                result) :to-be-falsy)
      (expect (nshell.domain.parsing:tokenization-result-cursor-token
                 result) :to-be-null)
      (expect (member (format nil "hello~%") token-values :test #'string=) :to-be-truthy)
      (expect (member "echo" token-values :test #'string=) :to-be-truthy)))
  (it "parser-here-doc-tabbed-tokenization-strips-leading-tabs"
    "Tab-stripping here-document tokenization removes tabs from body and delimiter lines."
    (let* ((input (format nil "cat <<- EOF~%~cinline-doc~%~cEOF~%echo done"
                          #\Tab #\Tab))
           (result (nshell.domain.parsing::%tokenize-here-doc-aware input nil))
           (tokens (nshell.domain.parsing:tokenization-result-tokens result))
           (token-values (mapcar #'nshell.domain.parsing:token-value tokens)))
      (expect (member (format nil "inline-doc~%") token-values :test #'string=)
              :to-be-truthy)
      (expect (member "echo" token-values :test #'string=) :to-be-truthy)
      (expect (member (format nil "~cinline-doc~%" #\Tab)
                      token-values
                      :test #'string=)
              :to-be-falsy)))

  (it "parser-here-doc-target-replacer-consumes-bodies-after-redirects"
    "The target replacer owns pending-target and body consumption state."
    (let* ((redirect (nshell.domain.parsing:make-token :redirect "<<" 0 2))
           (target (nshell.domain.parsing:make-token :word "EOF" 3 6 :single))
           (plain (nshell.domain.parsing:make-token :word "plain" 7 12))
           (replacer (nshell.domain.parsing::%make-here-doc-target-replacer
                      (list (format nil "body~%")))))
      (expect (fboundp 'nshell.domain.parsing::copy-here-doc-target-replacer) :to-be-falsy)
      (expect redirect :to-be (nshell.domain.parsing::%here-doc-target-replacer-accept
               replacer
               redirect))
      (let ((updated-target
              (nshell.domain.parsing::%here-doc-target-replacer-accept
               replacer
               target)))
        (expect (format nil "body~%") :to-equal (nshell.domain.parsing:token-value updated-target))
        (expect :single :to-be (nshell.domain.parsing::token-quote-style updated-target)))
      (expect plain :to-be (nshell.domain.parsing::%here-doc-target-replacer-accept
               replacer
               plain))))

  (it "parser-here-doc-target-replacer-consumes-bodies-in-order"
    "Here-doc target body consumption is an explicit replacer boundary."
    (let ((replacer (nshell.domain.parsing::%make-here-doc-target-replacer
                     (list "first" "second"))))
      (expect "first" :to-equal (nshell.domain.parsing::%consume-next-here-doc-target-body
                    replacer))
      (expect "second" :to-equal (nshell.domain.parsing::%consume-next-here-doc-target-body
                    replacer))
      (expect (nshell.domain.parsing::%consume-next-here-doc-target-body
            replacer) :to-be-null)))

  (it "parser-here-doc-target-body-cursor-projects-current-and-remaining-bodies"
    "Here-doc target body cursor owns raw body-list projection."
    (let ((cursor (nshell.domain.parsing::%here-doc-target-body-cursor
                   (list "first" "second"))))
      (expect (nshell.domain.parsing::%here-doc-target-body-cursor-p cursor) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%here-doc-target-body-cursor) :to-be-falsy)
      (expect "first" :to-equal (nshell.domain.parsing::%here-doc-target-body-cursor-body cursor))
      (expect '("second") :to-equal (nshell.domain.parsing::%here-doc-target-body-cursor-remaining-bodies
                  cursor))))))
