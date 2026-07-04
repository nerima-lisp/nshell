(in-package #:nshell/test)

(in-suite parser-tests)

(test pbt-tokenizer-roundtrip
  "Generated commands tokenize and parse without error (property test)"
  (for-all-property (:trials 50) ((cmd (gen-shell-command :min-words 2)))
    (let* ((tokenization (nshell.domain.parsing:tokenize cmd))
           (tokens (nshell.domain.parsing:tokenization-result-tokens
                    tokenization))
           (incomplete (nshell.domain.parsing:tokenization-result-incomplete-p
                        tokenization)))
      (is (not incomplete) "Generated command ~s should not be incomplete" cmd)
      (is (consp tokens) "Generated command ~s should produce tokens" cmd))))

(test pbt-parse-roundtrip
  "Generated commands parse without error (property test)"
  (for-all-property (:trials 50) ((cmd (gen-shell-command :min-words 2)))
    (with-complete-command-line (result ast cmd)
      (declare (ignore result))
      (is (not (null ast))
          "Generated command ~s should produce AST" cmd))))

(test pbt-parser-generated-pipelines-parse-completely
  "Generated shell pipelines parse completely and produce an AST."
  (for-all-property (:trials 50) ((pipeline (gen-shell-pipeline)))
    (with-complete-command-line (result ast pipeline)
      (declare (ignore result))
      (is (not (null ast))
          "Generated pipeline ~s should produce AST" pipeline))))

(test pbt-parser-diagnostic-spans-stay-in-bounds
  "Generated invalid continuations report diagnostics inside the input span."
  (for-all-property (:trials 50) ((pipeline (gen-shell-pipeline)))
    (let ((line (format nil "~a |" pipeline)))
      (with-parsed-command-line (result line)
        (is (nshell.domain.parsing:parse-result-incomplete result)
            "Generated invalid pipeline ~s should require continuation" line)
        (assert-all-parsed-diagnostics-within-input result line)))))

(test shell-assignment-word-p
  "Shell assignment words are detected independently of completion/history."
  (is (nshell.domain.parsing:shell-assignment-word-p "FOO=bar"))
  (is (nshell.domain.parsing:shell-assignment-word-p "PATH=/bin:/usr/bin"))
  (is (not (nshell.domain.parsing:shell-assignment-word-p "git")))
  (is (not (nshell.domain.parsing:shell-assignment-word-p "FOO-bar"))))

(test shell-separator-predicates
  "Shell separator predicates share the same domain character sets."
  (dolist (ch '(#\Space #\Tab #\Newline))
    (is (nshell.domain.parsing:shell-word-separator-p ch)))
  (dolist (ch '(#\| #\; #\& #\< #\>))
    (is (nshell.domain.parsing:shell-operator-separator-p ch))
    (is (nshell.domain.parsing:shell-token-separator-p ch)))
  (is (not (nshell.domain.parsing:shell-word-separator-p #\|)))
  (is (not (nshell.domain.parsing:shell-operator-separator-p #\Space)))
  (is (not (nshell.domain.parsing:shell-token-separator-p #\a))))

(test shell-input-blank-p
  "Blank command input follows shell token separator rules."
  (is (nshell.domain.parsing:shell-input-blank-p " 	|;&<>"))
  (is (nshell.domain.parsing:shell-input-blank-p
       (format nil " ~c" #\Return)
       :include-return-p t))
  (is (not (nshell.domain.parsing:shell-input-blank-p
            (format nil " ~c" #\Return))))
  (is (not (nshell.domain.parsing:shell-input-blank-p " echo"))))

(test shell-command-separator-token-p
  "Command separator tokens are classified in the parsing domain."
  (dolist (type '(:pipe :and :or :semicolon :newline :ampersand))
    (is (nshell.domain.parsing:shell-command-separator-token-p
         (nshell.domain.parsing:make-token type ""))))
  (is (not (nshell.domain.parsing:shell-command-separator-token-p
            (nshell.domain.parsing:make-token :redirect ">"))))
  (is (not (nshell.domain.parsing:shell-command-separator-token-p
            (nshell.domain.parsing:make-token :word "git")))))
