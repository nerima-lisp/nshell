(in-package #:nshell/test)

(describe "parser-tests"
  (it "parse-keeps-dollar-substitutions-attached-to-word"
    "$( ) and $(( )) stay attached to surrounding word characters as one argument."
    (with-complete-ast (ast "echo a$((1+2))b")
      (expect '("a$((1+2))b") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))
    (with-complete-ast (ast "echo $(echo hi)")
      (expect '("$(echo hi)") :to-equal (nshell.domain.parsing:command-node-arg-values ast))))

  (it "parse-keeps-both-process-substitution-directions-as-arguments"
    "Input and output process substitutions remain attached as command arguments."
    (with-complete-ast (ast "cat <(printf hi) >(cat)")
      (expect '("<(printf hi)" ">(cat)")
              :to-equal
              (nshell.domain.parsing:command-node-arg-values ast))))

  (it "parse-records-quote-style-per-argument"
    "Single and double quotes are distinguished so expansion can treat them differently."
    (with-complete-ast (ast "echo plain \"$FOO\" '*'")
      (let ((args (nshell.domain.parsing:command-node-args ast)))
        (expect 3 :to-equal (length args))
        (assert-arg-quote-styles args nil :double :single))))

  (it "parse-records-quote-style-for-command-word"
    "Command-position quote style is retained so execution can expand it consistently."
    (with-complete-ast (ast "\"$CMD\" plain")
      (expect :double :to-be (nshell.domain.parsing::command-node-command-quote-style ast)))
    (with-complete-ast (ast "'$CMD' plain")
      (expect :single :to-be (nshell.domain.parsing::command-node-command-quote-style ast)))
    (with-complete-ast (ast "$CMD plain")
      (expect (nshell.domain.parsing::command-node-command-quote-style ast) :to-be-null)))

  (it "command-arg-uses-typed-quote-style-boundary"
    "Command args are stored as typed command-arg values at the AST boundary."
    (let* ((quoted (nshell.domain.parsing:make-command-arg "$FOO" :double))
           (command (nshell.domain.parsing:make-command-node
                     "echo"
                     (list "plain" quoted "target.txt")))
           (args (nshell.domain.parsing:command-node-args command)))
      (expect (every #'nshell.domain.parsing:command-arg-p args) :to-be-truthy)
      (expect '("plain" "$FOO" "target.txt") :to-equal (mapcar #'nshell.domain.parsing:arg-value args))
      (expect '(nil :double nil) :to-equal (mapcar #'nshell.domain.parsing:arg-quote-style args))
      (expect quoted :to-be (second args))))

  (it "parse-pipeline"
    (with-complete-ast (ast "ls | grep foo")
      (expect (nshell.domain.parsing:pipeline-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:pipeline-node-commands ast)))))

  (it "parse-pipe-and-merges-stderr-into-left-stage"
    "Pipe-and-stderr should reuse the ordinary pipeline AST and redirect the left stage."
    (with-complete-ast (ast "printf out |& cat")
      (let ((commands (nshell.domain.parsing:pipeline-node-commands ast)))
        (expect '("out" "2>&1") :to-equal
                (mapcar #'nshell.domain.parsing:command-arg-value
                        (nshell.domain.parsing:command-node-args (first commands))))
        (expect "cat" :to-equal
                (nshell.domain.parsing:command-node-command
                 (second commands))))))

  (it "ast-node-command-line-renders-command-and-pipeline"
    "AST command-line rendering should match the background job display text."
    (with-complete-ast (command "printf %s bg")
      (expect "printf %s bg" :to-equal (nshell.domain.parsing:ast-node->command-line command)))
    (with-complete-ast (pipeline "printf %s bg-pipe | cat")
      (expect "printf %s bg-pipe | cat" :to-equal (nshell.domain.parsing:ast-node->command-line pipeline))))

  (it "ast-node-base-constructor-is-internal-boundary"
    "The raw base AST constructor is internal; callers use concrete node factories."
    (expect (fboundp 'nshell.domain.parsing::make-ast-node) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::%make-ast-node) :to-be-truthy))

  (it "ast-node-leaf-constructors-are-internal-boundaries"
    "Leaf AST raw constructors are internal implementation details."
    (expect (fboundp 'nshell.domain.parsing::make-argument-node) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::make-operator-node) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::make-error-node) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::make-incomplete-node) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::%make-argument-node) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing::%make-operator-node) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing::%make-error-node) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing::%make-incomplete-node) :to-be-truthy))

  (it "ast-node-value-object-constructors-are-domain-boundaries"
    "AST value objects expose factories while hiding raw allocation and copy APIs."
    (expect (fboundp 'nshell.domain.parsing::copy-command-arg) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::copy-case-clause) :to-be-falsy)
    (expect (fboundp 'nshell.domain.parsing::%make-command-arg) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing::%make-case-clause) :to-be-truthy)
    (expect (lambda () (nshell.domain.parsing:make-command-arg 42)) :to-throw 'error)
    (expect (lambda () (nshell.domain.parsing:make-command-arg "value" :invalid)) :to-throw 'error)
    (expect (lambda () (nshell.domain.parsing:make-case-clause 42 '())) :to-throw 'error)
    (expect (lambda () (nshell.domain.parsing:make-case-clause "pattern" "not-a-list")) :to-throw 'error))

  (it "ast-value-objects-reject-invalid-fragment-state"
    "Fragment metadata is validated at the AST boundary."
    (expect (lambda ()
              (nshell.domain.parsing:make-command-fragment
               "value" nil '(0 -1)))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.domain.parsing:make-command-node
               "echo" nil nil nil '("not-a-fragment")))
            :to-throw 'error)
    (let ((fragment (nshell.domain.parsing:make-command-fragment "value" :double '(0 2))))
      (expect '(0 2) :to-equal
              (nshell.domain.parsing:command-fragment-escaped-positions fragment))))

  (it "command-node-derives-uniform-fragment-quote-style"
    "A command has a quote style only when every fragment agrees."
    (let ((single (nshell.domain.parsing:make-command-node
                   "echo" nil nil nil
                   (list (nshell.domain.parsing:make-command-fragment "e" :single)
                         (nshell.domain.parsing:make-command-fragment "cho" :single))))
          (mixed (nshell.domain.parsing:make-command-node
                  "echo" nil nil nil
                  (list (nshell.domain.parsing:make-command-fragment "e" :single)
                        (nshell.domain.parsing:make-command-fragment "cho" :double)))))
      (expect :single :to-be
              (nshell.domain.parsing::command-node-command-quote-style single))
      (expect nil :to-be
              (nshell.domain.parsing::command-node-command-quote-style mixed))))

  (it "ast-command-line-rendering-returns-empty-for-unsupported-node"
    "Only command and pipeline nodes have a shell command-line projection."
    (expect "" :to-equal
            (nshell.domain.parsing:ast-node->command-line
             (nshell.domain.parsing::%make-argument-node "argument"))))

  (it "ast-node-constructors-copy-list-slots"
    "AST constructors should not share mutable list slots with callers."
    (let* ((args (list "one"))
           (command (nshell.domain.parsing:make-command-node "echo" args)))
      (setf (car args) "changed")
      (expect '("one") :to-equal (nshell.domain.parsing:command-node-arg-values command)))
    (let* ((left (nshell.domain.parsing:make-command-node "echo" '("left")))
           (right (nshell.domain.parsing:make-command-node "echo" '("right")))
           (commands (list left))
           (pipeline (nshell.domain.parsing:make-pipeline-node commands)))
      (setf (car commands) right)
      (expect '("left") :to-equal (nshell.domain.parsing:command-node-arg-values
                  (first (nshell.domain.parsing:pipeline-node-commands pipeline)))))
    (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("first")))
           (second-command (nshell.domain.parsing:make-command-node "echo" '("second")))
           (commands (list first-command))
           (separators (list :amp))
           (sequence (nshell.domain.parsing::make-sequence-node commands separators)))
      (setf (car commands) second-command
            (car separators) :semi)
      (expect '("first") :to-equal (nshell.domain.parsing:command-node-arg-values
                  (first (nshell.domain.parsing:sequence-node-commands sequence))))
      (expect '(:amp) :to-equal (nshell.domain.parsing:sequence-node-separators sequence)))
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
      (expect then-original :to-be (first (nshell.domain.parsing:if-node-then-branch node)))
      (expect else-original :to-be (first (nshell.domain.parsing:if-node-else-branch node))))
    (let* ((value-original "one")
           (value-replacement "two")
           (body-original (nshell.domain.parsing:make-command-node "echo" '("for")))
           (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed")))
           (values (list value-original))
           (body (list body-original))
           (node (nshell.domain.parsing::make-for-node "name" values body)))
      (setf (car values) value-replacement
            (car body) body-replacement)
      (expect (list value-original) :to-equal (nshell.domain.parsing:for-node-in-values node))
      (expect body-original :to-be (first (nshell.domain.parsing:for-node-body node))))
    (let* ((condition (nshell.domain.parsing:make-command-node "test" '("ok")))
           (body-original (nshell.domain.parsing:make-command-node "echo" '("while")))
           (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed")))
           (body (list body-original))
           (node (nshell.domain.parsing::make-while-node condition body)))
      (setf (car body) body-replacement)
      (expect body-original :to-be (first (nshell.domain.parsing:while-node-body node))))
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
      (expect clause-original :to-be (first (nshell.domain.parsing:case-node-clauses node))))
    (let* ((body-original (nshell.domain.parsing:make-command-node "echo" '("case-body")))
           (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed-body")))
           (body (list body-original))
           (clause (nshell.domain.parsing:make-case-clause "a" body)))
      (setf (car body) body-replacement)
      (expect body-original :to-be (first (nshell.domain.parsing:case-clause-body clause)))
      (let ((projected-body (nshell.domain.parsing:case-clause-body clause)))
        (setf (car projected-body) body-replacement)
        (expect body-original :to-be (first (nshell.domain.parsing:case-clause-body clause)))))
    (let* ((body-original (nshell.domain.parsing:make-command-node "echo" '("begin")))
           (body-replacement (nshell.domain.parsing:make-command-node "echo" '("changed")))
           (body (list body-original))
           (node (nshell.domain.parsing::make-begin-end-node body)))
      (setf (car body) body-replacement)
      (expect body-original :to-be (first (nshell.domain.parsing:begin-end-node-body node)))))

  (it "sequence-node-command-separators-project-copied-node-state"
    "Sequence traversal should expose typed command/separator entries without leaking AST state."
    (let* ((left (nshell.domain.parsing:make-command-node "echo" '("left")))
           (right (nshell.domain.parsing:make-command-node "echo" '("right")))
           (sequence (nshell.domain.parsing::make-sequence-node
                      (list left right)
                      (list :semi :amp)))
           (entries (nshell.domain.parsing:sequence-node-command-separators sequence))
           (first-entry (first entries))
           (second-entry (second entries)))
      (expect 2 :to-equal (length entries))
      (expect (nshell.domain.parsing:sequence-node-command-separator-p first-entry) :to-be-truthy)
      (expect left :to-be (nshell.domain.parsing:sequence-node-command-separator-command
               first-entry))
      (expect :semi :to-be (nshell.domain.parsing:sequence-node-command-separator-separator
               first-entry))
      (expect (nshell.domain.parsing:sequence-node-command-separator-p second-entry) :to-be-truthy)
      (expect right :to-be (nshell.domain.parsing:sequence-node-command-separator-command
               second-entry))
      (expect :amp :to-be (nshell.domain.parsing:sequence-node-command-separator-separator
               second-entry))))

  (it "parser-data-reduces-raw-reducer-entry"
    "Parser data converts reducer entries directly into reduced command entries."
    (let* ((command (nshell.domain.parsing:make-command-node "echo" '("hi")))
           (separator-token (nshell.domain.parsing:make-token :pipe "|" 7 8))
           (entry
             (nshell.domain.parsing::%reduced-command-entry-from-reducer-entry
              (list command :pipe separator-token))))
      (expect (nshell.domain.parsing::%reduced-command-entry-p entry) :to-be-truthy)
      (expect command :to-be (nshell.domain.parsing::%reduced-command-entry-command entry))
      (expect :pipe :to-be (nshell.domain.parsing::%reduced-command-entry-separator entry))
      (expect separator-token :to-be (nshell.domain.parsing::%reduced-command-entry-separator-token
               entry))
      (expect (listp entry) :to-be-falsy)))

  (it "parser-projects-reduced-command-stream-boundary"
    "Public parser orchestration projects reduced command streams before diagnostics."
    (let* ((command (nshell.domain.parsing:make-command-node "echo" nil))
           (separator-token (nshell.domain.parsing:make-token :pipe "|" 5 6))
           (stream (nshell.domain.parsing::%reduced-command-stream-from-reducer-entries
                    (list (list command :pipe separator-token)))))
      (expect (list command) :to-equal (nshell.domain.parsing::%reduced-command-stream-commands stream))
      (expect :pipe :to-be (nshell.domain.parsing::%reduced-command-stream-last-separator stream))
      (expect separator-token :to-be (nshell.domain.parsing::%reduced-command-stream-last-separator-token
               stream))
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
        (expect (nshell.domain.parsing::%structural-diagnostics-incomplete-p
             diagnostics-result) :to-be-truthy)
        (expect '(:trailing-continuation) :to-equal (mapcar #'nshell.domain.parsing:parse-diagnostic-kind diagnostics))
        (expect separator-token :to-be (nshell.domain.parsing:parse-diagnostic-token
                 (first diagnostics))))))

  (it "parser-projects-command-list-components-boundary"
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
      (expect (every #'nshell.domain.parsing::%reduced-command-entry-p entries) :to-be-truthy)
      (expect (some #'listp entries) :to-be-falsy)
      (expect (nshell.domain.parsing::%command-list-components-p components) :to-be-truthy)
      (expect (list first-command second-command) :to-equal (nshell.domain.parsing::%command-list-components-commands
                  components))
      (expect '(:pipe nil) :to-equal (nshell.domain.parsing::%command-list-components-separators
                  components))
      (expect (list separator-token nil) :to-equal (nshell.domain.parsing::%command-list-components-separator-tokens
                  components))))

  (it "parser-reduction-projects-token-arguments-at-boundary"
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
      (expect (nshell.domain.parsing::%token-reduction-result-errors result) :to-be-null)
      (expect 1 :to-equal (length commands))
      (let ((command (first (first commands))))
        (let ((args (nshell.domain.parsing:command-node-args command)))
          (expect (every #'nshell.domain.parsing:command-arg-p args) :to-be-truthy)
          (expect '("$HOME" ">" "out.txt" "2>&1") :to-equal (mapcar #'nshell.domain.parsing:arg-value args))
          (expect '(:double nil nil nil) :to-equal (mapcar #'nshell.domain.parsing:arg-quote-style args))))))

  (it "token-reduction-argument-projection-preserves-quote-and-redirect-shapes"
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
      (expect (nshell.domain.parsing::%token-reduction-argument-p plain) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%token-reduction-argument) :to-be-falsy)
      (let ((plain-arg
              (nshell.domain.parsing::%token-reduction-argument-raw-value
               plain))
            (quoted-arg
              (nshell.domain.parsing::%token-reduction-argument-raw-value
               quoted))
            (redirect-arg
              (nshell.domain.parsing::%token-reduction-argument-raw-value
               redirect)))
        (expect (nshell.domain.parsing:command-arg-p plain-arg) :to-be-truthy)
        (expect "plain" :to-equal (nshell.domain.parsing:arg-value plain-arg))
        (expect (nshell.domain.parsing:arg-quote-style plain-arg) :to-be-null)
        (expect (nshell.domain.parsing:command-arg-p quoted-arg) :to-be-truthy)
        (expect "$HOME" :to-equal (nshell.domain.parsing:arg-value quoted-arg))
        (expect :double :to-be (nshell.domain.parsing:arg-quote-style quoted-arg))
        (expect (nshell.domain.parsing:command-arg-p redirect-arg) :to-be-truthy)
        (expect ">" :to-equal (nshell.domain.parsing:arg-value redirect-arg))
        (expect (nshell.domain.parsing:arg-quote-style redirect-arg) :to-be-null))
      (expect (nshell.domain.parsing::%token-reduction-argument-syntactic-p
           redirect) :to-be-truthy)))

  (it "parser-reduction-command-entry-projects-state-boundary"
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
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command command))
        (expect '("hello") :to-equal (nshell.domain.parsing:command-node-arg-values command))
        (expect :pipe :to-be separator)
        (expect separator-token :to-be token))))

  (it "parser-reduction-state-is-domain-state-object"
    "Token reduction state is an explicit reducer state object, not positional storage."
    (let ((state (nshell.domain.parsing::%make-token-reduction-state)))
      (expect (nshell.domain.parsing::%token-reduction-state-p state) :to-be-truthy)
      (expect (vectorp state) :to-be-falsy)
      (expect (fboundp 'nshell.domain.parsing::copy-%token-reduction-state) :to-be-falsy)
      (expect (nshell.domain.parsing::%token-reduction-state-all-cmds state) :to-be-null)
      (expect (nshell.domain.parsing::%token-reduction-state-current-args state) :to-be-null)
      (expect (nshell.domain.parsing::%token-reduction-state-errors state) :to-be-null))
    (let ((state
            (nshell.domain.parsing::%make-token-reduction-state
             :current-cmd "echo"
             :current-args (list "hello")
             :pending-sep :pipe)))
      (expect "echo" :to-equal (nshell.domain.parsing::%token-reduction-state-current-cmd state))
      (expect '("hello") :to-equal (nshell.domain.parsing::%token-reduction-state-current-args state))
      (expect :pipe :to-be (nshell.domain.parsing::%token-reduction-state-pending-sep state))))

  (it "parser-reduction-data-boundaries-preserve-explicit-fields"
    "Reducer data objects expose every field through their domain-owned accessors."
    (let* ((command-token (nshell.domain.parsing:make-token :word "echo" 0 4))
           (redirect-token (nshell.domain.parsing:make-token :redirect ">" 5 6))
           (separator-token (nshell.domain.parsing:make-token :pipe "|" 7 8))
           (state
             (nshell.domain.parsing::%make-token-reduction-state
              :all-cmds '("previous")
              :current-args '("hello")
              :current-cmd "echo"
              :current-cmd-token command-token
              :current-cmd-fragments '("ec" "ho")
              :last-word-token command-token
              :pending-redirect-token redirect-token
              :pending-sep :pipe
              :pending-sep-token separator-token
              :errors '("diagnostic")))
           (result (nshell.domain.parsing::%make-token-reduction-result
                    '("command") '("error")))
           (argument (nshell.domain.parsing::%make-token-reduction-argument
                      "hello" :double t '("hel" "lo")))
           (policy (nshell.domain.parsing::%make-token-reduction-diagnostic-policy
                    :unexpected-token "Unexpected token")))
      (dolist (case `((,(nshell.domain.parsing::%token-reduction-state-all-cmds state)
                       ("previous"))
                      (,(nshell.domain.parsing::%token-reduction-state-current-args state)
                       ("hello"))
                      (,(nshell.domain.parsing::%token-reduction-state-current-cmd state) "echo")
                      (,(nshell.domain.parsing::%token-reduction-state-current-cmd-token state)
                       ,command-token)
                      (,(nshell.domain.parsing::%token-reduction-state-current-cmd-fragments state)
                       ("ec" "ho"))
                      (,(nshell.domain.parsing::%token-reduction-state-last-word-token state)
                       ,command-token)
                      (,(nshell.domain.parsing::%token-reduction-state-pending-redirect-token state)
                       ,redirect-token)
                      (,(nshell.domain.parsing::%token-reduction-state-pending-sep state) :pipe)
                      (,(nshell.domain.parsing::%token-reduction-state-pending-sep-token state)
                       ,separator-token)
                      (,(nshell.domain.parsing::%token-reduction-state-errors state)
                       ("diagnostic"))))
        (destructuring-bind (actual expected) case
          (expect expected :to-equal actual)))
      (expect '("command") :to-equal
              (nshell.domain.parsing::%token-reduction-result-commands result))
      (expect '("error") :to-equal
              (nshell.domain.parsing::%token-reduction-result-errors result))
      (expect "hello" :to-equal
              (nshell.domain.parsing::%token-reduction-argument-value argument))
      (expect :double :to-be
              (nshell.domain.parsing::%token-reduction-argument-quote-style argument))
      (expect t :to-be
              (nshell.domain.parsing::%token-reduction-argument-syntactic-p argument))
      (expect '("hel" "lo") :to-equal
              (nshell.domain.parsing::%token-reduction-argument-fragments argument))
      (expect :unexpected-token :to-be
              (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind policy))
      (expect "Unexpected token" :to-equal
              (nshell.domain.parsing::%token-reduction-diagnostic-policy-message policy))))

  (it "parser-reduction-state-records-diagnostic-boundary"
    "Token reduction state owns diagnostic recording through a single boundary."
    (let* ((state (nshell.domain.parsing::%make-token-reduction-state))
           (token (nshell.domain.parsing:make-token :pipe "|" 0 1))
           (policy
             (nshell.domain.parsing::%make-token-reduction-diagnostic-policy
              :missing-command
              "Expected command before '|'")))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-record-diagnostic
               state token policy))
      (let ((diagnostic
              (first
               (nshell.domain.parsing::%token-reduction-state-errors state))))
        (expect :missing-command :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic))
        (expect "Expected command before '|'" :to-equal (nshell.domain.parsing:parse-diagnostic-message diagnostic)))))

  (it "parser-reduction-diagnostic-policy-formats-token-errors"
    "Token reduction diagnostic policies own reducer-facing error messages."
    (let ((missing-command
            (nshell.domain.parsing::%token-reduction-missing-command-policy "|"))
          (unexpected-token
            (nshell.domain.parsing::%token-reduction-unexpected-token-policy
             (nshell.domain.parsing:make-token :unknown "@" 0 1))))
      (expect (fboundp 'nshell.domain.parsing::copy-%token-reduction-diagnostic-policy) :to-be-falsy)
      (expect :missing-command :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
               missing-command))
      (expect "Expected command before '|'" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                    missing-command))
      (expect :unexpected-token :to-be (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind
               unexpected-token))
      (expect "Unexpected token: @" :to-equal (nshell.domain.parsing::%token-reduction-diagnostic-policy-message
                    unexpected-token))
      (dolist (case '(("\\" :trailing-escape "Trailing escape requires continuation")
                      ("<(" :unterminated-process-substitution
                       "Unterminated process substitution")
                      ("hello" :unterminated-quote "Unterminated quoted string")))
        (destructuring-bind (value kind message) case
          (let ((policy
                  (nshell.domain.parsing::%token-reduction-error-policy-from-token
                   (nshell.domain.parsing:make-token :word value 0 (length value)))))
            (expect kind :to-be
             (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind policy))
            (expect message :to-equal
             (nshell.domain.parsing::%token-reduction-diagnostic-policy-message policy)))))))

  (it "parser-reduction-state-records-and-clears-command-context"
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
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-record-command-entry
               state))
      (expect 1 :to-equal (length
              (nshell.domain.parsing::%token-reduction-state-all-cmds state)))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-clear-command-context
               state))
      (expect (nshell.domain.parsing::%token-reduction-state-current-cmd state) :to-be-null)
      (expect (nshell.domain.parsing::%token-reduction-state-pending-redirect-token
                 state) :to-be-null)
      (expect (nshell.domain.parsing::%token-reduction-state-current-args state) :to-be-null)))

  (it "parser-reduction-state-updates-command-and-arguments"
    "Token reduction state owns command start and argument accumulation transitions."
    (let* ((command-token (nshell.domain.parsing:make-token :word "echo" 0 4))
           (argument-token (nshell.domain.parsing:make-token :word "hello" 5 10))
           (redirect-token (nshell.domain.parsing:make-token :redirect ">" 11 12))
           (state (nshell.domain.parsing::%make-token-reduction-state)))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-start-command
               state command-token))
      (expect "echo" :to-equal (nshell.domain.parsing::%token-reduction-state-current-cmd
                    state))
      (expect command-token :to-be (nshell.domain.parsing::%token-reduction-state-current-cmd-token
               state))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-append-word-argument
               state argument-token))
      (expect '("hello") :to-equal (mapcar #'nshell.domain.parsing:arg-value
                         (nshell.domain.parsing::%token-reduction-state-current-args
                          state)))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-append-redirect-argument
               state redirect-token))
      (expect '(">" "hello") :to-equal (mapcar #'nshell.domain.parsing:arg-value
                         (nshell.domain.parsing::%token-reduction-state-current-args
                          state)))))

  (it "parser-reduction-state-updates-pending-redirect"
    "Token reduction state owns pending redirect lifecycle transitions."
    (let* ((redirect-token (nshell.domain.parsing:make-token :redirect ">" 0 1))
           (state (nshell.domain.parsing::%make-token-reduction-state)))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-mark-pending-redirect
               state redirect-token))
      (expect redirect-token :to-be (nshell.domain.parsing::%token-reduction-state-pending-redirect-token
               state))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-clear-pending-redirect
               state))
      (expect (nshell.domain.parsing::%token-reduction-state-pending-redirect-token
            state) :to-be-null)))

  (it "parser-reduction-state-updates-pending-separator"
    "Token reduction state owns pending separator lifecycle transitions."
    (let* ((separator-token (nshell.domain.parsing:make-token :pipe "|" 0 1))
           (state (nshell.domain.parsing::%make-token-reduction-state)))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-mark-pending-separator
               state :pipe separator-token))
      (expect :pipe :to-be (nshell.domain.parsing::%token-reduction-state-pending-sep state))
      (expect separator-token :to-be (nshell.domain.parsing::%token-reduction-state-pending-sep-token
               state))
      (expect state :to-be (nshell.domain.parsing::%token-reduction-state-clear-pending-separator
               state))
      (expect (nshell.domain.parsing::%token-reduction-state-pending-sep state) :to-be-null)
      (expect (nshell.domain.parsing::%token-reduction-state-pending-sep-token
                 state) :to-be-null)))

  (it "parser-reduction-state-folds-token-stream"
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
      (expect (nshell.domain.parsing::%token-reduction-state-p state) :to-be-truthy)
      (expect 2 :to-equal (length commands))
      (destructuring-bind (first-command first-separator first-token)
          (first commands)
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command first-command))
        (expect '("hello") :to-equal (nshell.domain.parsing:command-node-arg-values first-command))
        (expect :pipe :to-be first-separator)
        (expect :pipe :to-be (nshell.domain.parsing:token-type first-token)))
      (destructuring-bind (second-command second-separator second-token)
          (second commands)
        (expect "wc" :to-equal (nshell.domain.parsing:command-node-command second-command))
        (expect (nshell.domain.parsing:command-node-args second-command) :to-be-null)
        (expect second-separator :to-be-null)
        (expect second-token :to-be-null))))

  (it "parser-reduction-result-projects-state-boundary"
    "Token reduction result is the projection boundary for commands and diagnostics."
    (let* ((separator-token (nshell.domain.parsing:make-token :pipe "|" 7 8))
           (result
             (nshell.domain.parsing::%reduce-token-stream-result
              (list (nshell.domain.parsing:make-token :word "echo" 0 4)
                    (nshell.domain.parsing:make-token :redirect ">" 5 6)
                    separator-token))))
      (expect (nshell.domain.parsing::%token-reduction-result-p result) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-%token-reduction-result) :to-be-falsy)
      (destructuring-bind (command separator token)
          (first (nshell.domain.parsing::%token-reduction-result-commands result))
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command command))
        (expect '(">") :to-equal (nshell.domain.parsing:command-node-arg-values command))
        (expect :pipe :to-be separator)
        (expect separator-token :to-be token))
      (let ((diagnostic
              (first (nshell.domain.parsing::%token-reduction-result-errors result))))
        (expect :missing-redirection-target :to-be (nshell.domain.parsing:parse-diagnostic-kind diagnostic)))))

  (it "parser-result-uses-token-reduction-boundary"
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
      (expect (nshell.domain.parsing:parse-result-incomplete result) :to-be-truthy)
      (expect (member diagnostic
                  (nshell.domain.parsing:parse-errors result)) :to-be-truthy)
       (expect (member :trailing-continuation
                   (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                           (nshell.domain.parsing:parse-errors result))) :to-be-truthy)
       (let ((ast (nshell.domain.parsing:parse-result-ast result)))
         (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
         (expect "echo" :to-equal (nshell.domain.parsing:command-node-command ast)))))

  (it "parse-mixed-sequence-and-pipeline"
    (with-complete-ast (ast "echo one | cat; echo two")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect (nshell.domain.parsing:pipeline-node-p
           (first (nshell.domain.parsing:sequence-node-commands ast))) :to-be-truthy)
      (expect (nshell.domain.parsing:command-node-p
           (second (nshell.domain.parsing:sequence-node-commands ast))) :to-be-truthy)
      (expect '(:semi) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-mixed-sequence-keeps-pipeline-groups"
    (with-complete-ast (ast "echo one | cat && echo two | wc")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect (every #'nshell.domain.parsing:pipeline-node-p
                 (nshell.domain.parsing:sequence-node-commands ast)) :to-be-truthy)
      (expect '(:and) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-background-pipeline-preserves-sequence-node"
    "A trailing & backgrounds the whole pipeline, not the final command only."
    (with-complete-ast (ast "echo one | cat &")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 1 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect (nshell.domain.parsing:pipeline-node-p
           (first (nshell.domain.parsing:sequence-node-commands ast))) :to-be-truthy)
      (expect '(:amp) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-newline-sequence"
    (with-complete-ast (ast (format nil "echo one~%echo two"))
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect '(:semi) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-empty-input"
    (with-parsed-command-line (result "")
      (expect (nshell.domain.parsing:parse-result-ast result) :to-be-null)
      (expect :empty :to-be (nshell.domain.parsing:parse-result-state result))))

  (it "parse-empty-input-case-branch-is-explicit"
    (expect :empty :to-be (nshell.domain.parsing:with-parsed-command-line-case (result ast "")
              (:complete
               (declare (ignore result ast))
               :complete)
              (:empty
               (declare (ignore result ast))
               :empty))))

  (it "parsed-command-line-case-clause-projects-branch-body"
    "Case branch expansion should project macro clauses before generating code."
    (let ((clause (nshell.domain.parsing::%parsed-command-line-case-clause
                   :empty
                   '((:complete :complete-body)
                     (:empty :empty-body-1 :empty-body-2)))))
      (expect (nshell.domain.parsing::%parsed-command-line-case-clause-p clause) :to-be-truthy)
      (expect :empty :to-be (nshell.domain.parsing::%parsed-command-line-case-clause-keyword
               clause))
      (expect '(:empty-body-1 :empty-body-2) :to-equal (nshell.domain.parsing::%parsed-command-line-case-clause-body
                  clause))
      (expect (nshell.domain.parsing::%parsed-command-line-case-clause
                 :error
                 '((:complete :complete-body))) :to-be-null)))

  (it "parse-complete-redirect"
    (with-complete-command-line (result ast "echo hello > out.txt")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
      (expect '("hello" ">" "out.txt") :to-equal (nshell.domain.parsing:command-node-arg-values ast))))

  (it "parse-here-string-redirect"
    (with-complete-command-line (result ast "cat <<< hello")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
      (expect '("<<<" "hello") :to-equal (nshell.domain.parsing:command-node-arg-values ast))))

  (it "parse-here-document-redirect"
    (with-complete-command-line (result ast (format nil "cat << EOF~%hello~%EOF"))
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
      (expect `("<<" ,(format nil "hello~%")) :to-equal (nshell.domain.parsing:command-node-arg-values ast))))

  (it "parse-multiple-here-documents-preserve-delimiter-order"
    (with-complete-command-line (result ast
                                        (format nil "cat << A << B~%one~%A~%two~%B"))
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
      (expect `("<<" ,(format nil "one~%")
                   "<<" ,(format nil "two~%")) :to-equal (nshell.domain.parsing:command-node-arg-values ast))))

  (it "parse-here-document-preserves-tail-command"
    (with-complete-command-line (result ast
                                        (format nil "cat << EOF~%hello~%EOF~%echo done"))
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect '(:semi) :to-equal (nshell.domain.parsing:sequence-node-separators ast))
      (let ((first-command (first (nshell.domain.parsing:sequence-node-commands ast)))
            (second-command (second (nshell.domain.parsing:sequence-node-commands ast))))
        (expect `("<<" ,(format nil "hello~%")) :to-equal (nshell.domain.parsing:command-node-arg-values first-command))
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command second-command))
        (expect '("done") :to-equal (nshell.domain.parsing:command-node-arg-values second-command)))))

  (it "parse-incomplete-here-document"
    (with-parsed-command-line (result (format nil "cat << EOF~%hello"))
      (expect (nshell.domain.parsing:parse-result-incomplete result) :to-be-truthy)))

  (it "parse-escaped-space-word"
    (with-complete-command-line (result ast "echo hello\\ world")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
      (expect '("hello world") :to-equal (nshell.domain.parsing:command-node-arg-values ast))))

  (it "token-reduction-error-policy-classifies-terminal-errors"
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
            :to-be-falsy)))
