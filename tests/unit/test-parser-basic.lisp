(in-package #:nshell/test)

(in-suite parser-tests)

(test parse-keeps-dollar-substitutions-attached-to-word
  "$( ) and $(( )) stay attached to surrounding word characters as one argument."
  (with-complete-ast (ast "echo a$((1+2))b")
    (is (equal '("a$((1+2))b")
               (nshell.domain.parsing:command-node-arg-values ast))))
  (with-complete-ast (ast "echo $(echo hi)")
    (is (equal '("$(echo hi)")
               (nshell.domain.parsing:command-node-arg-values ast)))))

(test parse-records-quote-style-per-argument
  "Single and double quotes are distinguished so expansion can treat them differently."
  (with-complete-ast (ast "echo plain \"$FOO\" '*'")
    (let ((args (nshell.domain.parsing:command-node-args ast)))
      (is (= 3 (length args)))
      (assert-arg-quote-styles args nil :double :single))))

(test parse-records-quote-style-for-command-word
  "Command-position quote style is retained so execution can expand it consistently."
  (with-complete-ast (ast "\"$CMD\" plain")
    (is (eq :double
            (nshell.domain.parsing::command-node-command-quote-style ast))))
  (with-complete-ast (ast "'$CMD' plain")
    (is (eq :single
            (nshell.domain.parsing::command-node-command-quote-style ast))))
  (with-complete-ast (ast "$CMD plain")
    (is (null
         (nshell.domain.parsing::command-node-command-quote-style ast)))))

(test command-arg-uses-typed-quote-style-boundary
  "Command args are stored as typed command-arg values at the AST boundary."
  (let* ((quoted (nshell.domain.parsing:make-command-arg "$FOO" :double))
         (command (nshell.domain.parsing:make-command-node
                   "echo"
                   (list "plain" quoted "target.txt")))
         (args (nshell.domain.parsing:command-node-args command)))
    (is (every #'nshell.domain.parsing:command-arg-p args))
    (is (equal '("plain" "$FOO" "target.txt")
               (mapcar #'nshell.domain.parsing:arg-value args)))
    (is (equal '(nil :double nil)
               (mapcar #'nshell.domain.parsing:arg-quote-style args)))
    (is (eq quoted (second args)))))

(test parse-pipeline
  (with-complete-ast (ast "ls | grep foo")
    (is (nshell.domain.parsing:pipeline-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:pipeline-node-commands ast))))))

(test ast-node-command-line-renders-command-and-pipeline
  "AST command-line rendering should match the background job display text."
  (with-complete-ast (command "printf %s bg")
    (is (string= "printf %s bg"
                 (nshell.domain.parsing:ast-node->command-line command))))
  (with-complete-ast (pipeline "printf %s bg-pipe | cat")
    (is (string= "printf %s bg-pipe | cat"
                 (nshell.domain.parsing:ast-node->command-line pipeline)))))

(test ast-node-base-constructor-is-internal-boundary
  "The raw base AST constructor is internal; callers use concrete node factories."
  (is (not (fboundp 'nshell.domain.parsing::make-ast-node)))
  (is (fboundp 'nshell.domain.parsing::%make-ast-node)))

(test ast-node-leaf-constructors-are-internal-boundaries
  "Leaf AST raw constructors are internal implementation details."
  (is (not (fboundp 'nshell.domain.parsing::make-argument-node)))
  (is (not (fboundp 'nshell.domain.parsing::make-operator-node)))
  (is (not (fboundp 'nshell.domain.parsing::make-error-node)))
  (is (not (fboundp 'nshell.domain.parsing::make-incomplete-node)))
  (is (fboundp 'nshell.domain.parsing::%make-argument-node))
  (is (fboundp 'nshell.domain.parsing::%make-operator-node))
  (is (fboundp 'nshell.domain.parsing::%make-error-node))
  (is (fboundp 'nshell.domain.parsing::%make-incomplete-node)))

(test ast-node-value-object-constructors-are-domain-boundaries
  "AST value objects expose factories while hiding raw allocation and copy APIs."
  (is (not (fboundp 'nshell.domain.parsing::copy-command-arg)))
  (is (not (fboundp 'nshell.domain.parsing::copy-case-clause)))
  (is (fboundp 'nshell.domain.parsing::%allocate-command-arg))
  (is (fboundp 'nshell.domain.parsing::%allocate-case-clause))
  (signals error (nshell.domain.parsing:make-command-arg 42))
  (signals error (nshell.domain.parsing:make-command-arg "value" :invalid))
  (signals error (nshell.domain.parsing:make-case-clause 42 '()))
  (signals error (nshell.domain.parsing:make-case-clause "pattern" "not-a-list")))

(test ast-node-constructors-copy-list-slots
  "AST constructors should not share mutable list slots with callers."
  (let* ((args (list "one"))
         (command (nshell.domain.parsing:make-command-node "echo" args)))
    (setf (car args) "changed")
    (is (equal '("one")
               (nshell.domain.parsing:command-node-arg-values command))))
  (let* ((left (nshell.domain.parsing:make-command-node "echo" '("left")))
         (right (nshell.domain.parsing:make-command-node "echo" '("right")))
         (commands (list left))
         (pipeline (nshell.domain.parsing:make-pipeline-node commands)))
    (setf (car commands) right)
    (is (equal '("left")
               (nshell.domain.parsing:command-node-arg-values
                (first (nshell.domain.parsing:pipeline-node-commands pipeline))))))
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("first")))
         (second-command (nshell.domain.parsing:make-command-node "echo" '("second")))
         (commands (list first-command))
         (separators (list :amp))
         (sequence (nshell.domain.parsing::make-sequence-node commands separators)))
    (setf (car commands) second-command
          (car separators) :semi)
    (is (equal '("first")
               (nshell.domain.parsing:command-node-arg-values
                (first (nshell.domain.parsing:sequence-node-commands sequence)))))
    (is (equal '(:amp)
               (nshell.domain.parsing:sequence-node-separators sequence))))
  (let* ((condition (nshell.domain.parsing:make-command-node "test" '("ok")))
         (then-original (nshell.domain.parsing:make-command-node "echo" '("then")))
         (then-replacement (nshell.domain.parsing:make-command-node "echo" '("changed")))
         (else-original (nshell.domain.parsing:make-command-node "echo" '("else")))
         (else-replacement (nshell.domain.parsing:make-command-node "echo" '("changed-else")))
         (then-branch (list then-original))
         (else-branch (list else-original))
         (node (nshell.domain.parsing::make-if-node condition then-branch else-branch)))
    (setf (car then-branch) then-replacement
          (car else-branch) else-replacement)
    (is (eq then-original (first (nshell.domain.parsing:if-node-then-branch node))))
    (is (eq else-original (first (nshell.domain.parsing:if-node-else-branch node)))))
  (let* ((value-original "one")
         (value-replacement "two")
         (body-original (nshell.domain.parsing:make-command-node "echo" '("for")))
         (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed")))
         (values (list value-original))
         (body (list body-original))
         (node (nshell.domain.parsing::make-for-node "name" values body)))
    (setf (car values) value-replacement
          (car body) body-replacement)
    (is (equal (list value-original) (nshell.domain.parsing:for-node-in-values node)))
    (is (eq body-original (first (nshell.domain.parsing:for-node-body node)))))
  (let* ((condition (nshell.domain.parsing:make-command-node "test" '("ok")))
         (body-original (nshell.domain.parsing:make-command-node "echo" '("while")))
         (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed")))
         (body (list body-original))
         (node (nshell.domain.parsing::make-while-node condition body)))
    (setf (car body) body-replacement)
    (is (eq body-original (first (nshell.domain.parsing:while-node-body node)))))
  (let* ((clause-original
           (nshell.domain.parsing:make-case-clause
            "a"
            (list (nshell.domain.parsing:make-command-node "echo" '("case")))))
         (clause-replacement
           (nshell.domain.parsing:make-case-clause
            "b"
            (list (nshell.domain.parsing:make-command-node "echo" '("changed")))))
         (clauses (list clause-original))
         (node (nshell.domain.parsing::make-case-node "value" clauses)))
    (setf (car clauses) clause-replacement)
    (is (eq clause-original (first (nshell.domain.parsing:case-node-clauses node)))))
  (let* ((body-original (nshell.domain.parsing:make-command-node "echo" '("case-body")))
         (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed-body")))
         (body (list body-original))
         (clause (nshell.domain.parsing:make-case-clause "a" body)))
    (setf (car body) body-replacement)
    (is (eq body-original (first (nshell.domain.parsing:case-clause-body clause))))
    (let ((projected-body (nshell.domain.parsing:case-clause-body clause)))
      (setf (car projected-body) body-replacement)
      (is (eq body-original (first (nshell.domain.parsing:case-clause-body clause))))))
  (let* ((body-original (nshell.domain.parsing:make-command-node "echo" '("begin")))
         (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed")))
         (body (list body-original))
         (node (nshell.domain.parsing::make-begin-end-node body)))
    (setf (car body) body-replacement)
    (is (eq body-original (first (nshell.domain.parsing:begin-end-node-body node))))))

(test sequence-node-command-separators-project-copied-node-state
  "Sequence traversal should expose typed command/separator entries without leaking AST state."
  (let* ((left (nshell.domain.parsing:make-command-node "echo" '("left")))
         (right (nshell.domain.parsing:make-command-node "echo" '("right")))
         (sequence (nshell.domain.parsing::make-sequence-node
                    (list left right)
                    (list :semi :amp)))
         (entries (nshell.domain.parsing:sequence-node-command-separators sequence))
         (first-entry (first entries))
         (second-entry (second entries)))
    (is (= 2 (length entries)))
    (is (nshell.domain.parsing:sequence-node-command-separator-p first-entry))
    (is (eq left
            (nshell.domain.parsing:sequence-node-command-separator-command
             first-entry)))
    (is (eq :semi
            (nshell.domain.parsing:sequence-node-command-separator-separator
             first-entry)))
    (is (nshell.domain.parsing:sequence-node-command-separator-p second-entry))
    (is (eq right
            (nshell.domain.parsing:sequence-node-command-separator-command
             second-entry)))
    (is (eq :amp
            (nshell.domain.parsing:sequence-node-command-separator-separator
             second-entry)))))

(test parser-data-reduces-raw-reducer-entry
  "Parser data converts reducer entries directly into reduced command entries."
  (let* ((command (nshell.domain.parsing:make-command-node "echo" '("hi")))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 7 8))
         (entry
           (nshell.domain.parsing::%reduced-command-entry-from-reducer-entry
            (list command :pipe separator-token))))
    (is (nshell.domain.parsing::%reduced-command-entry-p entry))
    (is (eq command
            (nshell.domain.parsing::%reduced-command-entry-command entry)))
    (is (eq :pipe
            (nshell.domain.parsing::%reduced-command-entry-separator entry)))
    (is (eq separator-token
            (nshell.domain.parsing::%reduced-command-entry-separator-token
             entry)))
    (is (not (listp entry)))))

(test parser-projects-reduced-command-stream-boundary
  "Public parser orchestration projects reduced command streams before diagnostics."
  (let* ((command (nshell.domain.parsing:make-command-node "echo" nil))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 5 6))
         (stream (nshell.domain.parsing::%reduced-command-stream-from-reducer-entries
                  (list (list command :pipe separator-token)))))
    (is (equal (list command)
               (nshell.domain.parsing::%reduced-command-stream-commands stream)))
    (is (eq :pipe
            (nshell.domain.parsing::%reduced-command-stream-last-separator stream)))
    (is (eq separator-token
            (nshell.domain.parsing::%reduced-command-stream-last-separator-token
             stream)))
    (let* ((input
             (nshell.domain.parsing::%structural-diagnostics-input-from-stream
              stream
              6))
           (diagnostics-result
             (nshell.domain.parsing::%parse-structural-diagnostics-for-input
              input))
           (diagnostics
             (nshell.domain.parsing::%structural-diagnostics-diagnostics
              diagnostics-result)))
      (is (nshell.domain.parsing::%structural-diagnostics-incomplete-p
           diagnostics-result))
      (is (equal '(:trailing-continuation)
                 (mapcar #'nshell.domain.parsing:parse-diagnostic-kind diagnostics)))
      (is (eq separator-token
              (nshell.domain.parsing:parse-diagnostic-token
               (first diagnostics)))))))

(test parser-projects-command-list-components-boundary
  "Parser orchestration projects typed reducer entries before stream construction."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" nil))
         (second-command (nshell.domain.parsing:make-command-node "cat" nil))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 5 6))
         (entries
           (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
            (list (list first-command :pipe separator-token)
                  (list second-command nil nil))))
         (components
           (nshell.domain.parsing::%command-list-components-from-reduced-entries
            entries)))
    (is (every #'nshell.domain.parsing::%reduced-command-entry-p entries))
    (is (not (some #'listp entries)))
    (is (nshell.domain.parsing::%command-list-components-p components))
    (is (equal (list first-command second-command)
               (nshell.domain.parsing::%command-list-components-commands
                components)))
    (is (equal '(:pipe nil)
               (nshell.domain.parsing::%command-list-components-separators
                components)))
    (is (equal (list separator-token nil)
               (nshell.domain.parsing::%command-list-components-separator-tokens
                components)))))

(test parser-reduction-projects-token-arguments-at-boundary
  "Token reduction owns the command argument representation."
  (let* ((result
           (nshell.domain.parsing::%reduce-token-stream-result
            (list (nshell.domain.parsing:make-token :word "echo" 0 4)
                  (nshell.domain.parsing:make-token :word "$HOME" 5 12 :double)
                  (nshell.domain.parsing:make-token :redirect ">" 13 14)
                  (nshell.domain.parsing:make-token :word "out.txt" 15 22)
                  (nshell.domain.parsing:make-token :redirect "2>&1" 23 27))))
         (commands
           (nshell.domain.parsing::%token-reduction-result-commands result)))
    (is (null (nshell.domain.parsing::%token-reduction-result-errors result)))
    (is (= 1 (length commands)))
    (let ((command (first (first commands))))
      (let ((args (nshell.domain.parsing:command-node-args command)))
        (is (every #'nshell.domain.parsing:command-arg-p args))
        (is (equal '("$HOME" ">" "out.txt" "2>&1")
                   (mapcar #'nshell.domain.parsing:arg-value args)))
        (is (equal '(:double nil nil nil)
                   (mapcar #'nshell.domain.parsing:arg-quote-style args)))))))

(test token-reduction-argument-projection-preserves-quote-and-redirect-shapes
  "Token argument projection owns typed command-node arg shapes."
  (let* ((plain-token
           (nshell.domain.parsing:make-token :word "plain" 0 5))
         (quoted-token
           (nshell.domain.parsing:make-token :word "$HOME" 6 11 :double))
         (redirect-token
           (nshell.domain.parsing:make-token :redirect ">" 12 13))
         (plain
           (nshell.domain.parsing::%token-reduction-argument-from-word-token
            plain-token))
         (quoted
           (nshell.domain.parsing::%token-reduction-argument-from-word-token
            quoted-token))
         (redirect
           (nshell.domain.parsing::%token-reduction-argument-from-redirect-token
            redirect-token)))
    (is (nshell.domain.parsing::%token-reduction-argument-p plain))
    (is (not (fboundp 'nshell.domain.parsing::copy-%token-reduction-argument)))
    (let ((plain-arg
            (nshell.domain.parsing::%token-reduction-argument-raw-value
             plain))
          (quoted-arg
            (nshell.domain.parsing::%token-reduction-argument-raw-value
             quoted))
          (redirect-arg
            (nshell.domain.parsing::%token-reduction-argument-raw-value
             redirect)))
      (is (nshell.domain.parsing:command-arg-p plain-arg))
      (is (equal "plain" (nshell.domain.parsing:arg-value plain-arg)))
      (is (null (nshell.domain.parsing:arg-quote-style plain-arg)))
      (is (nshell.domain.parsing:command-arg-p quoted-arg))
      (is (equal "$HOME" (nshell.domain.parsing:arg-value quoted-arg)))
      (is (eq :double (nshell.domain.parsing:arg-quote-style quoted-arg)))
      (is (nshell.domain.parsing:command-arg-p redirect-arg))
      (is (equal ">" (nshell.domain.parsing:arg-value redirect-arg)))
      (is (null (nshell.domain.parsing:arg-quote-style redirect-arg))))
    (is (nshell.domain.parsing::%token-reduction-argument-syntactic-p
         redirect))))

(test parser-reduction-command-entry-projects-state-boundary
  "Command entry projection owns the reducer's command/separator/token shape."
  (let* ((command-token (nshell.domain.parsing:make-token :word "echo" 0 4))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 5 6))
         (state
           (nshell.domain.parsing::%make-token-reduction-state
            :current-cmd "echo"
            :current-cmd-token command-token
            :current-args (list "hello")
            :pending-sep :pipe
            :pending-sep-token separator-token)))
    (destructuring-bind (command separator token)
        (nshell.domain.parsing::%token-reduction-command-entry-from-state state)
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command command)))
      (is (equal '("hello")
                 (nshell.domain.parsing:command-node-arg-values command)))
      (is (eq :pipe separator))
      (is (eq separator-token token)))))

(test parser-reduction-state-is-domain-state-object
  "Token reduction state is an explicit reducer state object, not positional storage."
  (let ((state (nshell.domain.parsing::%make-token-reduction-state)))
    (is (nshell.domain.parsing::%token-reduction-state-p state))
    (is (not (vectorp state)))
    (is (not (fboundp 'nshell.domain.parsing::copy-%token-reduction-state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-all-cmds state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-current-args state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-errors state))))
  (let ((state
          (nshell.domain.parsing::%make-token-reduction-state
           :current-cmd "echo"
           :current-args (list "hello")
           :pending-sep :pipe)))
    (is (string= "echo"
                 (nshell.domain.parsing::%token-reduction-state-current-cmd state)))
    (is (equal '("hello")
               (nshell.domain.parsing::%token-reduction-state-current-args state)))
    (is (eq :pipe
            (nshell.domain.parsing::%token-reduction-state-pending-sep state)))))

(test parser-reduction-state-records-diagnostic-boundary
  "Token reduction state owns diagnostic recording through a single boundary."
  (let* ((state (nshell.domain.parsing::%make-token-reduction-state))
         (token (nshell.domain.parsing:make-token :pipe "|" 0 1))
         (policy
           (nshell.domain.parsing::%make-token-reduction-diagnostic-policy
            :missing-command
            "Expected command before '|'")))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-record-diagnostic
             state token policy)))
    (let ((diagnostic
            (first
             (nshell.domain.parsing::%token-reduction-state-errors state))))
      (is (eq :missing-command
              (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))
      (is (string= "Expected command before '|'"
                   (nshell.domain.parsing:parse-diagnostic-message diagnostic))))))

(test parser-reduction-diagnostic-policy-formats-token-errors
  "Token reduction diagnostic policies own reducer-facing error messages."
  (let ((missing-command
          (nshell.domain.parsing::%token-reduction-missing-command-policy "|"))
        (unexpected-token
          (nshell.domain.parsing::%token-reduction-unexpected-token-policy
           (nshell.domain.parsing:make-token :unknown "@" 0 1))))
    (is (not (fboundp 'nshell.domain.parsing::copy-%token-reduction-diagnostic-policy)))
    (is (eq :missing-command
            (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
             missing-command)))
    (is (string= "Expected command before '|'"
                 (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                  missing-command)))
    (is (eq :unexpected-token
            (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
             unexpected-token)))
    (is (string= "Unexpected token: @"
                 (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                  unexpected-token)))))

(test parser-reduction-state-records-and-clears-command-context
  "Token reduction state owns command entry recording and command context reset."
  (let* ((command-token (nshell.domain.parsing:make-token :word "echo" 0 4))
         (redirect-token (nshell.domain.parsing:make-token :redirect ">" 5 6))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 11 12))
         (state
           (nshell.domain.parsing::%make-token-reduction-state
            :current-cmd "echo"
            :current-cmd-token command-token
            :current-args (list "hello")
            :pending-redirect-token redirect-token
            :pending-sep :pipe
            :pending-sep-token separator-token)))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-record-command-entry
             state)))
    (is (= 1
           (length
            (nshell.domain.parsing::%token-reduction-state-all-cmds state))))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-clear-command-context
             state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-current-cmd state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-pending-redirect-token
               state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-current-args state)))))

(test parser-reduction-state-updates-command-and-arguments
  "Token reduction state owns command start and argument accumulation transitions."
  (let* ((command-token (nshell.domain.parsing:make-token :word "echo" 0 4))
         (argument-token (nshell.domain.parsing:make-token :word "hello" 5 10))
         (redirect-token (nshell.domain.parsing:make-token :redirect ">" 11 12))
         (state (nshell.domain.parsing::%make-token-reduction-state)))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-start-command
             state command-token)))
    (is (string= "echo"
                 (nshell.domain.parsing::%token-reduction-state-current-cmd
                  state)))
    (is (eq command-token
            (nshell.domain.parsing::%token-reduction-state-current-cmd-token
             state)))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-append-word-argument
             state argument-token)))
    (is (equal '("hello")
               (mapcar #'nshell.domain.parsing:arg-value
                       (nshell.domain.parsing::%token-reduction-state-current-args
                        state))))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-append-redirect-argument
             state redirect-token)))
    (is (equal '(">" "hello")
               (mapcar #'nshell.domain.parsing:arg-value
                       (nshell.domain.parsing::%token-reduction-state-current-args
                        state))))))

(test parser-reduction-state-updates-pending-redirect
  "Token reduction state owns pending redirect lifecycle transitions."
  (let* ((redirect-token (nshell.domain.parsing:make-token :redirect ">" 0 1))
         (state (nshell.domain.parsing::%make-token-reduction-state)))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-mark-pending-redirect
             state redirect-token)))
    (is (eq redirect-token
            (nshell.domain.parsing::%token-reduction-state-pending-redirect-token
             state)))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-clear-pending-redirect
             state)))
    (is (null
         (nshell.domain.parsing::%token-reduction-state-pending-redirect-token
          state)))))

(test parser-reduction-state-updates-pending-separator
  "Token reduction state owns pending separator lifecycle transitions."
  (let* ((separator-token (nshell.domain.parsing:make-token :pipe "|" 0 1))
         (state (nshell.domain.parsing::%make-token-reduction-state)))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-mark-pending-separator
             state :pipe separator-token)))
    (is (eq :pipe
            (nshell.domain.parsing::%token-reduction-state-pending-sep state)))
    (is (eq separator-token
            (nshell.domain.parsing::%token-reduction-state-pending-sep-token
             state)))
    (is (eq state
            (nshell.domain.parsing::%token-reduction-state-clear-pending-separator
             state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-pending-sep state)))
    (is (null (nshell.domain.parsing::%token-reduction-state-pending-sep-token
               state)))))

(test parser-reduction-state-folds-token-stream
  "Token stream reduction folds tokens through an explicit state boundary."
  (let* ((state
           (nshell.domain.parsing::%token-reduction-state-from-tokens
            (list (nshell.domain.parsing:make-token :word "echo" 0 4)
                  (nshell.domain.parsing:make-token :word "hello" 5 10)
                  (nshell.domain.parsing:make-token :pipe "|" 11 12)
                  (nshell.domain.parsing:make-token :word "wc" 13 15))))
         (result
           (nshell.domain.parsing::%token-reduction-result-from-state state))
         (commands
           (nshell.domain.parsing::%token-reduction-result-commands result)))
    (is (nshell.domain.parsing::%token-reduction-state-p state))
    (is (= 2 (length commands)))
    (destructuring-bind (first-command first-separator first-token)
        (first commands)
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command first-command)))
      (is (equal '("hello")
                 (nshell.domain.parsing:command-node-arg-values first-command)))
      (is (eq :pipe first-separator))
      (is (eq :pipe (nshell.domain.parsing:token-type first-token))))
    (destructuring-bind (second-command second-separator second-token)
        (second commands)
      (is (string= "wc"
                   (nshell.domain.parsing:command-node-command second-command)))
      (is (null (nshell.domain.parsing:command-node-args second-command)))
      (is (null second-separator))
      (is (null second-token)))))

(test parser-reduction-result-projects-state-boundary
  "Token reduction result is the projection boundary for commands and diagnostics."
  (let* ((separator-token (nshell.domain.parsing:make-token :pipe "|" 7 8))
         (result
           (nshell.domain.parsing::%reduce-token-stream-result
            (list (nshell.domain.parsing:make-token :word "echo" 0 4)
                  (nshell.domain.parsing:make-token :redirect ">" 5 6)
                  separator-token))))
    (is (nshell.domain.parsing::%token-reduction-result-p result))
    (is (not (fboundp 'nshell.domain.parsing::copy-%token-reduction-result)))
    (destructuring-bind (command separator token)
        (first (nshell.domain.parsing::%token-reduction-result-commands result))
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command command)))
      (is (equal '(">")
                 (nshell.domain.parsing:command-node-arg-values command)))
      (is (eq :pipe separator))
      (is (eq separator-token token)))
    (let ((diagnostic
            (first (nshell.domain.parsing::%token-reduction-result-errors result))))
      (is (eq :missing-redirection-target
              (nshell.domain.parsing:parse-diagnostic-kind diagnostic))))))

(test parser-result-uses-token-reduction-boundary
  "Parser orchestration should consume token reduction results as the reducer boundary."
  (let* ((command (nshell.domain.parsing:make-command-node "echo" '("hello")))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 11 12))
         (diagnostic
           (nshell.domain.parsing::%make-parse-diagnostic
            :missing-redirection-target "Expected redirect target" 6 7))
         (reduction
           (nshell.domain.parsing::%make-token-reduction-result
            (list (list command :pipe separator-token))
            (list diagnostic)))
         (result
           (nshell.domain.parsing::%parse-result-from-token-reduction-result
            reduction nil 12)))
    (is (nshell.domain.parsing:parse-result-incomplete result))
    (is (member diagnostic
                (nshell.domain.parsing:parse-errors result)))
     (is (member :trailing-continuation
                 (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                         (nshell.domain.parsing:parse-errors result))))
     (let ((ast (nshell.domain.parsing:parse-result-ast result)))
       (is (nshell.domain.parsing:command-node-p ast))
       (is (string= "echo"
                    (nshell.domain.parsing:command-node-command ast))))))

(test parse-mixed-sequence-and-pipeline
  (with-complete-ast (ast "echo one | cat; echo two")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (nshell.domain.parsing:pipeline-node-p
         (first (nshell.domain.parsing:sequence-node-commands ast))))
    (is (nshell.domain.parsing:command-node-p
         (second (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:semi)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-mixed-sequence-keeps-pipeline-groups
  (with-complete-ast (ast "echo one | cat && echo two | wc")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (every #'nshell.domain.parsing:pipeline-node-p
               (nshell.domain.parsing:sequence-node-commands ast)))
    (is (equal '(:and)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-background-pipeline-preserves-sequence-node
  "A trailing & backgrounds the whole pipeline, not the final command only."
  (with-complete-ast (ast "echo one | cat &")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 1 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (nshell.domain.parsing:pipeline-node-p
         (first (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:amp)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-newline-sequence
  (with-complete-ast (ast (format nil "echo one~%echo two"))
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:semi)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-empty-input
  (with-parsed-command-line (result "")
    (is (null (nshell.domain.parsing:parse-result-ast result)))
    (is (eq :empty (nshell.domain.parsing:parse-result-state result)))))

(test parse-empty-input-case-branch-is-explicit
  (is (eq :empty
          (nshell.domain.parsing:with-parsed-command-line-case (result ast "")
            (:complete
             (declare (ignore result ast))
             :complete)
            (:empty
             (declare (ignore result ast))
             :empty)))))

(test parsed-command-line-case-clause-projects-branch-body
  "Case branch expansion should project macro clauses before generating code."
  (let ((clause (nshell.domain.parsing::%parsed-command-line-case-clause
                 :empty
                 '((:complete :complete-body)
                   (:empty :empty-body-1 :empty-body-2)))))
    (is (nshell.domain.parsing::%parsed-command-line-case-clause-p clause))
    (is (eq :empty
            (nshell.domain.parsing::%parsed-command-line-case-clause-keyword
             clause)))
    (is (equal '(:empty-body-1 :empty-body-2)
               (nshell.domain.parsing::%parsed-command-line-case-clause-body
                clause)))
    (is (null (nshell.domain.parsing::%parsed-command-line-case-clause
               :error
               '((:complete :complete-body)))))))

(test parse-complete-redirect
  (with-complete-command-line (result ast "echo hello > out.txt")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal '("hello" ">" "out.txt")
               (nshell.domain.parsing:command-node-arg-values ast)))))

(test parse-here-string-redirect
  (with-complete-command-line (result ast "cat <<< hello")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal '("<<<" "hello")
               (nshell.domain.parsing:command-node-arg-values ast)))))

(test parse-here-document-redirect
  (with-complete-command-line (result ast (format nil "cat << EOF~%hello~%EOF"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal `("<<" ,(format nil "hello~%"))
               (nshell.domain.parsing:command-node-arg-values ast)))))

(test parse-multiple-here-documents-preserve-delimiter-order
  (with-complete-command-line (result ast
                                      (format nil "cat << A << B~%one~%A~%two~%B"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal `("<<" ,(format nil "one~%")
                 "<<" ,(format nil "two~%"))
               (nshell.domain.parsing:command-node-arg-values ast)))))

(test parse-here-document-preserves-tail-command
  (with-complete-command-line (result ast
                                      (format nil "cat << EOF~%hello~%EOF~%echo done"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:semi)
               (nshell.domain.parsing:sequence-node-separators ast)))
    (let ((first-command (first (nshell.domain.parsing:sequence-node-commands ast)))
          (second-command (second (nshell.domain.parsing:sequence-node-commands ast))))
      (is (equal `("<<" ,(format nil "hello~%"))
                 (nshell.domain.parsing:command-node-arg-values first-command)))
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command second-command)))
      (is (equal '("done")
                 (nshell.domain.parsing:command-node-arg-values second-command))))))

(test parse-incomplete-here-document
  (with-parsed-command-line (result (format nil "cat << EOF~%hello"))
    (is (nshell.domain.parsing:parse-result-incomplete result))))

(test parse-escaped-space-word
  (with-complete-command-line (result ast "echo hello\\ world")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal '("hello world")
               (nshell.domain.parsing:command-node-arg-values ast)))))
