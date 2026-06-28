(in-package #:nshell/test)

(def-suite tokenizer-tests
  :description "Tokenizer unit tests"
  :in nshell-tests)

(in-suite tokenizer-tests)

(defmacro with-tokenized-input ((tokens cursor incomplete) input &body body)
  `(multiple-value-bind (,tokens ,cursor ,incomplete)
       (nshell.domain.parsing:tokenize ,input)
     ,@body))

(test simple-command
  (with-tokenized-input (tokens cursor incomplete) "ls -la"
    (declare (ignore cursor incomplete))
    (is (= 2 (length tokens)))
    (is (string= "ls" (nshell.domain.parsing:token-value (first tokens))))))

(test pipeline
  (with-tokenized-input (tokens cursor incomplete) "ls | grep foo"
    (declare (ignore cursor incomplete))
    (is (= 4 (length tokens)))
    (is (eq :pipe (nshell.domain.parsing:token-type (second tokens))))))

(test newline-separates-commands
  (with-tokenized-input (tokens cursor incomplete) (format nil "echo one~%echo two")
    (declare (ignore cursor incomplete))
    (is (= 5 (length tokens)))
    (is (eq :newline (nshell.domain.parsing:token-type (third tokens))))
    (is (string= (string #\Newline)
                 (nshell.domain.parsing:token-value (third tokens))))))

(test redirect
  (with-tokenized-input (tokens cursor incomplete) "echo hello > file.txt"
    (declare (ignore cursor incomplete))
    (is (eq :redirect (nshell.domain.parsing:token-type (third tokens))))))

(test double-quoted-string
  (with-tokenized-input (tokens cursor incomplete) "echo \"hello world\""
    (declare (ignore cursor incomplete))
    (is (string= "hello world" (nshell.domain.parsing:token-value (second tokens))))))

(test double-quoted-backslash-before-space-is-literal
  (with-tokenized-input (tokens cursor incomplete) "echo \"my\\ file\""
    (declare (ignore cursor incomplete))
    (is (= 2 (length tokens)))
    (is (string= "my\\ file" (nshell.domain.parsing:token-value (second tokens))))))

(test escaped-space-word
  (with-tokenized-input (tokens cursor incomplete) "echo hello\\ world"
    (declare (ignore cursor incomplete))
    (is (= 2 (length tokens)))
    (is (string= "hello world" (nshell.domain.parsing:token-value (second tokens))))))

(test hash-in-word-remains-literal
  (with-tokenized-input (tokens cursor incomplete) "echo foo#bar"
    (declare (ignore cursor incomplete))
    (is (= 2 (length tokens)))
    (is (string= "foo#bar" (nshell.domain.parsing:token-value (second tokens))))))

(test hash-at-boundary-starts-comment
  (with-tokenized-input (tokens cursor incomplete) "echo foo #bar"
    (declare (ignore cursor incomplete))
    (is (= 2 (length tokens)))
    (is (string= "foo" (nshell.domain.parsing:token-value (second tokens))))))

(test incomplete-quote
  (with-tokenized-input (tokens cursor incomplete) "echo 'hello"
    (declare (ignore tokens cursor))
    (is (not (null incomplete)))))

(test append-redirect
  (with-tokenized-input (tokens cursor incomplete) "echo >> log"
    (declare (ignore cursor incomplete))
    (is (string= ">>" (nshell.domain.parsing:token-value (second tokens))))))

(test single-redirect-at-end
  (with-tokenized-input (tokens cursor incomplete) ">"
    (declare (ignore cursor incomplete))
    (is (= 1 (length tokens)))
    (is (eq :redirect (nshell.domain.parsing:token-type (first tokens))))
    (is (string= ">" (nshell.domain.parsing:token-value (first tokens))))))

(test here-string-redirect
  (with-tokenized-input (tokens cursor incomplete) "cat <<< hello"
    (declare (ignore cursor incomplete))
    (is (= 3 (length tokens)))
    (is (eq :redirect (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "<<<" (nshell.domain.parsing:token-value (second tokens))))))

(test here-document-redirect
  (with-tokenized-input (tokens cursor incomplete) "cat << EOF"
    (declare (ignore cursor incomplete))
    (is (= 3 (length tokens)))
    (is (eq :redirect (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "<<" (nshell.domain.parsing:token-value (second tokens))))))

(test bare-parentheses-tokenize-with-progress
  (with-tokenized-input (tokens cursor incomplete) "()"
    (declare (ignore cursor incomplete))
    (is (= 2 (length tokens)))
    (is (eq :lparen (nshell.domain.parsing:token-type (first tokens))))
    (is (eq :rparen (nshell.domain.parsing:token-type (second tokens))))))

(test command-substitution-tokenizes-as-word-when-balanced
  (with-tokenized-input (tokens cursor incomplete) "echo (echo ok)"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "(echo ok)" (nshell.domain.parsing:token-value (second tokens))))))

(test command-substitution-stays-attached-inside-word
  (with-tokenized-input (tokens cursor incomplete) "echo prefix=(echo ok).txt"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "prefix=(echo ok).txt"
                 (nshell.domain.parsing:token-value (second tokens))))))

(test trailing-backslash-is-incomplete
  (with-tokenized-input (tokens cursor incomplete) "echo \\"
    (declare (ignore cursor))
    (is (not (null incomplete)))
    (is (= 2 (length tokens)))
    (is (eq :error (nshell.domain.parsing:token-type (second tokens))))
    (is (= 5 (nshell.domain.parsing:token-start (second tokens))))
    (is (= 6 (nshell.domain.parsing:token-end (second tokens))))))

(test process-substitution-tokenizes-as-word-when-balanced
  (with-tokenized-input (tokens cursor incomplete) "cat <(echo ok)"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "<(echo ok)" (nshell.domain.parsing:token-value (second tokens))))))

(test process-substitution-treats-quoted-parens-as-literals
  (with-tokenized-input (tokens cursor incomplete) "cat <(printf \"(\")"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "<(printf \"(\")" (nshell.domain.parsing:token-value (second tokens))))))

(test unbalanced-process-substitution-is-incomplete-error-token
  (with-tokenized-input (tokens cursor incomplete) "cat <(echo ok"
    (declare (ignore cursor))
    (is (not (null incomplete)))
    (is (= 2 (length tokens)))
    (is (eq :error (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "<(echo ok" (nshell.domain.parsing:token-value (second tokens))))
    (is (= 4 (nshell.domain.parsing:token-start (second tokens))))
    (is (= 13 (nshell.domain.parsing:token-end (second tokens))))))

(test empty-input
  (with-tokenized-input (tokens cursor incomplete) ""
    (declare (ignore cursor incomplete))
    (is (null tokens))))

(test pbt-tokenizer-spans-are-monotonic-and-in-bounds
  "Token spans are monotonic and remain within the generated input bounds."
  (for-all-property (:trials 50) ((input (gen-shell-pipeline)))
    (with-tokenized-input (tokens cursor incomplete) input
      (declare (ignore cursor incomplete))
      (is (loop with previous-end = 0
                for token in tokens
                for start = (nshell.domain.parsing:token-start token)
                for end = (nshell.domain.parsing:token-end token)
                always (and (<= 0 start end (length input))
                            (<= previous-end start))
                do (setf previous-end end))
          "Tokenizer produced non-monotonic or out-of-bounds spans for ~s"
          input))))
