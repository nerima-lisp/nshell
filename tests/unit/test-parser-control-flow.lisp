(in-package #:nshell/test)

(in-suite parser-tests)

(test parse-incomplete-control-flow-blocks
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
    (is (not (nshell.domain.parsing:parse-result-incomplete result)))
    (is (nshell.domain.parsing:parse-complete-p result))))

(test parse-unmatched-control-flow-terminators
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
        (is (not (nshell.domain.parsing:parse-complete-p result))
            "~s should not parse completely" line)))))

(test parse-switch-case-without-end-is-incomplete-not-unexpected
  (with-parsed-command-line (result "switch chocolate; case vanilla")
    (let ((kinds (mapcar #'nshell.domain.parsing:parse-diagnostic-kind
                         (nshell.domain.parsing:parse-errors result))))
      (is (nshell.domain.parsing:parse-result-incomplete result))
      (is (member :unclosed-block kinds))
      (is (not (member :unexpected-control-flow kinds))))))

(test parse-case-outside-switch-is-an-error
  (with-parsed-command-line (result "case vanilla")
    (with-parsed-diagnostic-of-kind (diagnostic result "case vanilla" :unexpected-control-flow)
      (assert-parsed-diagnostic result diagnostic
                                :present t
                                :kind :unexpected-control-flow)
      (is (not (nshell.domain.parsing:parse-complete-p result))))))

(test control-flow-stack-transition-projects-frame-rules
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
      (is (not (eq (first if-stack)
                   (first else-stack))))
      (is (not (nshell.domain.parsing::control-flow-frame-else-seen
                (first if-stack))))
      (is (nshell.domain.parsing::control-flow-frame-else-seen
           (first else-stack)))
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

(test control-flow-stack-transition-rejects-legacy-string-frames
  "Control-flow diagnostic stacks should contain typed frames only."
  (let* ((case-command (nshell.domain.parsing:make-command-node
                        "case"
                        '("value")))
         (legacy-stack '("switch"))
         (transition
           (nshell.domain.parsing::%control-flow-stack-transition
            legacy-stack
            case-command)))
    (is (eq legacy-stack
            (nshell.domain.parsing::%control-flow-stack-transition-stack
             transition)))
    (is (string= "case"
                 (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
                  transition)))))

(test control-flow-diagnostic-span-projects-node-boundary
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
    (is (nshell.domain.parsing::%control-flow-node-span-p node-span))
    (is (not (fboundp
              'nshell.domain.parsing::copy-%control-flow-node-span)))
    (is (not (fboundp
              'nshell.domain.parsing::copy-%control-flow-diagnostic-span)))
    (is (= 7
           (nshell.domain.parsing::%control-flow-node-span-start node-span)))
    (is (= 11
           (nshell.domain.parsing::%control-flow-node-span-end node-span)))
    (is (null
         (nshell.domain.parsing::%control-flow-node-span-from-raw-span nil)))
    (is (nshell.domain.parsing::%control-flow-diagnostic-span-p span))
    (is (= 7
           (nshell.domain.parsing::%control-flow-diagnostic-span-start span)))
    (is (= 11
           (nshell.domain.parsing::%control-flow-diagnostic-span-end span)))
    (is (= 20
           (nshell.domain.parsing::%control-flow-diagnostic-span-start
            fallback)))
    (is (= 20
           (nshell.domain.parsing::%control-flow-diagnostic-span-end
            fallback)))))

(test control-flow-header-args-project-command-argument-boundary
  "Control-flow header helpers should consume one typed argument projection."
  (let* ((header (nshell.domain.parsing:make-command-node
                  "else"
                  (list (nshell.domain.parsing:make-command-arg "if" :double)
                        "false"
                        "extra")))
         (header-args (nshell.domain.parsing::%control-flow-header-args header))
         (condition (nshell.domain.parsing::%command-from-header-args header)))
    (is (nshell.domain.parsing::%control-flow-header-args-p header-args))
    (is (not (fboundp
              'nshell.domain.parsing::copy-%control-flow-header-args)))
    (is (string= "if"
                 (nshell.domain.parsing:arg-value
                  (nshell.domain.parsing::%control-flow-header-args-first
                   header-args))))
    (is (equal '("false" "extra")
               (mapcar #'nshell.domain.parsing:arg-value
                       (nshell.domain.parsing::%control-flow-header-args-rest
                        header-args))))
    (is (equal '("if" "false" "extra")
               (mapcar #'nshell.domain.parsing:arg-value
                       (nshell.domain.parsing::%control-flow-header-args-all
                        header-args))))
    (is (nshell.domain.parsing::%else-if-header-p header))
    (is (string= "if"
                 (nshell.domain.parsing:command-node-command condition)))
    (is (eq :double
            (nshell.domain.parsing:command-node-command-quote-style condition)))
    (is (equal '("false" "extra")
               (nshell.domain.parsing:command-node-arg-values condition)))
    (is (string= "*"
                 (nshell.domain.parsing::%command-first-arg-value
                  (nshell.domain.parsing:make-command-node "case" nil)
                  "*")))))

(test control-flow-for-header-binding-projects-loop-variable-and-values
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
    (is (nshell.domain.parsing::%control-flow-for-header-binding-p
         explicit-binding))
    (is (string= "item"
                 (nshell.domain.parsing::%control-flow-for-header-binding-var-name
                  explicit-binding)))
    (is (equal '("a" "b")
               (mapcar #'nshell.domain.parsing:arg-value
                       (nshell.domain.parsing::%control-flow-for-header-binding-in-values
                        explicit-binding))))
      (is (equal '("a" "b")
                 (mapcar #'nshell.domain.parsing:arg-value
                         (nshell.domain.parsing::%control-flow-for-header-binding-in-values
                          implicit-binding))))))

(test control-flow-body-scan-projects-body-rest-and-terminator
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
    (is (nshell.domain.parsing::%control-flow-body-scan-p scan))
    (is (equal (list body-command)
               (nshell.domain.parsing::%control-flow-body-scan-body scan)))
    (is (eq (rest nodes)
            (nshell.domain.parsing::%control-flow-body-scan-rest scan)))
    (is (string= "else"
                  (nshell.domain.parsing::%control-flow-body-scan-terminator
                   scan)))))

(test control-flow-node-grouping-projects-node-and-rest
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
    (is (nshell.domain.parsing::%control-flow-node-grouping-p
         plain-grouping))
    (is (eq command
            (nshell.domain.parsing::%control-flow-node-grouping-node
             plain-grouping)))
    (is (eq (rest commands)
            (nshell.domain.parsing::%control-flow-node-grouping-rest
             plain-grouping)))
    (is (nshell.domain.parsing::%control-flow-node-grouping-p
         block-grouping))
    (is (nshell.domain.parsing:begin-end-node-p
         (nshell.domain.parsing::%control-flow-node-grouping-node
          block-grouping)))
    (is (eq (nthcdr 3 block-commands)
            (nshell.domain.parsing::%control-flow-node-grouping-rest
             block-grouping)))))

(test control-flow-clause-scan-projects-clauses-and-rest
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
    (is (nshell.domain.parsing::%control-flow-clause-scan-p scan))
    (is (equal (list (cons "apple" (list body-command)))
               (nshell.domain.parsing::%control-flow-clause-scan-clauses scan)))
    (is (eq (nthcdr 4 nodes)
            (nshell.domain.parsing::%control-flow-clause-scan-rest scan)))))

(test control-flow-switch-case-patterns-project-default-and-explicit-patterns
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
    (is (nshell.domain.parsing::%control-flow-switch-case-patterns-p
         explicit-patterns))
    (is (equal '("vanilla" "chocolate")
               (nshell.domain.parsing::%control-flow-switch-case-patterns-values
                explicit-patterns)))
    (is (equal '("*")
               (nshell.domain.parsing::%control-flow-switch-case-patterns-values
                default-patterns)))))

(test parse-fish-switch-case-block
  (with-complete-command-line (result ast
                               "switch chocolate; case vanilla; echo plain; case chocolate strawberry; echo sweet; case '*'; echo default; end")
    (let ((clauses (and (nshell.domain.parsing:case-node-p ast)
                        (nshell.domain.parsing:case-node-clauses ast))))
      (is (nshell.domain.parsing:case-node-p ast))
      (is (string= "chocolate" (nshell.domain.parsing:case-node-value ast)))
      (is (every #'nshell.domain.parsing:case-clause-p clauses))
      (is (equal '("vanilla" "chocolate" "strawberry" "*")
                 (mapcar #'nshell.domain.parsing:case-clause-pattern
                         clauses)))
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command
                    (first (nshell.domain.parsing:case-clause-body
                            (second clauses)))))))))

(test parse-else-if-becomes-nested-if-branch
  (with-complete-ast (ast "if true; echo yes; else if false; echo no; end")
    (let ((else-branch (nshell.domain.parsing:if-node-else-branch ast)))
      (is (nshell.domain.parsing:if-node-p ast))
      (is (string= "true"
                   (nshell.domain.parsing:command-node-command
                    (nshell.domain.parsing:if-node-condition ast))))
      (is (= 1 (length else-branch)))
      (let ((nested-if (first else-branch)))
        (is (nshell.domain.parsing:if-node-p nested-if))
        (is (string= "false"
                     (nshell.domain.parsing:command-node-command
                      (nshell.domain.parsing:if-node-condition nested-if))))
        (is (string= "echo"
                     (nshell.domain.parsing:command-node-command
                      (first (nshell.domain.parsing:if-node-then-branch nested-if)))))
        (is (equal '("no")
                   (nshell.domain.parsing:command-node-arg-values
                    (first (nshell.domain.parsing:if-node-then-branch nested-if)))))))))

(test parse-else-if-preserves-nested-else-branch
  (with-complete-ast (ast "if false; echo no; else if false; echo maybe; else; echo yes; end")
    (let* ((else-branch (nshell.domain.parsing:if-node-else-branch ast))
           (nested-if (first else-branch))
           (nested-else (nshell.domain.parsing:if-node-else-branch nested-if)))
      (is (nshell.domain.parsing:if-node-p ast))
      (is (= 1 (length else-branch)))
      (is (nshell.domain.parsing:if-node-p nested-if))
      (is (string= "false"
                   (nshell.domain.parsing:command-node-command
                    (nshell.domain.parsing:if-node-condition nested-if))))
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command
                    (first nested-else))))
      (is (equal '("yes")
                 (nshell.domain.parsing:command-node-arg-values
                  (first nested-else)))))))
