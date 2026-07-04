(in-package #:nshell/test)

(in-suite parser-tests)

(test parse-simple-command
  (with-complete-ast (ast "ls -la")
    (is (nshell.domain.parsing:command-node-p ast))
    (is (string= "ls" (nshell.domain.parsing:command-node-command ast)))
    (is (equal '("-la")
               (nshell.domain.parsing:command-node-arg-values ast)))))

(test parse-fd-redirects-tokenize-and-need-no-spurious-target
  "fd-prefixed and combined redirects parse cleanly; 2>&1 needs no file target."
  (is (nshell.domain.parsing::%redirect-targetless-p "2>&1"))
  (with-complete-command-line (result ast "cat x 2>err.txt")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "cat" (nshell.domain.parsing:command-node-command ast))))
  (with-complete-command-line (result ast "cat x 2>&1")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "cat" (nshell.domain.parsing:command-node-command ast)))
    (is (equal '("x" "2>&1")
               (nshell.domain.parsing:command-node-arg-values ast))))
  (with-complete-command-line (result ast "make &>build.log")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "make" (nshell.domain.parsing:command-node-command ast)))))

(test parser-data-query-functions-handle-boundary-values
  "Parser data lookups should reject absent domain values without type errors."
  (let ((redirect-facts (nshell.domain.parsing::%redirect-facts "2>&1"))
        (pipe-facts (nshell.domain.parsing::%separator-facts :pipe)))
    (is (null (nshell.domain.parsing::%redirect-facts nil)))
    (is (null (nshell.domain.parsing::%redirect-target-policy nil)))
    (is (nshell.domain.parsing::%redirect-facts-p redirect-facts))
    (is (string= "2>&1"
                 (nshell.domain.parsing::%redirect-facts-text
                  redirect-facts)))
    (is (eq :2>&1
            (nshell.domain.parsing::%redirect-facts-kind
             redirect-facts)))
    (is (nshell.domain.parsing::%redirect-facts-fd-dup-p redirect-facts))
    (is (null (nshell.domain.parsing::%redirect-facts "not-a-redirect")))
    (is (null (nshell.domain.parsing::%separator-from-token-type :unknown)))
    (is (nshell.domain.parsing::%separator-facts-p pipe-facts))
    (is (eq :pipe
            (nshell.domain.parsing::%separator-facts-token-type pipe-facts)))
    (is (string= "|"
                 (nshell.domain.parsing::%separator-facts-text pipe-facts)))
    (is (nshell.domain.parsing::%separator-facts-continues-p pipe-facts))
    (is (not (nshell.domain.parsing::%continuation-separator-p nil)))
    (is (null (nshell.domain.parsing::%separator-facts nil)))
    (is (null (nshell.domain.parsing::%separator-text nil)))))

(test redirect-spec-entry-projects-table-shape
  "Redirect spec entries isolate raw table shape from parser data queries."
  (let ((entry (nshell.domain.parsing::%redirect-spec-entry "2>&1")))
    (is (nshell.domain.parsing::%redirect-spec-entry-p entry))
    (is (string= "2>&1"
                 (nshell.domain.parsing::%redirect-spec-entry-text entry)))
    (is (eq :2>&1
            (nshell.domain.parsing::%redirect-spec-entry-kind entry)))
    (is (null (nshell.domain.parsing::%redirect-spec-entry nil)))
    (is (null (nshell.domain.parsing::%redirect-spec-entry
               "not-a-redirect")))))

(test redirect-entry-projects-runtime-redirect-shape
  "Runtime redirect entries isolate cons shape from redirect classification."
  (let ((entry (nshell.domain.parsing::%redirect-entry-from-raw
                '(:>> . "out.txt"))))
    (is (nshell.domain.parsing::%redirect-entry-p entry))
    (is (eq :>> (nshell.domain.parsing::%redirect-entry-kind entry)))
    (is (string= "out.txt"
                 (nshell.domain.parsing::%redirect-entry-target entry)))
    (is (null (nshell.domain.parsing::%redirect-entry-from-raw nil)))))

(test redirect-target-policy-projects-target-requirement
  "Redirect target policy owns which redirect specs consume a target."
  (let ((fd-dup-policy
          (nshell.domain.parsing::%redirect-target-policy "2>&1"))
        (output-policy
          (nshell.domain.parsing::%redirect-target-policy ">"))
        (stderr-policy
          (nshell.domain.parsing::%redirect-target-policy "2>"))
        (all-output-policy
          (nshell.domain.parsing::%redirect-target-policy "&>"))
        (all-output-append-policy
          (nshell.domain.parsing::%redirect-target-policy "&>>")))
    (is (nshell.domain.parsing::%redirect-target-policy-p fd-dup-policy))
    (is (eq :2>&1
            (nshell.domain.parsing::%redirect-target-policy-kind
             fd-dup-policy)))
    (is (not (nshell.domain.parsing::%redirect-target-policy-target-required-p
              fd-dup-policy)))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         output-policy))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         stderr-policy))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         all-output-policy))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         all-output-append-policy))
    (is (nshell.domain.parsing::%redirect-target-required-p ">"))
    (is (nshell.domain.parsing::%redirect-target-required-p "2>"))
    (is (nshell.domain.parsing::%redirect-targetless-p "2>&1"))
    (is (not (fboundp
              'nshell.domain.parsing::%redirect-target-policy-from-kind)))
    (is (null (nshell.domain.parsing::%redirect-target-policy nil)))
    (is (null (nshell.domain.parsing::%redirect-target-policy
               "not-a-redirect")))
    (is (null (nshell.domain.parsing::%redirect-target-required-p nil)))
    (is (null (nshell.domain.parsing::%redirect-targetless-p
               "not-a-redirect")))))

(test redirect-kind-facts-project-classification
  "Redirect kind facts should own input/output/stderr/append classification."
  (let ((input-facts (nshell.domain.parsing::%redirect-kind-facts :<))
        (stderr-append-facts (nshell.domain.parsing::%redirect-kind-facts :2>>))
        (all-output-append-facts (nshell.domain.parsing::%redirect-kind-facts :&>>)))
    (is (nshell.domain.parsing::%redirect-kind-facts-p input-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-input-p input-facts))
    (is (not (nshell.domain.parsing::%redirect-kind-facts-output-p input-facts)))
    (is (not (nshell.domain.parsing::%redirect-kind-facts-stderr-p input-facts)))
    (is (nshell.domain.parsing::%redirect-kind-facts-stderr-p
         stderr-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-append-p
         stderr-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-output-p
         all-output-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-stderr-p
         all-output-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-append-p
         all-output-append-facts))
    (is (null (nshell.domain.parsing::%redirect-kind-facts nil)))
    (is (null (nshell.domain.parsing::%redirect-kind-facts :unknown)))))

(test redirect-execution-classification-projects-effective-specs
  "Execution redirect classification belongs to parser-domain data."
  (let ((redirects '((:< . "in.txt")
                     (:> . "out.txt")
                     (:>> . "append.txt")
                     (:2>&1 . nil))))
    (is (nshell.domain.parsing:redirect-input-kind-p :<))
    (is (nshell.domain.parsing:redirect-output-kind-p :&>))
    (is (nshell.domain.parsing:redirect-stderr-kind-p :2>&1))
    (is (nshell.domain.parsing:redirect-append-kind-p :>>))
    (is (nshell.domain.parsing:redirect-append-kind-p :2>>))
    (is (nshell.domain.parsing:redirect-output-kind-p :&>>))
    (is (nshell.domain.parsing:redirect-stderr-kind-p :&>>))
    (is (not (nshell.domain.parsing:redirect-input-kind-p nil)))
    (is (not (nshell.domain.parsing:redirect-output-kind-p :unknown)))
    (is (not (nshell.domain.parsing:redirect-stderr-kind-p :unknown)))
    (is (not (nshell.domain.parsing:redirect-append-kind-p :unknown)))
    (multiple-value-bind (kind target)
        (nshell.domain.parsing:redirect-input-spec redirects)
      (is (eq :< kind))
      (is (string= "in.txt" target)))
    (is (string= "in.txt"
                 (nshell.domain.parsing:redirect-input-file-target redirects)))
    (multiple-value-bind (target mode)
        (nshell.domain.parsing:redirect-output-spec redirects)
      (is (string= "append.txt" target))
      (is (eq :append mode)))
    (multiple-value-bind (kind target mode)
        (nshell.domain.parsing:redirect-stderr-spec redirects)
      (is (eq :merge kind))
      (is (null target))
      (is (null mode)))
    (is (nshell.domain.parsing:redirect-output-p redirects))))

(test redirect-output-destinations-preserve-left-to-right-effects
  "Domain output destination resolution owns shell-significant redirect order."
  (multiple-value-bind (stdout-target stdout-mode stderr-target stderr-mode)
      (nshell.domain.parsing:redirect-output-destinations
       '((:2> . "early.err")
         (:> . "out.txt")
         (:2>&1 . nil)
         (:>> . "later.out")))
    (is (string= "later.out" stdout-target))
    (is (eq :append stdout-mode))
    (is (string= "out.txt" stderr-target))
    (is (eq :supersede stderr-mode)))
  (multiple-value-bind (stdout-target stdout-mode stderr-target stderr-mode)
      (nshell.domain.parsing:redirect-output-destinations
       '((:&>> . "all.log")))
    (is (string= "all.log" stdout-target))
    (is (eq :append stdout-mode))
    (is (string= "all.log" stderr-target))
    (is (eq :append stderr-mode)))
  (let* ((state (nshell.domain.parsing::%empty-redirect-output-destination-state))
         (stdout-state
           (nshell.domain.parsing::%redirect-output-destination-state-apply-entry
            state :> "out.txt"))
         (merged-state
           (nshell.domain.parsing::%redirect-output-destination-state-apply-entry
            stdout-state :2>&1 nil))
         (changed-stdout-state
           (nshell.domain.parsing::%redirect-output-destination-state-apply-entry
            merged-state :>> "later.out")))
    (is (string= "later.out"
                 (nshell.domain.parsing::%redirect-output-destination-state-stdout-target
                  changed-stdout-state)))
    (is (eq :append
            (nshell.domain.parsing::%redirect-output-destination-state-stdout-mode
             changed-stdout-state)))
    (is (string= "out.txt"
                 (nshell.domain.parsing::%redirect-output-destination-state-stderr-target
                  changed-stdout-state)))
    (is (eq :supersede
            (nshell.domain.parsing::%redirect-output-destination-state-stderr-mode
             changed-stdout-state)))))

(test map-redirect-entries-projects-kind-and-target
  "Redirect consumers receive projected values instead of raw cons cells."
  (let ((entries nil))
    (nshell.domain.parsing:map-redirect-entries
     (lambda (kind target)
       (push (list kind target) entries))
     '((:> . "out.txt")
       (:2>&1)))
    (is (equal '((:> "out.txt")
                 (:2>&1 nil))
               (nreverse entries)))))

(test split-command-node-redirects-preserves-dangling-operator
  "A trailing redirect operator should remain part of the command arguments."
  (multiple-value-bind (clean redirects)
      (nshell.domain.parsing:split-command-node-redirects
       (nshell.domain.parsing:make-command-node "echo" (list "hello" ">")))
    (is (equal '("hello" ">")
               (nshell.domain.parsing:command-node-arg-values clean)))
    (is (null redirects))))

(test split-command-node-redirects-preserves-left-to-right-order
  "Redirect extraction preserves shell-significant left-to-right order."
  (multiple-value-bind (clean redirects)
      (nshell.domain.parsing:split-command-node-redirects
       (nshell.domain.parsing:make-command-node
        "cmd"
        (list "arg" "2>&1" ">" "out" "2>" "err")))
    (is (equal '("arg")
               (nshell.domain.parsing:command-node-arg-values clean)))
    (is (equal '((:2>&1 . nil) (:> . "out") (:2> . "err"))
               redirects))))

(test split-command-node-redirects-projects-redirect-table-cases
  "Redirect splitting uses parser-domain redirect specs for supported redirect forms."
  (dolist (case '((("echo" ">" "out.txt")
                   ("echo")
                   ((:> . "out.txt")))
                  (("echo" ">>" "out.txt")
                   ("echo")
                   ((:>> . "out.txt")))
                  (("echo" "<" "in.txt")
                   ("echo")
                   ((:< . "in.txt")))
                  (("cat" "<<<" "bg")
                   ("cat")
                   ((:<<< . "bg")))
                  (("cat" "<<" "bg")
                   ("cat")
                   ((:<< . "bg")))))
    (destructuring-bind (words expected-clean expected-redirects) case
      (multiple-value-bind (clean redirects)
          (nshell.domain.parsing:split-command-node-redirects
           (nshell.domain.parsing:make-command-node
            (first words)
            (rest words)))
        (is (equal expected-clean
                   (cons (nshell.domain.parsing:command-node-command clean)
                         (nshell.domain.parsing:command-node-arg-values clean))))
        (is (equal expected-redirects redirects))))))

(test split-command-node-redirects-consumes-redirect-facts-boundary
  "Redirect splitting consumes parser-data facts for target and fd-dup redirects."
  (multiple-value-bind (clean redirects)
      (nshell.domain.parsing:split-command-node-redirects
       (nshell.domain.parsing:make-command-node
        "cmd" (list ">" "out.txt" "2>&1" "arg")))
    (is (equal '("arg")
               (nshell.domain.parsing:command-node-arg-values clean)))
    (is (equal '((:> . "out.txt") (:2>&1 . nil))
               redirects))))

(test separator-rule-entry-projects-separator-facts
  "Separator rule entries are the projection boundary for parser separator specs."
  (let ((pipe-entry (nshell.domain.parsing::%separator-rule-entry :pipe))
        (pipe-facts (nshell.domain.parsing::%separator-facts :pipe)))
    (is (every #'nshell.domain.parsing::%separator-rule-entry-p
               nshell.domain.parsing::+separator-rules+))
    (is (notany #'listp nshell.domain.parsing::+separator-rules+))
    (is (not (fboundp
              'nshell.domain.parsing::%separator-rule-entry-from-rule)))
    (is (nshell.domain.parsing::%separator-rule-entry-p pipe-entry))
    (is (eq :pipe
            (nshell.domain.parsing::%separator-rule-entry-kind pipe-entry)))
    (is (eq :pipe
            (nshell.domain.parsing::%separator-rule-entry-token-type
             pipe-entry)))
    (is (string= "|"
                 (nshell.domain.parsing::%separator-rule-entry-text
                  pipe-entry)))
    (is (nshell.domain.parsing::%separator-rule-entry-continues-p
         pipe-entry))
    (is (eq :pipe
            (nshell.domain.parsing::%separator-facts-kind pipe-facts)))
    (is (eq :pipe
            (nshell.domain.parsing::%separator-facts-token-type pipe-facts)))
    (is (string= "|"
                 (nshell.domain.parsing::%separator-facts-text pipe-facts)))
    (is (nshell.domain.parsing::%separator-facts-continues-p pipe-facts))))

(test separator-rule-entry-projects-token-type-lookup
  "Separator token-type lookup should not expose raw rule table shape."
  (let ((entry
          (nshell.domain.parsing::%separator-rule-entry-from-token-type
           :semicolon)))
    (is (nshell.domain.parsing::%separator-rule-entry-p entry))
    (is (eq :semi
            (nshell.domain.parsing::%separator-rule-entry-kind entry)))
    (is (eq :semicolon
            (nshell.domain.parsing::%separator-rule-entry-token-type entry)))
    (is (string= ";"
                 (nshell.domain.parsing::%separator-rule-entry-text entry)))
    (is (not (nshell.domain.parsing::%separator-rule-entry-continues-p
              entry)))
    (is (eq :semi
            (nshell.domain.parsing::%separator-from-token-type :semicolon)))
    (is (null
         (nshell.domain.parsing::%separator-rule-entry-from-token-type nil)))))

(test separator-facts-preserve-unknown-separator-fallback
  "Unknown non-nil separators keep display text without becoming continuations."
  (let ((entry (nshell.domain.parsing::%separator-rule-entry :custom-separator))
        (facts (nshell.domain.parsing::%separator-facts :custom-separator)))
    (is (nshell.domain.parsing::%separator-rule-entry-p entry))
    (is (eq :custom-separator
            (nshell.domain.parsing::%separator-rule-entry-kind entry)))
    (is (null (nshell.domain.parsing::%separator-rule-entry-token-type entry)))
    (is (string= "custom-separator"
                 (nshell.domain.parsing::%separator-rule-entry-text entry)))
    (is (not (nshell.domain.parsing::%separator-rule-entry-continues-p
              entry)))
    (is (eq :custom-separator
            (nshell.domain.parsing::%separator-facts-kind facts)))
    (is (null (nshell.domain.parsing::%separator-facts-token-type facts)))
    (is (string= "custom-separator"
                 (nshell.domain.parsing::%separator-facts-text facts)))
    (is (not (nshell.domain.parsing::%separator-facts-continues-p facts)))))

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

(test parser-assembly-builds-single-command-boundaries
  "Parser assembly should keep background metadata out of command nodes."
  (let* ((command (nshell.domain.parsing:make-command-node "sleep" '("1")))
         (foreground-ast
           (nshell.domain.parsing::%build-ast-from-reduced-entries
            (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
             (list (list command nil nil)))))
         (background-ast
           (nshell.domain.parsing::%build-ast-from-reduced-entries
            (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
             (list (list command :amp nil))))))
    (is (eq command foreground-ast))
    (is (nshell.domain.parsing:sequence-node-p background-ast))
    (is (equal '(:amp)
               (nshell.domain.parsing:sequence-node-separators background-ast)))
    (is (eq command
            (first (nshell.domain.parsing:sequence-node-commands
                    background-ast))))))

(test parser-assembly-projects-command-list-boundary
  "Parser assembly should project command-list pairs before AST construction."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("one")))
         (second-command (nshell.domain.parsing:make-command-node "cat" nil))
         (reducer-entries (list (list first-command :pipe nil)
                                (list second-command :amp nil)))
         (reduced-entries
           (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
            reducer-entries))
         (entries
           (nshell.domain.parsing::%command-list-entries-from-reduced-entries
            reduced-entries))
         (assembly
           (nshell.domain.parsing::%command-list-assembly-from-entries
            entries))
         (layout
           (nshell.domain.parsing::%command-list-assembly-separator-layout
            assembly)))
    (is (every #'nshell.domain.parsing::%reduced-command-entry-p
               reduced-entries))
    (is (every #'nshell.domain.parsing::%command-list-entry-p entries))
    (is (not (some #'listp entries)))
    (is (equal (list first-command second-command)
               (nshell.domain.parsing::%command-list-assembly-commands
                assembly)))
    (is (nshell.domain.parsing::%command-list-separator-layout-p layout))
    (is (equal '(:pipe :amp)
               (nshell.domain.parsing::%command-list-separator-layout-separators
                layout)))
    (is (equal '(:pipe)
               (nshell.domain.parsing::%command-list-separator-layout-boundary-separators
                layout)))
    (is (eq :amp
            (nshell.domain.parsing::%command-list-separator-layout-trailing-separator
             layout)))))

(test parser-assembly-command-list-cardinality-owns-single-command-projection
  "Command-list cardinality should own raw single-command list projection."
  (let* ((command (nshell.domain.parsing:make-command-node "echo" '("hi")))
         (projection
           (nshell.domain.parsing::%command-list-cardinality
            (list command))))
    (is (nshell.domain.parsing::%command-list-cardinality-p projection))
    (is (nshell.domain.parsing::%command-list-cardinality-single-command-p
         projection))
    (is (eq command
            (nshell.domain.parsing::%command-list-cardinality-single-command
             projection))))
  (let ((projection
          (nshell.domain.parsing::%command-list-cardinality
           (list (nshell.domain.parsing:make-command-node "echo" nil)
                 (nshell.domain.parsing:make-command-node "grep" nil)))))
    (is (nshell.domain.parsing::%command-list-cardinality-p projection))
    (is (not (nshell.domain.parsing::%command-list-cardinality-single-command-p
              projection)))
    (is (null (nshell.domain.parsing::%command-list-cardinality-single-command
               projection)))))

(test parser-assembly-projects-single-command-intent
  "Single-command assembly should expose command and background intent."
  (let* ((command (nshell.domain.parsing:make-command-node "sleep" '("1")))
         (foreground
           (nshell.domain.parsing::%command-list-assembly-from-reduced-entries
            (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
             (list (list command nil nil)))))
         (background
           (nshell.domain.parsing::%command-list-assembly-from-reduced-entries
            (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
             (list (list command :amp nil))))))
    (is (eq command
            (nshell.domain.parsing::%command-list-assembly-single-command
             foreground)))
    (is (not (nshell.domain.parsing::%command-list-assembly-background-p
              foreground)))
    (is (nshell.domain.parsing::%command-list-assembly-background-p
         background))
    (is (eq command
            (nshell.domain.parsing::%single-command-ast foreground)))
    (let ((background-ast
            (nshell.domain.parsing::%single-command-ast background)))
      (is (nshell.domain.parsing:sequence-node-p background-ast))
      (is (equal '(:amp)
                 (nshell.domain.parsing:sequence-node-separators
                  background-ast)))
      (is (eq command
              (first (nshell.domain.parsing:sequence-node-commands
                      background-ast)))))))

(test parser-assembly-background-command-list-ast-wraps-one-command
  "Background command-list AST wrapping should own the singleton sequence projection."
  (let* ((command (nshell.domain.parsing:make-command-node "sleep" '("1")))
         (ast (nshell.domain.parsing::%background-command-list-ast command)))
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (equal (list command)
               (nshell.domain.parsing:sequence-node-commands ast)))
    (is (equal '(:amp)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parser-assembly-projects-command-separator-pairs
  "Mixed sequence assembly should expose command boundaries as value objects."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("one")))
         (second-command (nshell.domain.parsing:make-command-node "cat" nil))
         (source (nshell.domain.parsing::%make-command-separator-pair-source
                  (list first-command second-command)
                  '(:pipe :and)))
         (pairs (nshell.domain.parsing::%command-separator-pairs source))
         (first-pair (first pairs))
         (second-pair (second pairs)))
    (is (nshell.domain.parsing::%command-separator-pair-source-p source))
    (is (= 2 (length pairs)))
    (is (nshell.domain.parsing::%command-separator-pair-p first-pair))
    (is (eq first-command
            (nshell.domain.parsing::%command-separator-pair-command
             first-pair)))
    (is (eq :pipe
            (nshell.domain.parsing::%command-separator-pair-separator
             first-pair)))
    (is (nshell.domain.parsing::%command-separator-pair-p second-pair))
    (is (eq second-command
            (nshell.domain.parsing::%command-separator-pair-command
             second-pair)))
    (is (eq :and
            (nshell.domain.parsing::%command-separator-pair-separator
             second-pair)))))

(test parser-assembly-projects-mixed-sequence-assembly
  "Mixed sequence building should consume a projected assembly input."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("one")))
         (second-command (nshell.domain.parsing:make-command-node "grep" '("two")))
         (third-command (nshell.domain.parsing:make-command-node "wc" nil))
         (assembly
           (nshell.domain.parsing::%command-list-assembly-from-reduced-entries
            (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
             (list (list first-command :pipe nil)
                   (list second-command :and nil)
                   (list third-command nil nil)))))
         (mixed
           (nshell.domain.parsing::%mixed-sequence-assembly-from-command-list-assembly
            assembly))
         (layout
           (nshell.domain.parsing::%mixed-sequence-assembly-separator-layout
            mixed))
         (pairs
           (nshell.domain.parsing::%mixed-sequence-assembly-pairs mixed)))
    (is (nshell.domain.parsing::%mixed-sequence-assembly-p mixed))
    (is (equal (list first-command second-command third-command)
               (nshell.domain.parsing::%mixed-sequence-assembly-commands
                mixed)))
    (is (nshell.domain.parsing::%command-list-separator-layout-p layout))
    (is (equal '(:pipe :and nil)
               (nshell.domain.parsing::%command-list-separator-layout-separators
                layout)))
    (is (= 3 (length pairs)))
    (is (eq :and
            (nshell.domain.parsing::%command-separator-pair-separator
             (second pairs))))))

(test parser-assembly-projects-pipeline-groups
  "Mixed sequence assembly should project pending pipeline groups before AST construction."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("one")))
         (second-command (nshell.domain.parsing:make-command-node "cat" nil))
         (single-group
           (nshell.domain.parsing::%pipeline-group-from-reversed
            (list first-command)))
         (pipeline-group
           (nshell.domain.parsing::%pipeline-group-from-reversed
            (list second-command first-command)))
         (pipeline-ast
           (nshell.domain.parsing::%pipeline-group-ast pipeline-group)))
    (is (nshell.domain.parsing::%pipeline-group-p single-group))
    (is (equal (list first-command)
               (nshell.domain.parsing::%pipeline-group-commands
                single-group)))
    (is (eq first-command
            (nshell.domain.parsing::%pipeline-group-ast single-group)))
    (is (equal (list first-command second-command)
               (nshell.domain.parsing::%pipeline-group-commands
                pipeline-group)))
    (is (nshell.domain.parsing:pipeline-node-p pipeline-ast))
    (is (equal (list first-command second-command)
               (nshell.domain.parsing:pipeline-node-commands
                pipeline-ast)))))

(test parser-assembly-flushes-pipeline-group-through-value-object
  "Mixed sequence pipe flushing should expose accumulator state as one value object."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("one")))
         (second-command (nshell.domain.parsing:make-command-node "cat" nil))
         (pending-group
           (nshell.domain.parsing::%pending-pipeline-group-push
            (nshell.domain.parsing::%pending-pipeline-group-push
             (nshell.domain.parsing::%empty-pending-pipeline-group)
             first-command)
            second-command))
         (flush
           (nshell.domain.parsing::%flush-mixed-sequence-pipe-group
             nil
             pending-group))
          (sequence-commands
            (nshell.domain.parsing::%mixed-sequence-pipe-flush-sequence-commands
             flush)))
    (is (nshell.domain.parsing::%mixed-sequence-pipe-flush-p flush))
    (is (nshell.domain.parsing::%pending-pipeline-group-p pending-group))
    (is (nshell.domain.parsing::%pending-pipeline-group-empty-p
         (nshell.domain.parsing::%mixed-sequence-pipe-flush-pipe-group
          flush)))
    (is (= 1 (length sequence-commands)))
    (is (nshell.domain.parsing:pipeline-node-p (first sequence-commands)))
    (is (equal (list first-command second-command)
               (nshell.domain.parsing:pipeline-node-commands
                (first sequence-commands))))))

(test parser-assembly-build-state-accepts-pair-through-value-object
  "Mixed sequence building should transition through a single state value."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("one")))
         (pair
           (nshell.domain.parsing::%make-command-separator-pair
            first-command
            :and))
         (state
           (nshell.domain.parsing::%mixed-sequence-build-state-accept-pair
            (nshell.domain.parsing::%empty-mixed-sequence-build-state)
            pair))
         (sequence-commands
           (nshell.domain.parsing::%mixed-sequence-build-state-sequence-commands
            state)))
    (is (nshell.domain.parsing::%mixed-sequence-build-state-p state))
    (is (nshell.domain.parsing::%pending-pipeline-group-empty-p
         (nshell.domain.parsing::%mixed-sequence-build-state-pipe-group
          state)))
    (is (= 1 (length sequence-commands)))
    (is (eq first-command (first sequence-commands)))
    (is (equal '(:and)
               (nshell.domain.parsing::%mixed-sequence-build-state-sequence-separators
                state)))))

(test parser-assembly-classifies-command-list-policy
  "Parser assembly policy should classify command-list shape before building AST nodes."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" '("one")))
         (second-command (nshell.domain.parsing:make-command-node "cat" nil))
         (third-command (nshell.domain.parsing:make-command-node "wc" nil)))
    (flet ((policy (command-list)
             (nshell.domain.parsing::%command-list-assembly-policy
              (nshell.domain.parsing::%command-list-assembly-from-reduced-entries
               (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
                command-list)))))
      (is (eq :empty (policy nil)))
      (is (eq :single-command
              (policy (list (list first-command nil nil)))))
      (is (eq :pipeline
              (policy (list (list first-command :pipe nil)
                            (list second-command nil nil)))))
      (is (eq :sequence
              (policy (list (list first-command :semi nil)
                            (list second-command nil nil)))))
      (is (eq :mixed-sequence
              (policy (list (list first-command :pipe nil)
                            (list second-command :and nil)
                            (list third-command nil nil))))))))

(test parser-assembly-decision-keeps-policy-with-projection
  "Assembly decisions should bind the projected command-list shape to its AST policy."
  (let* ((first-command (nshell.domain.parsing:make-command-node "echo" nil))
         (second-command (nshell.domain.parsing:make-command-node "cat" nil))
         (assembly
           (nshell.domain.parsing::%command-list-assembly-from-reduced-entries
            (nshell.domain.parsing::%reduced-command-entries-from-reducer-entries
             (list (list first-command :pipe nil)
                   (list second-command :amp nil)))))
         (decision
           (nshell.domain.parsing::%command-list-assembly-decision-from-assembly
            assembly)))
    (is (nshell.domain.parsing::%command-list-assembly-decision-p decision))
    (is (eq assembly
            (nshell.domain.parsing::%command-list-assembly-decision-assembly
             decision)))
    (is (eq :pipeline
            (nshell.domain.parsing::%command-list-assembly-decision-policy
             decision)))))

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
  (let* ((state (nshell.domain.parsing::%make-token-reduction-state))
         (command-token (nshell.domain.parsing:make-token :word "echo" 0 4))
         (separator-token (nshell.domain.parsing:make-token :pipe "|" 5 6)))
    (setf (nshell.domain.parsing::%token-reduction-state-current-cmd state) "echo"
          (nshell.domain.parsing::%token-reduction-state-current-cmd-token state) command-token
          (nshell.domain.parsing::%token-reduction-state-current-args state) (list "hello")
          (nshell.domain.parsing::%token-reduction-state-pending-sep state) :pipe
          (nshell.domain.parsing::%token-reduction-state-pending-sep-token state) separator-token)
    (destructuring-bind (command separator token)
        (nshell.domain.parsing::%token-reduction-command-entry-from-state state)
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command command)))
      (is (equal '("hello")
                 (nshell.domain.parsing:command-node-arg-values command)))
      (is (eq :pipe separator))
      (is (eq separator-token token)))))

(test parser-reduction-result-projects-state-boundary
  "Token reduction result is the projection boundary for commands and diagnostics."
  (let* ((separator-token (nshell.domain.parsing:make-token :pipe "|" 7 8))
         (result
           (nshell.domain.parsing::%reduce-token-stream-result
            (list (nshell.domain.parsing:make-token :word "echo" 0 4)
                  (nshell.domain.parsing:make-token :redirect ">" 5 6)
                  separator-token))))
    (is (nshell.domain.parsing::%token-reduction-result-p result))
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
    (is (string= (format nil "one~%")
                 (nshell.domain.parsing::%here-doc-body-body body)))
    (is (= 8
           (nshell.domain.parsing::%here-doc-body-next-position body)))
    (is (not
         (nshell.domain.parsing::%here-doc-body-missing-delimiter-p body)))))

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
    (is (string= "first"
                 (nshell.domain.parsing::%here-doc-target-body-cursor-body cursor)))
    (is (equal '("second")
               (nshell.domain.parsing::%here-doc-target-body-cursor-remaining-bodies
                cursor)))))

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
