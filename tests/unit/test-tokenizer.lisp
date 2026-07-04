(in-package #:nshell/test)

(def-suite tokenizer-tests
  :description "Tokenizer unit tests"
  :in nshell-tests)

(in-suite tokenizer-tests)

(defmacro with-tokenized-input ((tokens cursor incomplete) input &body body)
  (let ((result (gensym "TOKENIZATION-RESULT-")))
    `(let* ((,result (nshell.domain.parsing:tokenize ,input))
            (,tokens (nshell.domain.parsing:tokenization-result-tokens
                      ,result))
            (,cursor (nshell.domain.parsing:tokenization-result-cursor-token
                      ,result))
            (,incomplete (nshell.domain.parsing:tokenization-result-incomplete-p
                          ,result)))
       ,@body)))

(test tokenize-returns-tokenization-result-object
  (let* ((result (nshell.domain.parsing:tokenize "echo ok"))
         (tokens (nshell.domain.parsing:tokenization-result-tokens
                  result)))
    (is (nshell.domain.parsing:tokenization-result-p result))
    (is (= 2 (length tokens)))
    (is (not (nshell.domain.parsing:tokenization-result-incomplete-p
              result)))))

(test tokenization-result-token-list-is-domain-owned
  (let* ((result (nshell.domain.parsing:tokenize "echo ok"))
         (tokens (nshell.domain.parsing:tokenization-result-tokens
                  result)))
    (setf (first tokens)
          (nshell.domain.parsing:make-token :word "mutated"))
    (is (string= "echo"
                 (nshell.domain.parsing:token-value
                  (first (nshell.domain.parsing:tokenization-result-tokens
                          result)))))))

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

(test tokenizer-main-loop-dispatches-shell-boundaries
  "The tokenizer main loop must consume shell boundary characters instead of
letting word-reading stop on an unconsumed terminator."
  (dolist (ch '(#\# #\( #\) #\' #\" #\& #\| #\> #\< #\;))
    (is (nshell.domain.parsing::%tokenizer-special-dispatch-character-p ch)))
  (dolist (ch '(#\Space #\Tab #\Newline #\a #\0))
    (is (not (nshell.domain.parsing::%tokenizer-special-dispatch-character-p ch)))))

(test tokenizer-special-dispatch-route-projects-main-loop-policy
  "Special dispatch should classify route facts before handler mutation."
  (flet ((route-kind (ch)
           (let ((route (nshell.domain.parsing::%tokenizer-special-dispatch-route ch)))
             (and route
                  (nshell.domain.parsing::%tokenizer-special-dispatch-route-kind route)))))
    (is (eq :operator-separator (route-kind #\&)))
    (is (eq :operator-separator (route-kind #\<)))
    (is (eq :reader-boundary (route-kind #\#)))
    (is (eq :reader-boundary (route-kind (char "(" 0))))
    (is (eq :reader-boundary (route-kind #\")))
    (is (null (route-kind #\Space)))
    (is (null (route-kind #\Newline)))
    (is (null (route-kind nil)))))

(test tokenizer-state-constructor-is-internal-boundary
  "Tokenizer state construction should not keep an unprefixed compatibility helper."
  (is (fboundp 'nshell.domain.parsing::%make-tokenizer-state-for-input))
  (is (not (fboundp 'nshell.domain.parsing::make-tokenizer-state))))

(test tokenizer-dispatch-kind-projects-main-loop-boundaries
  "Tokenizer dispatch classification should remain separate from state mutation."
  (flet ((kind (input)
           (let ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input)))
             (nshell.domain.parsing::%tokenizer-dispatch-kind
              state
              (nshell.domain.parsing::%tokenizer-state-peek state)))))
    (is (eq :newline (kind (format nil "~%"))))
    (is (eq :whitespace (kind " ")))
    (is (eq :fd-redirect (kind "2>&1")))
    (is (eq :special (kind ";")))
    (is (eq :special (kind "# comment")))
    (is (eq :word (kind "echo")))))

(test tokenizer-left-paren-route-projects-command-substitution-policy
  "Left-paren handling should project command-substitution routing before mutation."
  (flet ((route-facts (input)
           (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                  (route (nshell.domain.parsing::%tokenizer-left-paren-route-for
                          state)))
             (is (nshell.domain.parsing::%tokenizer-left-paren-route-p route))
             (list
              (nshell.domain.parsing::%tokenizer-left-paren-route-kind route)
              (nshell.domain.parsing::%tokenizer-left-paren-route-end route)))))
    (is (equal '(:command-substitution 8) (route-facts "(echo ok)")))
    (is (equal '(:literal nil) (route-facts "()")))
    (is (equal '(:literal nil) (route-facts "(echo ok")))))

(test tokenizer-ampersand-route-projects-operator-policy
  "Ampersand handling should project operator token facts before mutation."
  (flet ((route-facts (input)
           (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                  (route (nshell.domain.parsing::%tokenizer-ampersand-route-for
                          state)))
             (is (nshell.domain.parsing::%tokenizer-ampersand-route-p route))
             (list
              (nshell.domain.parsing::%tokenizer-ampersand-route-token-type route)
              (nshell.domain.parsing::%tokenizer-ampersand-route-value route)))))
    (is (equal '(:and "&&") (route-facts "&& echo")))
    (is (equal '(:redirect "&>") (route-facts "&> out")))
    (is (equal '(:redirect "&>>") (route-facts "&>> out")))
    (is (equal '(:ampersand "&") (route-facts "& wait")))))

(test tokenizer-pipe-route-projects-operator-policy
  "Pipe handling should project separator token facts before mutation."
  (flet ((route-facts (input)
           (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                  (route (nshell.domain.parsing::%tokenizer-pipe-route-for
                          state)))
             (is (nshell.domain.parsing::%tokenizer-pipe-route-p route))
             (list
              (nshell.domain.parsing::%tokenizer-pipe-route-token-type route)
              (nshell.domain.parsing::%tokenizer-pipe-route-value route)))))
    (is (equal '(:or "||") (route-facts "|| echo")))
    (is (equal '(:pipe "|") (route-facts "| grep")))))

(test tokenizer-redirect-route-projects-operator-policy
  "Redirect handling should project redirect token facts before mutation."
  (flet ((right-route-value (input)
           (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                  (route
                    (nshell.domain.parsing::%tokenizer-right-redirect-route-for
                     state)))
             (is (nshell.domain.parsing::%tokenizer-right-redirect-route-p
                  route))
             (nshell.domain.parsing::%tokenizer-right-redirect-route-value
              route)))
         (left-route-facts (input)
           (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                  (route
                    (nshell.domain.parsing::%tokenizer-left-angle-route-for
                     state)))
             (is (nshell.domain.parsing::%tokenizer-left-angle-route-p route))
             (list
              (nshell.domain.parsing::%tokenizer-left-angle-route-kind route)
              (nshell.domain.parsing::%tokenizer-left-angle-route-value route)))))
    (is (string= ">" (right-route-value "> out")))
    (is (string= ">>" (right-route-value ">> log")))
    (is (equal '(:redirect "<") (left-route-facts "< in")))
    (is (equal '(:redirect "<<") (left-route-facts "<< EOF")))
    (is (equal '(:redirect "<<<") (left-route-facts "<<< value")))
    (is (equal '(:process-substitution nil) (left-route-facts "<(echo ok)")))))

(test tokenizer-token-extent-projects-normalized-token-boundaries
  "Token extent projection should own value normalization and end-position facts."
  (let ((empty-extent (nshell.domain.parsing::%token-extent nil nil))
        (operator-extent (nshell.domain.parsing::%token-extent 3 "&&")))
    (is (nshell.domain.parsing::%token-extent-p empty-extent))
    (is (= 0 (nshell.domain.parsing::%token-extent-start empty-extent)))
    (is (= 0 (nshell.domain.parsing::%token-extent-end empty-extent)))
    (is (string= "" (nshell.domain.parsing::%token-extent-value empty-extent)))
    (is (= 3 (nshell.domain.parsing::%token-extent-start operator-extent)))
    (is (= 5 (nshell.domain.parsing::%token-extent-end operator-extent)))
    (is (string= "&&" (nshell.domain.parsing::%token-extent-value
                       operator-extent)))))

(test tokenizer-character-boundary-projects-word-termination-data
  "Tokenizer data should classify word termination facts before loop dispatch."
  (flet ((boundary-kind (ch)
           (let ((boundary (nshell.domain.parsing::%shell-character-boundary ch)))
             (and boundary
                  (nshell.domain.parsing::%shell-character-boundary-kind boundary)))))
    (is (eq :token-separator (boundary-kind #\Space)))
    (is (eq :token-separator (boundary-kind #\|)))
    (is (eq :word-boundary-delimiter (boundary-kind #\()))
    (is (eq :word-boundary-delimiter (boundary-kind #\")))
    (is (null (boundary-kind #\a)))
    (is (null (boundary-kind nil)))
    (is (null (nshell.domain.parsing::%shell-word-boundary-p nil)))))

(test tokenizer-input-blankness-spec-projects-return-policy
  "Tokenizer data should keep blank-input return handling in an explicit spec."
  (let ((default-spec
          (nshell.domain.parsing::%shell-input-blankness-spec-from-options))
        (return-spec
          (nshell.domain.parsing::%shell-input-blankness-spec-from-options
           :include-return-p t)))
    (is (nshell.domain.parsing::%shell-input-blankness-spec-p default-spec))
    (is (not (nshell.domain.parsing::%shell-input-blankness-spec-include-return-p
              default-spec)))
    (is (nshell.domain.parsing::%shell-input-blankness-spec-include-return-p
         return-spec))
    (is (nshell.domain.parsing::%shell-input-separator-p #\Space default-spec))
    (is (not (nshell.domain.parsing::%shell-input-separator-p
              #\Return default-spec)))
    (is (nshell.domain.parsing::%shell-input-separator-p #\Return return-spec))
    (is (not (nshell.domain.parsing::%shell-input-separator-p nil return-spec)))
    (is (nshell.domain.parsing:shell-input-blank-p
         (format nil " ~c" #\Return)
         :include-return-p t))))

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

(test fd-prefixed-redirect-tokenizes-as-redirection
  (with-tokenized-input (tokens cursor incomplete) "echo err 2>&1"
    (declare (ignore cursor incomplete))
    (is (= 3 (length tokens)))
    (is (eq :redirect (nshell.domain.parsing:token-type (third tokens))))
    (is (string= "2>&1" (nshell.domain.parsing:token-value (third tokens))))))

(test fd-redirect-token-text-projects-lookahead-policy
  "FD redirect token text should be classified before tokenizer state mutation."
  (flet ((token-text (fd op next after-next)
           (nshell.domain.parsing::%fd-redirect-token-text
            fd op next after-next)))
    (let ((simple (token-text #\2 #\> nil nil))
          (append (token-text #\2 #\> #\> nil))
          (dup (token-text #\2 #\> #\& #\1))
          (input (token-text #\0 #\< nil nil)))
      (is (string= "2>"
                   (nshell.domain.parsing::%fd-redirect-token-text-value
                    simple)))
      (is (= 0
             (nshell.domain.parsing::%fd-redirect-token-text-advance-count
              simple)))
      (is (string= "2>>"
                   (nshell.domain.parsing::%fd-redirect-token-text-value
                    append)))
      (is (= 1
             (nshell.domain.parsing::%fd-redirect-token-text-advance-count
              append)))
      (is (string= "2>&1"
                   (nshell.domain.parsing::%fd-redirect-token-text-value dup)))
      (is (= 2
             (nshell.domain.parsing::%fd-redirect-token-text-advance-count
              dup)))
      (is (string= "0<"
                   (nshell.domain.parsing::%fd-redirect-token-text-value input)))
      (is (= 0
             (nshell.domain.parsing::%fd-redirect-token-text-advance-count
              input))))))

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

(test dollar-command-substitution-stays-attached-with-nested-parens
  (with-tokenized-input (tokens cursor incomplete) "echo prefix$(outer (inner))suffix"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "prefix$(outer (inner))suffix"
                 (nshell.domain.parsing:token-value (second tokens))))))

(test dollar-command-substitution-treats-quoted-parens-as-literals
  (with-tokenized-input (tokens cursor incomplete) "echo prefix$(printf \"(\")suffix"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "prefix$(printf \"(\")suffix"
                 (nshell.domain.parsing:token-value (second tokens))))))

(test fish-command-substitution-stays-attached-with-nested-parens
  (with-tokenized-input (tokens cursor incomplete) "echo prefix(outer (inner))suffix"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "prefix(outer (inner))suffix"
                 (nshell.domain.parsing:token-value (second tokens))))))

(test tokenizer-word-scan-action-projects-reader-branches
  "Word scanning should classify reader branches before mutating tokenizer state."
  (flet ((scan-action (input &optional (pos 0))
           (let ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input)))
             (setf (nshell.domain.parsing::tokenizer-state-pos state) pos)
             (let ((action
                     (nshell.domain.parsing::%tokenizer-word-scan-action-for
                      state
                      (nshell.domain.parsing::%tokenizer-state-peek state))))
               (is (nshell.domain.parsing::%tokenizer-word-scan-action-p action))
               (list (nshell.domain.parsing::%tokenizer-word-scan-action-kind action)
                     (nshell.domain.parsing::%tokenizer-word-scan-action-end action))))))
    (is (equal '(:dollar-substitution 6) (scan-action "$(echo)")))
    (is (equal '(:fish-substitution 5) (scan-action "(echo)")))
    (is (equal '(:boundary nil) (scan-action "()")))
    (is (equal '(:escape nil) (scan-action "\\x")))
    (is (equal '(:character nil) (scan-action "word")))))

(test trailing-backslash-is-incomplete
  (with-tokenized-input (tokens cursor incomplete) "echo \\"
    (declare (ignore cursor))
    (is (not (null incomplete)))
    (is (= 2 (length tokens)))
    (is (eq :error (nshell.domain.parsing:token-type (second tokens))))
    (is (= 5 (nshell.domain.parsing:token-start (second tokens))))
    (is (= 6 (nshell.domain.parsing:token-end (second tokens))))))

(test tokenizer-balanced-token-boundary-projects-prefixed-substitution-extent
  "Prefixed substitution readers should consume a projected token boundary."
  (flet ((boundary-facts (input)
           (let ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input)))
             (let ((boundary
                     (nshell.domain.parsing::%tokenizer-balanced-token-boundary-for
                      state
                      1)))
               (is (nshell.domain.parsing::%tokenizer-balanced-token-boundary-p
                    boundary))
               (list
                (nshell.domain.parsing::%tokenizer-balanced-token-boundary-substitution-end
                 boundary)
                (nshell.domain.parsing::%tokenizer-balanced-token-boundary-token-end
                 boundary))))))
    (is (equal '(9 10) (boundary-facts "<(echo ok)")))
    (is (equal '(nil 9) (boundary-facts "<(echo ok")))))

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

(test process-substitution-stays-attached-with-nested-parens
  (with-tokenized-input (tokens cursor incomplete) "cat <(outer (inner))"
    (declare (ignore cursor))
    (is (null incomplete))
    (is (= 2 (length tokens)))
    (is (eq :word (nshell.domain.parsing:token-type (second tokens))))
    (is (string= "<(outer (inner))"
                 (nshell.domain.parsing:token-value (second tokens))))))

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

(test tokenizer-double-quoted-escape-character-p-identifies-special-chars
  "Inside double quotes, only \\, \", $, ` and newline require backslash escaping."
  (flet ((esc (ch)
           (nshell.domain.parsing::%tokenizer-double-quoted-escape-character-p ch)))
    (is (esc #\\))
    (is (esc #\"))
    (is (esc #\$))
    (is (esc #\`))
    (is (esc #\Newline))
    (is (not (esc #\Space)))
    (is (not (esc #\a)))
    (is (not (esc #\!)))))
