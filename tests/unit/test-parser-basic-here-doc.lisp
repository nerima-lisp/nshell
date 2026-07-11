(in-package #:nshell/test)

(in-suite parser-tests)

(test parser-here-doc-target-replacement-is-here-doc-specific
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
    (is (equal `("cat" "<<<" "inline" "<<" ,(format nil "body~%") ">" "out")
               (mapcar #'nshell.domain.parsing:token-value updated)))
    (is (eq :single
            (nshell.domain.parsing::token-quote-style (fifth updated))))))

(test parser-here-doc-line-projects-text-position-and-newline
  "Here-doc line scanning returns one explicit line value."
  (let ((line (nshell.domain.parsing::%read-here-doc-line
               (format nil "body~%tail")
               0)))
    (is (nshell.domain.parsing::%here-doc-line-p line))
    (is (not (fboundp 'nshell.domain.parsing::copy-%here-doc-line)))
    (is (string= "body"
                 (nshell.domain.parsing::%here-doc-line-text line)))
    (is (= 5
           (nshell.domain.parsing::%here-doc-line-next-position line)))
    (is (nshell.domain.parsing::%here-doc-line-newline-p line))))

(test parser-here-doc-body-projects-body-position-and-missing-delimiter
  "Here-doc body consumption returns one explicit body value."
  (let ((body (nshell.domain.parsing::%consume-here-doc-body
               (format nil "one~%EOF~%tail")
               0
               "EOF")))
    (is (nshell.domain.parsing::%here-doc-body-p body))
    (is (not (fboundp 'nshell.domain.parsing::copy-%here-doc-body)))
    (is (string= (format nil "one~%")
                 (nshell.domain.parsing::%here-doc-body-body body)))
    (is (= 8
           (nshell.domain.parsing::%here-doc-body-next-position body)))
    (is (not
         (nshell.domain.parsing::%here-doc-body-missing-delimiter-p body)))))

(test parser-here-doc-delimiter-scan-projects-left-to-right-delimiters
  "Here-doc delimiter scanning owns accumulation order."
  (let ((scan (nshell.domain.parsing::%here-doc-delimiter-scan-add
               (nshell.domain.parsing::%here-doc-delimiter-scan-add
                (nshell.domain.parsing::%empty-here-doc-delimiter-scan)
                "EOF")
                "NEXT")))
    (is (nshell.domain.parsing::%here-doc-delimiter-scan-p scan))
    (is (not (fboundp 'nshell.domain.parsing::copy-%here-doc-delimiter-scan)))
    (is (equal '("EOF" "NEXT")
               (nshell.domain.parsing::%here-doc-delimiter-scan-result
                scan)))))

(test parser-here-doc-consumption-state-projects-fold-result
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
    (is (nshell.domain.parsing::%here-doc-consumption-state-p state))
    (is (not (fboundp 'nshell.domain.parsing::copy-%here-doc-consumption-state)))
    (is (equal (list (format nil "one~%") (format nil "two~%"))
               (nshell.domain.parsing::%here-doc-consumption-bodies
                consumption)))
    (is (= (length input)
           (nshell.domain.parsing::%here-doc-consumption-next-position
            consumption)))
    (is (not (nshell.domain.parsing::%here-doc-consumption-incomplete-p
              consumption)))))

(test parser-here-doc-consumption-projects-body-position-and-incomplete-state
  "Here-doc consumption returns one explicit domain result for tokenizer assembly."
  (let* ((consumed-prefix (format nil "one~%A~%two~%B~%"))
         (input (concatenate 'string consumed-prefix "echo tail"))
         (consumption
           (nshell.domain.parsing::%consume-here-docs-result
            input
            0
            '("A" "B"))))
    (is (nshell.domain.parsing::%here-doc-consumption-p consumption))
    (is (not (fboundp 'nshell.domain.parsing::copy-%here-doc-consumption)))
    (is (equal (list (format nil "one~%") (format nil "two~%"))
               (nshell.domain.parsing::%here-doc-consumption-bodies
                consumption)))
    (is (= (length consumed-prefix)
           (nshell.domain.parsing::%here-doc-consumption-next-position
            consumption)))
    (is (not (nshell.domain.parsing::%here-doc-consumption-incomplete-p
              consumption)))))

(test parser-here-doc-tokenization-projects-result-boundary
  "Here-doc aware tokenization returns one explicit tokenizer result."
  (let* ((input (format nil "cat << EOF~%hello~%EOF~%echo done"))
         (result (nshell.domain.parsing::%tokenize-here-doc-aware input nil))
         (tokens (nshell.domain.parsing:tokenization-result-tokens result))
         (token-values (mapcar #'nshell.domain.parsing:token-value tokens)))
    (is (nshell.domain.parsing:tokenization-result-p result))
    (is (not (nshell.domain.parsing:tokenization-result-incomplete-p
              result)))
    (is (null (nshell.domain.parsing:tokenization-result-cursor-token
               result)))
    (is (member (format nil "hello~%") token-values :test #'string=))
    (is (member "echo" token-values :test #'string=))))

(test parser-here-doc-target-replacer-consumes-bodies-after-redirects
  "The target replacer owns pending-target and body consumption state."
  (let* ((redirect (nshell.domain.parsing:make-token :redirect "<<" 0 2))
         (target (nshell.domain.parsing:make-token :word "EOF" 3 6 :single))
         (plain (nshell.domain.parsing:make-token :word "plain" 7 12))
         (replacer (nshell.domain.parsing::%make-here-doc-target-replacer
                    (list (format nil "body~%")))))
    (is (not (fboundp 'nshell.domain.parsing::copy-here-doc-target-replacer)))
    (is (eq redirect
            (nshell.domain.parsing::%here-doc-target-replacer-accept
             replacer
             redirect)))
    (let ((updated-target
            (nshell.domain.parsing::%here-doc-target-replacer-accept
             replacer
             target)))
      (is (string= (format nil "body~%")
                   (nshell.domain.parsing:token-value updated-target)))
      (is (eq :single
              (nshell.domain.parsing::token-quote-style updated-target))))
    (is (eq plain
            (nshell.domain.parsing::%here-doc-target-replacer-accept
             replacer
             plain)))))

(test parser-here-doc-target-replacer-consumes-bodies-in-order
  "Here-doc target body consumption is an explicit replacer boundary."
  (let ((replacer (nshell.domain.parsing::%make-here-doc-target-replacer
                   (list "first" "second"))))
    (is (string= "first"
                 (nshell.domain.parsing::%consume-next-here-doc-target-body
                  replacer)))
    (is (string= "second"
                 (nshell.domain.parsing::%consume-next-here-doc-target-body
                  replacer)))
    (is (null
         (nshell.domain.parsing::%consume-next-here-doc-target-body
          replacer)))))

(test parser-here-doc-target-body-cursor-projects-current-and-remaining-bodies
  "Here-doc target body cursor owns raw body-list projection."
  (let ((cursor (nshell.domain.parsing::%here-doc-target-body-cursor
                 (list "first" "second"))))
    (is (nshell.domain.parsing::%here-doc-target-body-cursor-p cursor))
    (is (not (fboundp 'nshell.domain.parsing::copy-%here-doc-target-body-cursor)))
    (is (string= "first"
                 (nshell.domain.parsing::%here-doc-target-body-cursor-body cursor)))
    (is (equal '("second")
               (nshell.domain.parsing::%here-doc-target-body-cursor-remaining-bodies
                cursor)))))
