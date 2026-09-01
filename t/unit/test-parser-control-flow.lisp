(in-package #:nshell/test)

(describe "parser-tests"
  (it "parser-value-objects-preserve-domain-data"
    "Parser data records retain their typed values across construction."
    (let* ((scan (nshell.domain.parsing::%make-here-doc-delimiter-scan '("EOF")))
           (line (nshell.domain.parsing::%make-here-doc-line "body" 4 t))
           (body (nshell.domain.parsing::%make-here-doc-body "body\n" 5 nil))
           (consumption (nshell.domain.parsing::%make-here-doc-consumption
                         (list body) 5 t))
           (state (nshell.domain.parsing::%make-here-doc-consumption-state
                   (list body) 5 t))
           (reduction (nshell.domain.parsing::%make-token-reduction-state
                       :all-cmds '("echo")
                       :current-args '("body")
                       :current-cmd "cat"
                       :errors '(:error)))
           (result (nshell.domain.parsing::%make-token-reduction-result
                    '("cat") '(:error)))
           (argument (nshell.domain.parsing::%make-token-reduction-argument
                      "body" :single t nil))
           (policy (nshell.domain.parsing::%make-token-reduction-diagnostic-policy
                    :error "invalid")))
      (expect '("EOF") :to-equal
              (nshell.domain.parsing::%here-doc-delimiter-scan-reversed-delimiters scan))
      (expect '("body") :to-equal
              (list (nshell.domain.parsing::%here-doc-line-text line)))
      (expect (nshell.domain.parsing::%here-doc-line-newline-p line)
              :to-be-truthy)
      (expect "body\n" :to-equal
              (nshell.domain.parsing::%here-doc-body-body body))
      (expect (nshell.domain.parsing::%here-doc-body-missing-delimiter-p body)
              :to-be-falsy)
      (expect (list body) :to-equal
              (nshell.domain.parsing::%here-doc-consumption-bodies consumption))
      (expect (nshell.domain.parsing::%here-doc-consumption-incomplete-p consumption)
              :to-be-truthy)
      (expect (list body) :to-equal
              (nshell.domain.parsing::%here-doc-consumption-state-reversed-bodies state))
      (expect '("echo") :to-equal
              (nshell.domain.parsing::%token-reduction-state-all-cmds reduction))
      (expect '("cat") :to-equal
              (nshell.domain.parsing::%token-reduction-result-commands result))
      (expect "body" :to-equal
              (nshell.domain.parsing::%token-reduction-argument-value argument))
      (expect :single :to-equal
              (nshell.domain.parsing::%token-reduction-argument-quote-style argument))
      (expect :error :to-equal
              (nshell.domain.parsing::%token-reduction-diagnostic-policy-kind policy))
      (expect "invalid" :to-equal
              (nshell.domain.parsing::%token-reduction-diagnostic-policy-message policy))))

  (it "parse-incomplete-control-flow-blocks"
    (do-command-lines (line '("if true"
                              "for item in a b"
                              "while true"
                              "begin"
                              "switch chocolate"))
      (with-parsed-command-line (result line)
        (with-last-parsed-diagnostic (diagnostic result line)
          (assert-parsed-diagnostic result diagnostic
                                    :present t
                                    :incomplete t
                                    :kind :unclosed-block))))
    (with-parsed-command-line (result "if true; echo ok; end")
      (expect (nshell.domain.parsing:parse-result-incomplete result) :to-be-falsy)
      (expect (nshell.domain.parsing:parse-complete-p result) :to-be-truthy)))

  (it "parse-unmatched-control-flow-terminators"
    (do-command-lines (line '("else"
                              "end"
                              "if true; else; else; end"))
      (with-parsed-command-line (result line)
        (with-parsed-diagnostic-of-kind (diagnostic result line :unexpected-control-flow)
          (assert-parsed-diagnostic result diagnostic
                                    :present t
                                    :kind :unexpected-control-flow
                                    :within-input t
                                    :line line)
          (expect (nshell.domain.parsing:parse-complete-p result) :to-be-falsy)))))

  (it "parse-switch-case-without-end-is-incomplete-not-unexpected"
    (with-parsed-command-line (result "switch chocolate; case vanilla")
      (let ((kinds (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                           (nshell.domain.parsing:parse-errors result))))
        (expect (nshell.domain.parsing:parse-result-incomplete result) :to-be-truthy)
        (expect (member :unclosed-block kinds) :to-be-truthy)
        (expect (member :unexpected-control-flow kinds) :to-be-falsy))))

  (it "parse-case-outside-switch-is-an-error"
    (with-parsed-command-line (result "case vanilla")
      (with-parsed-diagnostic-of-kind (diagnostic result "case vanilla" :unexpected-control-flow)
        (assert-parsed-diagnostic result diagnostic
                                  :present t
                                  :kind :unexpected-control-flow)
        (expect (nshell.domain.parsing:parse-complete-p result) :to-be-falsy))))

  (it "parse-case-with-body-outside-switch-is-an-error"
    "A case clause with a body still reports the control-flow boundary error."
    (with-parsed-command-line (result "case vanilla; echo plain")
      (with-parsed-diagnostic-of-kind (diagnostic result "case vanilla; echo plain" :unexpected-control-flow)
        (assert-parsed-diagnostic result diagnostic
                                  :present t
                                  :kind :unexpected-control-flow)
        (expect (nshell.domain.parsing:parse-complete-p result) :to-be-falsy))))

  (it "control-flow-stack-transition-projects-frame-rules"
    "Control-flow diagnostics should share one typed frame transition boundary."
    (let ((if-command (nshell.domain.parsing:make-command-node "if" '("true")))
          (else-command (nshell.domain.parsing:make-command-node "else" nil))
          (end-command (nshell.domain.parsing:make-command-node "end" nil))
          (switch-command (nshell.domain.parsing:make-command-node "switch" '("value")))
          (case-command (nshell.domain.parsing:make-command-node "case" '("value"))))
      (let* ((if-transition
               (nshell.domain.parsing::%control-flow-stack-transition
                nil if-command))
             (if-stack
               (nshell.domain.parsing::%control-flow-stack-transition-stack
                if-transition))
             (else-transition
               (nshell.domain.parsing::%control-flow-stack-transition
                if-stack else-command))
             (else-stack
               (nshell.domain.parsing::%control-flow-stack-transition-stack
                else-transition))
             (second-else-transition
               (nshell.domain.parsing::%control-flow-stack-transition
                else-stack else-command))
             (same-stack
               (nshell.domain.parsing::%control-flow-stack-transition-stack
                second-else-transition))
             (end-transition
               (nshell.domain.parsing::%control-flow-stack-transition
                same-stack end-command)))
        (assert-control-flow-stack-transition
            (nshell.domain.parsing::%control-flow-stack-transition
             nil if-command)
          :transition-p t
          :copy-absent t
          :unexpected nil
          :frame-keyword "if")
        (assert-control-flow-stack-transition
            else-transition
          :transition-p t
          :unexpected nil
          :frame-else-seen t)
        (expect (eq (first if-stack)
                     (first else-stack)) :to-be-falsy)
        (expect (nshell.domain.parsing::control-flow-frame-else-seen
                  (first if-stack)) :to-be-falsy)
        (expect (nshell.domain.parsing::control-flow-frame-else-seen
             (first else-stack)) :to-be-truthy)
        (assert-control-flow-stack-transition
            second-else-transition
          :transition-p t
          :unexpected "else"
          :stack-eq else-stack)
        (assert-control-flow-stack-transition
            end-transition
          :transition-p t
          :unexpected nil
          :stack-null t))
      (let* ((switch-transition
               (nshell.domain.parsing::%control-flow-stack-transition
                nil switch-command))
             (switch-stack
               (nshell.domain.parsing::%control-flow-stack-transition-stack
                switch-transition))
             (case-transition
               (nshell.domain.parsing::%control-flow-stack-transition
                switch-stack case-command)))
        (assert-control-flow-stack-transition
            switch-transition
          :transition-p t
          :unexpected nil)
        (assert-control-flow-stack-transition
            case-transition
          :transition-p t
          :unexpected nil
          :stack-eq switch-stack))
      (let ((case-transition
              (nshell.domain.parsing::%control-flow-stack-transition
               nil case-command)))
        (assert-control-flow-stack-transition
            case-transition
          :transition-p t
          :stack-null t
          :unexpected "case"))))

  (it "control-flow-stack-transition-rejects-legacy-string-frames"
    "Control-flow diagnostic stacks should contain typed frames only."
    (let* ((case-command (nshell.domain.parsing:make-command-node
                          "case"
                          '("value")))
           (legacy-stack '("switch"))
           (transition
             (nshell.domain.parsing::%control-flow-stack-transition
              legacy-stack
              case-command)))
      (expect legacy-stack :to-be (nshell.domain.parsing::%control-flow-stack-transition-stack
               transition))
      (expect "case" :to-equal (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
                    transition))))

  (it "control-flow-diagnostic-span-projects-node-boundary"
    "Unexpected control-flow diagnostics should consume a typed span projection."
    (let* ((node (nshell.domain.parsing:make-command-node
                  "else" nil '(7 11)))
           (node-span
             (nshell.domain.parsing::%control-flow-node-span-from-raw-span
              (nshell.domain.parsing::ast-node-span node)))
           (span
             (nshell.domain.parsing::%control-flow-diagnostic-span-from-node
              node 20))
           (fallback
             (nshell.domain.parsing::%control-flow-diagnostic-span-from-node
              (nshell.domain.parsing:make-command-node "else" nil)
              20)))
      (expect (nshell.domain.parsing::%control-flow-node-span-p node-span) :to-be-truthy)
      (expect (fboundp
                'nshell.domain.parsing::copy-%control-flow-node-span) :to-be-falsy)
      (expect (fboundp
                'nshell.domain.parsing::copy-%control-flow-diagnostic-span) :to-be-falsy)
      (expect 7 :to-equal (nshell.domain.parsing::%control-flow-node-span-start node-span))
      (expect 11 :to-equal (nshell.domain.parsing::%control-flow-node-span-end node-span))
      (expect (nshell.domain.parsing::%control-flow-node-span-from-raw-span nil) :to-be-null)
      (expect (nshell.domain.parsing::%control-flow-diagnostic-span-p span) :to-be-truthy)
      (expect 7 :to-equal (nshell.domain.parsing::%control-flow-diagnostic-span-start span))
      (expect 11 :to-equal (nshell.domain.parsing::%control-flow-diagnostic-span-end span))
      (expect 20 :to-equal (nshell.domain.parsing::%control-flow-diagnostic-span-start
              fallback))
      (expect 20 :to-equal (nshell.domain.parsing::%control-flow-diagnostic-span-end
              fallback))))

  (it "control-flow-header-args-project-command-argument-boundary"
    "Control-flow header helpers should consume one typed argument projection."
    (let* ((header (nshell.domain.parsing:make-command-node
                    "else"
                    (list (nshell.domain.parsing:make-command-arg "if" :double)
                          "false"
                          "extra")))
           (header-args (nshell.domain.parsing::%control-flow-header-args header))
           (condition (nshell.domain.parsing::%command-from-header-args header)))
      (expect (nshell.domain.parsing::%control-flow-header-args-p header-args) :to-be-truthy)
      (expect (fboundp
                'nshell.domain.parsing::copy-%control-flow-header-args) :to-be-falsy)
      (expect "if" :to-equal (nshell.domain.parsing:arg-value
                    (nshell.domain.parsing::%control-flow-header-args-first
                     header-args)))
      (expect '("false" "extra") :to-equal (mapcar #'nshell.domain.parsing:arg-value
                         (nshell.domain.parsing::%control-flow-header-args-rest
                          header-args)))
      (expect '("if" "false" "extra") :to-equal (mapcar #'nshell.domain.parsing:arg-value
                         (nshell.domain.parsing::%control-flow-header-args-all
                          header-args)))
      (expect (nshell.domain.parsing::%else-if-header-p header) :to-be-truthy)
      (expect "if" :to-equal (nshell.domain.parsing:command-node-command condition))
      (expect :double :to-be (nshell.domain.parsing:command-node-command-quote-style condition))
      (expect '("false" "extra") :to-equal (nshell.domain.parsing:command-node-arg-values condition))
      (expect "*" :to-equal (nshell.domain.parsing::%command-first-arg-value
                    (nshell.domain.parsing:make-command-node "case" nil)
                    "*"))))

  (it "control-flow-for-header-binding-projects-loop-variable-and-values"
    "For grouping should consume a typed loop-binding projection from the header."
    (let* ((explicit-header (nshell.domain.parsing:make-command-node
                             "for"
                             (list (nshell.domain.parsing:make-command-arg
                                    "item"
                                    :double)
                                   "in"
                                   "a"
                                   "b")))
           (explicit-binding
             (nshell.domain.parsing::%control-flow-for-header-binding-from-header
              explicit-header))
           (implicit-header (nshell.domain.parsing:make-command-node
                             "for"
                             '("item" "a" "b")))
           (implicit-binding
             (nshell.domain.parsing::%control-flow-for-header-binding-from-header
              implicit-header)))
      (expect (nshell.domain.parsing::%control-flow-for-header-binding-p
           explicit-binding) :to-be-truthy)
      (expect "item" :to-equal (nshell.domain.parsing::%control-flow-for-header-binding-var-name
                    explicit-binding))
      (expect '("a" "b") :to-equal (mapcar #'nshell.domain.parsing:arg-value
                         (nshell.domain.parsing::%control-flow-for-header-binding-in-values
                          explicit-binding)))
        (expect '("a" "b") :to-equal (mapcar #'nshell.domain.parsing:arg-value
                           (nshell.domain.parsing::%control-flow-for-header-binding-in-values
                            implicit-binding)))))

  (it "control-flow-body-scan-projects-body-rest-and-terminator"
    "Control-flow block body grouping should return one typed scan result."
    (let* ((body-command (nshell.domain.parsing:make-command-node
                          "echo"
                          '("inside")))
           (else-command (nshell.domain.parsing:make-command-node
                          "else"
                          nil))
           (after-command (nshell.domain.parsing:make-command-node
                           "echo"
                           '("after")))
           (nodes (list body-command else-command after-command))
           (scan (nshell.domain.parsing::%group-control-flow-body
                  nodes
                  '("else" "end"))))
      (expect (nshell.domain.parsing::%control-flow-body-scan-p scan) :to-be-truthy)
      (expect (list body-command) :to-equal (nshell.domain.parsing::%control-flow-body-scan-body scan))
      (expect (rest nodes) :to-be (nshell.domain.parsing::%control-flow-body-scan-rest scan))
      (expect "else" :to-equal (nshell.domain.parsing::%control-flow-body-scan-terminator
                     scan))))

  (it "control-flow-node-grouping-projects-node-and-rest"
    "Control-flow node grouping should return one typed node/rest projection."
    (let* ((command (nshell.domain.parsing:make-command-node
                     "echo"
                     '("hello")))
           (after-command (nshell.domain.parsing:make-command-node
                           "echo"
                           '("after")))
           (commands (list command after-command))
           (plain-grouping
             (nshell.domain.parsing::%group-control-flow-next commands))
           (begin-header (nshell.domain.parsing:make-command-node "begin" nil))
           (body-command (nshell.domain.parsing:make-command-node
                          "echo"
                          '("inside")))
           (end-command (nshell.domain.parsing:make-command-node "end" nil))
           (block-commands (list begin-header
                                 body-command
                                 end-command
                                 after-command))
           (block-grouping
             (nshell.domain.parsing::%group-control-flow-next block-commands)))
      (expect (nshell.domain.parsing::%control-flow-node-grouping-p
           plain-grouping) :to-be-truthy)
      (expect command :to-be (nshell.domain.parsing::%control-flow-node-grouping-node
               plain-grouping))
      (expect (rest commands) :to-be (nshell.domain.parsing::%control-flow-node-grouping-rest
               plain-grouping))
      (expect (nshell.domain.parsing::%control-flow-node-grouping-p
           block-grouping) :to-be-truthy)
      (expect (nshell.domain.parsing:begin-end-node-p
           (nshell.domain.parsing::%control-flow-node-grouping-node
            block-grouping)) :to-be-truthy)
      (expect (nthcdr 3 block-commands) :to-be (nshell.domain.parsing::%control-flow-node-grouping-rest
               block-grouping))))

  (it "control-flow-clause-scan-projects-clauses-and-rest"
    "Control-flow clause grouping should return one typed scan result."
    (let* ((case-header (nshell.domain.parsing:make-command-node
                         "case"
                         '("fruit")))
           (clause-header (nshell.domain.parsing:make-command-node
                           "apple"
                           nil))
           (body-command (nshell.domain.parsing:make-command-node
                          "echo"
                          '("red")))
           (end-command (nshell.domain.parsing:make-command-node
                         "end"
                         nil))
           (after-command (nshell.domain.parsing:make-command-node
                           "echo"
                           '("after")))
           (nodes (list case-header
                        clause-header
                        body-command
                        end-command
                        after-command))
           (scan (nshell.domain.parsing::%group-control-flow-clauses
                  nodes
                  (lambda (clause-nodes)
                    (let ((body-scan
                            (nshell.domain.parsing::%group-control-flow-body
                             (rest clause-nodes)
                             '("end"))))
                      (nshell.domain.parsing::%make-control-flow-clause-parse-result
                       (list (cons (nshell.domain.parsing:command-node-command
                                    (first clause-nodes))
                                   (nshell.domain.parsing::%control-flow-body-scan-body
                                    body-scan)))
                       (nshell.domain.parsing::%control-flow-body-scan-rest
                        body-scan)))))))
      (expect (nshell.domain.parsing::%control-flow-clause-scan-p scan) :to-be-truthy)
      (expect (list (cons "apple" (list body-command))) :to-equal (nshell.domain.parsing::%control-flow-clause-scan-clauses scan))
      (expect (nthcdr 4 nodes) :to-be (nshell.domain.parsing::%control-flow-clause-scan-rest scan))))

  (it "control-flow-switch-case-patterns-project-default-and-explicit-patterns"
    "Switch grouping should consume a typed case-pattern projection from case headers."
    (let* ((explicit-header (nshell.domain.parsing:make-command-node
                             "case"
                             (list (nshell.domain.parsing:make-command-arg
                                    "vanilla"
                                    :single)
                                   "chocolate")))
           (explicit-patterns
             (nshell.domain.parsing::%control-flow-switch-case-patterns-from-header
              explicit-header))
           (default-header (nshell.domain.parsing:make-command-node
                            "case"
                            nil))
           (default-patterns
             (nshell.domain.parsing::%control-flow-switch-case-patterns-from-header
              default-header)))
      (expect (nshell.domain.parsing::%control-flow-switch-case-patterns-p
           explicit-patterns) :to-be-truthy)
      (expect '("vanilla" "chocolate") :to-equal (nshell.domain.parsing::%control-flow-switch-case-patterns-values
                  explicit-patterns))
      (expect '("*") :to-equal (nshell.domain.parsing::%control-flow-switch-case-patterns-values
                  default-patterns))))

  (it "parse-fish-switch-case-block"
    (with-complete-command-line (result ast
                                 "switch chocolate; case vanilla; echo plain; case chocolate strawberry; echo sweet; case '*'; echo default; end")
      (let ((clauses (and (nshell.domain.parsing:case-node-p ast)
                          (nshell.domain.parsing:case-node-clauses ast))))
        (expect (nshell.domain.parsing:case-node-p ast) :to-be-truthy)
        (expect "chocolate" :to-equal (nshell.domain.parsing:case-node-value ast))
        (expect (every #'nshell.domain.parsing:case-clause-p clauses) :to-be-truthy)
        (expect '("vanilla" "chocolate" "strawberry" "*") :to-equal (mapcar #'nshell.domain.parsing:case-clause-pattern
                           clauses))
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command
                      (first (nshell.domain.parsing:case-clause-body
                              (second clauses))))))))

  (it "parse-switch-without-explicit-case-uses-default-clause"
    "A switch body without a case header becomes the default pattern clause."
    (with-complete-command-line (result ast "switch; echo default; end")
      (let ((clause (first (nshell.domain.parsing:case-node-clauses ast))))
        (expect (nshell.domain.parsing:case-node-p ast) :to-be-truthy)
        (expect "*" :to-equal (nshell.domain.parsing:case-clause-pattern clause))
        (expect "echo" :to-equal
                (nshell.domain.parsing:command-node-command
                 (first (nshell.domain.parsing:case-clause-body clause)))))))

  (it "parse-else-if-becomes-nested-if-branch"
    (with-complete-ast (ast "if true; echo yes; else if false; echo no; end")
      (let ((else-branch (nshell.domain.parsing:if-node-else-branch ast)))
        (expect (nshell.domain.parsing:if-node-p ast) :to-be-truthy)
        (expect "true" :to-equal (nshell.domain.parsing:command-node-command
                      (nshell.domain.parsing:if-node-condition ast)))
        (expect 1 :to-equal (length else-branch))
        (let ((nested-if (first else-branch)))
          (expect (nshell.domain.parsing:if-node-p nested-if) :to-be-truthy)
          (expect "false" :to-equal (nshell.domain.parsing:command-node-command
                        (nshell.domain.parsing:if-node-condition nested-if)))
          (expect "echo" :to-equal (nshell.domain.parsing:command-node-command
                        (first (nshell.domain.parsing:if-node-then-branch nested-if))))
          (expect '("no") :to-equal (nshell.domain.parsing:command-node-arg-values
                      (first (nshell.domain.parsing:if-node-then-branch nested-if))))))))

  (it "parse-else-if-preserves-nested-else-branch"
    (with-complete-ast (ast "if false; echo no; else if false; echo maybe; else; echo yes; end")
      (let* ((else-branch (nshell.domain.parsing:if-node-else-branch ast))
             (nested-if (first else-branch))
             (nested-else (nshell.domain.parsing:if-node-else-branch nested-if)))
        (expect (nshell.domain.parsing:if-node-p ast) :to-be-truthy)
        (expect 1 :to-equal (length else-branch))
        (expect (nshell.domain.parsing:if-node-p nested-if) :to-be-truthy)
        (expect "false" :to-equal (nshell.domain.parsing:command-node-command
                      (nshell.domain.parsing:if-node-condition nested-if)))
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command
                      (first nested-else)))
        (expect '("yes") :to-equal (nshell.domain.parsing:command-node-arg-values
                    (first nested-else)))))))
