(in-package #:nshell/test)

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

(describe "tokenizer-tests"
  (it "tokenize-returns-tokenization-result-object"
    (let* ((result (nshell.domain.parsing:tokenize "echo ok"))
           (tokens (nshell.domain.parsing:tokenization-result-tokens
                    result)))
      (expect (nshell.domain.parsing:tokenization-result-p result) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-tokenization-result) :to-be-falsy)
      (expect 2 :to-equal (length tokens))
      (expect (nshell.domain.parsing:tokenization-result-incomplete-p
                 result) :to-be-falsy)))

  (it "token-factory-is-public-boundary"
    "Token construction should stay behind the public normalizing factory."
    (let ((token (nshell.domain.parsing:make-token :word nil nil nil)))
      (expect (fboundp 'nshell.domain.parsing:make-token) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::%make-token) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-token) :to-be-falsy)
      (expect "" :to-equal (nshell.domain.parsing:token-value token))
      (expect 0 :to-equal (nshell.domain.parsing:token-start token))
      (expect 0 :to-equal (nshell.domain.parsing:token-end token))))

  (it "tokenization-result-token-list-is-domain-owned"
    (let* ((result (nshell.domain.parsing:tokenize "echo ok"))
           (tokens (nshell.domain.parsing:tokenization-result-tokens
                    result)))
      (setf (first tokens)
            (nshell.domain.parsing:make-token :word "mutated"))
      (expect "echo" :to-equal (nshell.domain.parsing:token-value
                    (first (nshell.domain.parsing:tokenization-result-tokens
                            result))))))

  (it "simple-command"
    (with-tokenized-input (tokens cursor incomplete) "ls -la"
      (declare (ignore cursor incomplete))
      (expect 2 :to-equal (length tokens))
      (expect "ls" :to-equal (nshell.domain.parsing:token-value (first tokens)))))

  (it "pipeline"
    (with-tokenized-input (tokens cursor incomplete) "ls | grep foo"
      (declare (ignore cursor incomplete))
      (expect 4 :to-equal (length tokens))
      (expect :pipe :to-be (nshell.domain.parsing:token-type (second tokens)))))

  (it "newline-separates-commands"
    (with-tokenized-input (tokens cursor incomplete) (format nil "echo one~%echo two")
      (declare (ignore cursor incomplete))
      (expect 5 :to-equal (length tokens))
      (expect :newline :to-be (nshell.domain.parsing:token-type (third tokens)))
      (expect (string #\Newline) :to-equal (nshell.domain.parsing:token-value (third tokens)))))

  (it "redirect"
    (with-tokenized-input (tokens cursor incomplete) "echo hello > file.txt"
      (declare (ignore cursor incomplete))
      (expect :redirect :to-be (nshell.domain.parsing:token-type (third tokens)))))

  ;; Every case here tokenizes `echo WORD' into exactly two tokens and checks how
  ;; quoting, escaping, and #\# are resolved into the single word token.
  (it-each (("echo \"hello world\""  "hello world")
            ("echo \"my\\ file\""    "my\\ file")
            ("echo hello\\ world"     "hello world")
            ("echo foo#bar"           "foo#bar")
            ("echo foo #bar"          "foo"))
      "tokenizes ~S into the word token ~S"
      (input expected)
    (with-tokenized-input (tokens cursor incomplete) input
      (declare (ignore cursor incomplete))
      (expect 2 :to-equal (length tokens))
      (expect expected :to-equal (nshell.domain.parsing:token-value (second tokens)))))

  (it "tokenizer-main-loop-dispatches-shell-boundaries"
    "The tokenizer main loop must consume shell boundary characters instead of
letting word-reading stop on an unconsumed terminator."
    (dolist (ch '(#\# #\( #\) #\' #\" #\& #\| #\> #\< #\;))
      (expect (nshell.domain.parsing::%tokenizer-special-dispatch-character-p ch) :to-be-truthy))
    (dolist (ch '(#\Space #\Tab #\Newline #\a #\0))
      (expect (nshell.domain.parsing::%tokenizer-special-dispatch-character-p ch) :to-be-falsy)))

  (it "tokenizer-state-constructor-is-internal-boundary"
    "Tokenizer state construction should not keep an unprefixed legacy helper."
    (expect (fboundp 'nshell.domain.parsing::%make-tokenizer-state-for-input) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing::make-tokenizer-state) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-tokenizer-state) :to-be-falsy))

  (it "tokenizer-dispatch-kind-projects-main-loop-boundaries"
    "Tokenizer dispatch classification should remain separate from state mutation."
    (flet ((kind (input)
             (let ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input)))
               (nshell.domain.parsing::%tokenizer-dispatch-kind
                state
                (nshell.domain.parsing::%tokenizer-state-peek state)))))
      (expect :newline :to-be (kind (format nil "~%")))
      (expect :whitespace :to-be (kind " "))
      (expect :fd-redirect :to-be (kind "2>&1"))
      (expect :special :to-be (kind ";"))
      (expect :special :to-be (kind "# comment"))
      (expect :word :to-be (kind "echo"))))

  (it "tokenizer-left-paren-route-projects-command-substitution-policy"
    "Left-paren handling should project command-substitution routing before mutation."
    (flet ((route-facts (input)
             (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                    (route (nshell.domain.parsing::%tokenizer-left-paren-route-for
                            state)))
               (expect (nshell.domain.parsing::%tokenizer-left-paren-route-p route) :to-be-truthy)
               (list
                (nshell.domain.parsing::%tokenizer-left-paren-route-kind route)
                (nshell.domain.parsing::%tokenizer-left-paren-route-end route)))))
      (expect '(:command-substitution 8) :to-equal (route-facts "(echo ok)"))
      (expect '(:literal nil) :to-equal (route-facts "()"))
      (expect '(:literal nil) :to-equal (route-facts "(echo ok"))))

  (it "tokenizer-ampersand-route-projects-operator-policy"
    "Ampersand handling should project operator token facts before mutation."
    (flet ((route-facts (input)
             (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                    (route (nshell.domain.parsing::%tokenizer-ampersand-route-for
                            state)))
               (expect (nshell.domain.parsing::%tokenizer-ampersand-route-p route) :to-be-truthy)
               (list
                (nshell.domain.parsing::%tokenizer-ampersand-route-token-type route)
                (nshell.domain.parsing::%tokenizer-ampersand-route-value route)))))
      (expect '(:and "&&") :to-equal (route-facts "&& echo"))
      (expect '(:redirect "&>") :to-equal (route-facts "&> out"))
      (expect '(:redirect "&>>") :to-equal (route-facts "&>> out"))
      (expect '(:ampersand "&") :to-equal (route-facts "& wait"))))

  (it "tokenizer-pipe-route-projects-operator-policy"
    "Pipe handling should project separator token facts before mutation."
    (flet ((route-facts (input)
             (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                    (route (nshell.domain.parsing::%tokenizer-pipe-route-for
                            state)))
               (expect (nshell.domain.parsing::%tokenizer-pipe-route-p route) :to-be-truthy)
               (list
                (nshell.domain.parsing::%tokenizer-pipe-route-token-type route)
                (nshell.domain.parsing::%tokenizer-pipe-route-value route)))))
      (expect '(:or "||") :to-equal (route-facts "|| echo"))
      (expect '(:pipe "|") :to-equal (route-facts "| grep"))))

  (it "tokenizer-redirect-route-projects-operator-policy"
    "Redirect handling should project redirect token facts before mutation."
    (flet ((right-route-value (input)
             (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                    (route
                      (nshell.domain.parsing::%tokenizer-right-redirect-route-for
                       state)))
               (expect (nshell.domain.parsing::%tokenizer-right-redirect-route-p
                    route) :to-be-truthy)
               (nshell.domain.parsing::%tokenizer-right-redirect-route-value
                route)))
           (left-route-facts (input)
             (let* ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input))
                    (route
                      (nshell.domain.parsing::%tokenizer-left-angle-route-for
                       state)))
               (expect (nshell.domain.parsing::%tokenizer-left-angle-route-p route) :to-be-truthy)
               (list
                (nshell.domain.parsing::%tokenizer-left-angle-route-kind route)
                (nshell.domain.parsing::%tokenizer-left-angle-route-value route)))))
      (expect ">" :to-equal (right-route-value "> out"))
      (expect ">>" :to-equal (right-route-value ">> log"))
      (expect '(:redirect "<") :to-equal (left-route-facts "< in"))
      (expect '(:redirect "<<") :to-equal (left-route-facts "<< EOF"))
      (expect '(:redirect "<<-") :to-equal (left-route-facts "<<- EOF"))
      (expect '(:redirect "<<<") :to-equal (left-route-facts "<<< value"))
      (expect '(:process-substitution nil) :to-equal (left-route-facts "<(echo ok)"))))

  (it "tokenizer-token-extent-projects-normalized-token-boundaries"
    "Token extent projection should own value normalization and end-position facts."
    (let ((empty-extent (nshell.domain.parsing::%token-extent nil nil))
          (operator-extent (nshell.domain.parsing::%token-extent 3 "&&")))
      (expect (nshell.domain.parsing::%token-extent-p empty-extent) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%token-extent) :to-be-falsy)
      (expect 0 :to-equal (nshell.domain.parsing::%token-extent-start empty-extent))
      (expect 0 :to-equal (nshell.domain.parsing::%token-extent-end empty-extent))
      (expect "" :to-equal (nshell.domain.parsing::%token-extent-value empty-extent))
      (expect 3 :to-equal (nshell.domain.parsing::%token-extent-start operator-extent))
      (expect 5 :to-equal (nshell.domain.parsing::%token-extent-end operator-extent))
      (expect "&&" :to-equal (nshell.domain.parsing::%token-extent-value
                         operator-extent))))

  (it "tokenizer-character-boundary-projects-word-termination-data"
    "Tokenizer data should classify word termination facts before loop dispatch."
    (flet ((boundary-kind (ch)
             (let ((boundary (nshell.domain.parsing::%shell-character-boundary ch)))
               (and boundary
                    (nshell.domain.parsing::%shell-character-boundary-kind boundary)))))
      (expect (fboundp 'nshell.domain.parsing::copy-%shell-character-boundary) :to-be-falsy)
      (expect :token-separator :to-be (boundary-kind #\Space))
      (expect :token-separator :to-be (boundary-kind #\|))
      (expect :word-boundary-delimiter :to-be (boundary-kind #\())
      (expect :word-boundary-delimiter :to-be (boundary-kind #\"))
      (expect (boundary-kind #\a) :to-be-null)
      (expect (boundary-kind nil) :to-be-null)
      (expect (nshell.domain.parsing::%shell-word-boundary-p nil) :to-be-null)))

  (it "tokenizer-input-blankness-spec-projects-return-policy"
    "Tokenizer data should keep blank-input return handling in an explicit spec."
    (let ((default-spec
            (nshell.domain.parsing::%shell-input-blankness-spec-from-options))
          (return-spec
             (nshell.domain.parsing::%shell-input-blankness-spec-from-options
              :include-return-p t)))
      (expect (nshell.domain.parsing::%shell-input-blankness-spec-p default-spec) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%shell-input-blankness-spec) :to-be-falsy)
      (expect (nshell.domain.parsing::%shell-input-blankness-spec-include-return-p
                default-spec) :to-be-falsy)
      (expect (nshell.domain.parsing::%shell-input-blankness-spec-include-return-p
           return-spec) :to-be-truthy)
      (expect (nshell.domain.parsing::%shell-input-separator-p #\Space default-spec) :to-be-truthy)
      (expect (nshell.domain.parsing::%shell-input-separator-p
                #\Return default-spec) :to-be-falsy)
      (expect (nshell.domain.parsing::%shell-input-separator-p #\Return return-spec) :to-be-truthy)
      (expect (nshell.domain.parsing::%shell-input-separator-p nil return-spec) :to-be-falsy)
      (expect (nshell.domain.parsing:shell-input-blank-p
           (format nil " ~c" #\Return)
           :include-return-p t) :to-be-truthy)))

  (it "incomplete-quote"
    (with-tokenized-input (tokens cursor incomplete) "echo 'hello"
      (declare (ignore tokens cursor))
      (expect (null incomplete) :to-be-falsy)))

  ;; Each row tokenizes INPUT and checks that the redirection operator lands at
  ;; token POSITION (zero-based) as a :redirect token with the given VALUE, the
  ;; whole input producing LENGTH tokens.
  (it-each (("echo >> log"    3 1 ">>")
            (">"              1 0 ">")
            ("cat << EOF"     3 1 "<<")
            ("cat <<- EOF"    3 1 "<<-")
            ("cat <<< hello"  3 1 "<<<")
            ("echo err 2>&1"  3 2 "2>&1"))
      "tokenizes ~S with a :redirect ~S"
      (input length position value)
    (with-tokenized-input (tokens cursor incomplete) input
      (declare (ignore cursor incomplete))
      (expect length :to-equal (length tokens))
      (expect :redirect :to-be (nshell.domain.parsing:token-type (nth position tokens)))
      (expect value :to-equal (nshell.domain.parsing:token-value (nth position tokens)))))

  (it "fd-redirect-token-text-projects-lookahead-policy"
    "FD redirect token text should be classified before tokenizer state mutation."
    (flet ((token-text (fd op next after-next)
             (nshell.domain.parsing::%fd-redirect-token-text
              fd op next after-next)))
      (let ((simple (token-text #\2 #\> nil nil))
            (append (token-text #\2 #\> #\> nil))
            (dup (token-text #\2 #\> #\& #\1))
            (input (token-text #\0 #\< nil nil)))
        (expect "2>" :to-equal (nshell.domain.parsing::%fd-redirect-token-text-value
                      simple))
        (expect 0 :to-equal (nshell.domain.parsing::%fd-redirect-token-text-advance-count
                simple))
        (expect "2>>" :to-equal (nshell.domain.parsing::%fd-redirect-token-text-value
                      append))
        (expect 1 :to-equal (nshell.domain.parsing::%fd-redirect-token-text-advance-count
                append))
        (expect "2>&1" :to-equal (nshell.domain.parsing::%fd-redirect-token-text-value dup))
        (expect 2 :to-equal (nshell.domain.parsing::%fd-redirect-token-text-advance-count
                dup))
        (expect "0<" :to-equal (nshell.domain.parsing::%fd-redirect-token-text-value input))
        (expect 0 :to-equal (nshell.domain.parsing::%fd-redirect-token-text-advance-count
                input)))))

  (it "bare-parentheses-tokenize-with-progress"
    (with-tokenized-input (tokens cursor incomplete) "()"
      (declare (ignore cursor incomplete))
      (expect 2 :to-equal (length tokens))
      (expect :lparen :to-be (nshell.domain.parsing:token-type (first tokens)))
      (expect :rparen :to-be (nshell.domain.parsing:token-type (second tokens)))))

  ;; A balanced command substitution -- fish `(...)`, `$(...)`, or attached to a
  ;; surrounding word -- stays a single :word token whose value is the whole run.
  (it-each (("echo (echo ok)"                     "(echo ok)")
            ("echo prefix=(echo ok).txt"          "prefix=(echo ok).txt")
            ("echo prefix$(outer (inner))suffix"  "prefix$(outer (inner))suffix")
            ("echo prefix$(printf \"(\")suffix"   "prefix$(printf \"(\")suffix")
            ("echo prefix(outer (inner))suffix"   "prefix(outer (inner))suffix"))
      "keeps a balanced command substitution attached as one word: ~S -> ~S"
      (input expected)
    (with-tokenized-input (tokens cursor incomplete) input
      (declare (ignore cursor))
      (expect incomplete :to-be-null)
      (expect 2 :to-equal (length tokens))
      (expect :word :to-be (nshell.domain.parsing:token-type (second tokens)))
      (expect expected :to-equal (nshell.domain.parsing:token-value (second tokens)))))

  (it "tokenizer-word-scan-action-projects-reader-branches"
    "Word scanning should classify reader branches before mutating tokenizer state."
    (flet ((scan-action (input &optional (pos 0))
             (let ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input)))
               (setf (nshell.domain.parsing::tokenizer-state-pos state) pos)
               (let ((action
                       (nshell.domain.parsing::%tokenizer-word-scan-action-for
                        state
                        (nshell.domain.parsing::%tokenizer-state-peek state))))
                 (expect (nshell.domain.parsing::%tokenizer-word-scan-action-p action) :to-be-truthy)
                 (list (nshell.domain.parsing::%tokenizer-word-scan-action-kind action)
                       (nshell.domain.parsing::%tokenizer-word-scan-action-end action))))))
      (expect '(:dollar-substitution 6) :to-equal (scan-action "$(echo)"))
      (expect '(:fish-substitution 5) :to-equal (scan-action "(echo)"))
      (expect '(:boundary nil) :to-equal (scan-action "()"))
      (expect '(:escape nil) :to-equal (scan-action "\\x"))
      (expect '(:character nil) :to-equal (scan-action "word"))))

  (it "trailing-backslash-is-incomplete"
    (with-tokenized-input (tokens cursor incomplete) "echo \\"
      (declare (ignore cursor))
      (expect (null incomplete) :to-be-falsy)
      (expect 2 :to-equal (length tokens))
      (expect :error :to-be (nshell.domain.parsing:token-type (second tokens)))
      (expect 5 :to-equal (nshell.domain.parsing:token-start (second tokens)))
      (expect 6 :to-equal (nshell.domain.parsing:token-end (second tokens)))))

  (it "tokenizer-balanced-token-boundary-projects-prefixed-substitution-extent"
    "Prefixed substitution readers should consume a projected token boundary."
    (flet ((boundary-facts (input)
             (let ((state (nshell.domain.parsing::%make-tokenizer-state-for-input input)))
               (let ((boundary
                       (nshell.domain.parsing::%tokenizer-balanced-token-boundary-for
                        state
                        1)))
                 (expect (nshell.domain.parsing::%tokenizer-balanced-token-boundary-p
                      boundary) :to-be-truthy)
                 (list
                  (nshell.domain.parsing::%tokenizer-balanced-token-boundary-substitution-end
                   boundary)
                  (nshell.domain.parsing::%tokenizer-balanced-token-boundary-token-end
                   boundary))))))
      (expect '(9 10) :to-equal (boundary-facts "<(echo ok)"))
      (expect '(nil 9) :to-equal (boundary-facts "<(echo ok"))))

  ;; A balanced process substitution `<(...)` is likewise a single :word token.
  (it-each (("cat <(echo ok)"        "<(echo ok)")
            ("cat <(printf \"(\")"   "<(printf \"(\")")
            ("cat <(outer (inner))"  "<(outer (inner))"))
      "keeps a balanced process substitution attached as one word: ~S -> ~S"
      (input expected)
    (with-tokenized-input (tokens cursor incomplete) input
      (declare (ignore cursor))
      (expect incomplete :to-be-null)
      (expect 2 :to-equal (length tokens))
      (expect :word :to-be (nshell.domain.parsing:token-type (second tokens)))
      (expect expected :to-equal (nshell.domain.parsing:token-value (second tokens)))))

  (it "unbalanced-process-substitution-is-incomplete-error-token"
    (with-tokenized-input (tokens cursor incomplete) "cat <(echo ok"
      (declare (ignore cursor))
      (expect (null incomplete) :to-be-falsy)
      (expect 2 :to-equal (length tokens))
      (expect :error :to-be (nshell.domain.parsing:token-type (second tokens)))
      (expect "<(echo ok" :to-equal (nshell.domain.parsing:token-value (second tokens)))
      (expect 4 :to-equal (nshell.domain.parsing:token-start (second tokens)))
      (expect 13 :to-equal (nshell.domain.parsing:token-end (second tokens)))))

  (it "empty-input"
    (with-tokenized-input (tokens cursor incomplete) ""
      (declare (ignore cursor incomplete))
      (expect tokens :to-be-null)))

  (it "tokenizer-double-quoted-escape-character-p-identifies-special-chars"
    "Inside double quotes, only \\, \", $, ` and newline require backslash escaping."
    (flet ((esc (ch)
             (nshell.domain.parsing::%tokenizer-double-quoted-escape-character-p ch)))
      (expect (esc #\\) :to-be-truthy)
      (expect (esc #\") :to-be-truthy)
      (expect (esc #\$) :to-be-truthy)
      (expect (esc #\`) :to-be-truthy)
      (expect (esc #\Newline) :to-be-truthy)
      (expect (esc #\Space) :to-be-falsy)
      (expect (esc #\a) :to-be-falsy)
      (expect (esc #\!) :to-be-falsy)))

  (it "pbt-tokenize-is-deterministic"
    "Tokenizing the same input twice yields identical type/span/value tokens."
    (check-property (:trials 50)
        ((cmd (gen-shell-command) #'shrink-shell-word))
      (flet ((toks (input)
               (nshell.domain.parsing::tokenization-result-tokens
                (nshell.domain.parsing:tokenize input))))
        (let ((a (toks cmd))
              (b (toks cmd)))
          (and (= (length a) (length b))
               (every (lambda (x y)
                        (and (eq (nshell.domain.parsing:token-type x)
                                 (nshell.domain.parsing:token-type y))
                             (= (nshell.domain.parsing:token-start x)
                                (nshell.domain.parsing:token-start y))
                             (= (nshell.domain.parsing:token-end x)
                                (nshell.domain.parsing:token-end y))
                             (string= (nshell.domain.parsing:token-value x)
                                      (nshell.domain.parsing:token-value y))))
                      a b))))))

  (it "pbt-tokenize-spans-are-ordered-and-non-negative"
    "Every produced token span satisfies 0 <= start <= end."
    (check-property (:trials 50)
        ((cmd (gen-shell-command) #'shrink-shell-word))
      (every (lambda (tok)
               (and (<= 0 (nshell.domain.parsing:token-start tok))
                    (<= (nshell.domain.parsing:token-start tok)
                        (nshell.domain.parsing:token-end tok))))
             (nshell.domain.parsing::tokenization-result-tokens
              (nshell.domain.parsing:tokenize cmd))))))
