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
      (is (nshell.domain.parsing::%control-flow-stack-transition-p
           if-transition))
      (is (not (fboundp
                'nshell.domain.parsing::copy-control-flow-frame)))
      (is (not (fboundp
                'nshell.domain.parsing::copy-%control-flow-stack-transition)))
      (is (null
           (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
            if-transition)))
      (is (string= "if"
                   (nshell.domain.parsing::control-flow-frame-keyword
                    (first if-stack))))
      (is (null
           (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
            else-transition)))
      (is (not (eq (first if-stack)
                   (first else-stack))))
      (is (not (nshell.domain.parsing::control-flow-frame-else-seen
                (first if-stack))))
      (is (nshell.domain.parsing::control-flow-frame-else-seen
           (first else-stack)))
      (is (eq else-stack same-stack))
      (is (string= "else"
                   (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
                    second-else-transition)))
      (is (null
           (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
            end-transition)))
      (is (null
           (nshell.domain.parsing::%control-flow-stack-transition-stack
            end-transition))))
    (let* ((switch-transition
             (nshell.domain.parsing::%control-flow-stack-transition
              nil switch-command))
           (switch-stack
             (nshell.domain.parsing::%control-flow-stack-transition-stack
              switch-transition))
           (case-transition
             (nshell.domain.parsing::%control-flow-stack-transition
              switch-stack case-command)))
      (is (null
           (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
            switch-transition)))
      (is (eq switch-stack
              (nshell.domain.parsing::%control-flow-stack-transition-stack
               case-transition)))
      (is (null
           (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
            case-transition))))
    (let ((case-transition
            (nshell.domain.parsing::%control-flow-stack-transition
             nil case-command)))
      (is (null
           (nshell.domain.parsing::%control-flow-stack-transition-stack
            case-transition)))
      (is (string= "case"
                   (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
                     case-transition))))))

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

(test control-flow-grouper-entry-projects-spec-table
  "Control-flow grouper entries should own raw spec table lookup."
  (let ((entry (nshell.domain.parsing::%control-flow-grouper-entry "if")))
    (is (nshell.domain.parsing::%control-flow-grouper-entry-p entry))
    (is (string= "if"
                 (nshell.domain.parsing::%control-flow-grouper-entry-keyword
                  entry)))
    (is (eq 'nshell.domain.parsing::%group-control-flow-if
            (nshell.domain.parsing::%control-flow-grouper-entry-grouper
             entry)))))

(test control-flow-grouping-route-projects-block-grouper-policy
  "Control-flow grouping should classify block routes before invoking groupers."
  (flet ((route-grouper (keyword)
           (let ((route (nshell.domain.parsing::%control-flow-grouping-route keyword)))
             (and route
                  (nshell.domain.parsing::%control-flow-grouping-route-grouper route)))))
    (is (eq 'nshell.domain.parsing::%group-control-flow-if
            (route-grouper "if")))
    (is (eq 'nshell.domain.parsing::%group-control-flow-for
            (route-grouper "for")))
    (is (eq 'nshell.domain.parsing::%group-control-flow-switch
            (route-grouper "switch")))
    (is (null (route-grouper "else")))
    (is (null (route-grouper "end")))
    (is (null (route-grouper "echo")))
    (is (null (route-grouper nil)))))

(test control-flow-sequence-step-result-projects-consumed-block-boundary
  "Control-flow sequence grouping should project one typed result for a consumed block."
  (let* ((header (nshell.domain.parsing:make-command-node "begin" nil))
         (body-command (nshell.domain.parsing:make-command-node "echo" '("inside")))
         (end-command (nshell.domain.parsing:make-command-node "end" nil))
         (after-command (nshell.domain.parsing:make-command-node "echo" '("after")))
         (commands (list header body-command end-command after-command))
         (separators '(:semi :semi :and))
         (consumption
           (nshell.domain.parsing::%control-flow-boundary-consumption-from-consumed-commands
            commands (nthcdr 3 commands) separators))
         (step (nshell.domain.parsing::%control-flow-sequence-step-result
                commands separators))
         (grouped (nshell.domain.parsing::%control-flow-sequence-step-grouped-command
                   step)))
    (is (nshell.domain.parsing::%control-flow-boundary-consumption-p
         consumption))
    (is (eq :and
            (nshell.domain.parsing::%control-flow-boundary-consumption-separator
             consumption)))
    (is (null
         (nshell.domain.parsing::%control-flow-boundary-consumption-rest-separators
          consumption)))
    (is (nshell.domain.parsing::%control-flow-sequence-step-p step))
    (is (nshell.domain.parsing:begin-end-node-p grouped))
    (is (equal (list body-command)
               (nshell.domain.parsing:begin-end-node-body grouped)))
    (is (eq :and
            (nshell.domain.parsing::%control-flow-sequence-step-boundary-separator
             step)))
    (is (eq (nthcdr 3 commands)
            (nshell.domain.parsing::%control-flow-sequence-step-rest-commands
             step)))
  (is (null (nshell.domain.parsing::%control-flow-sequence-step-rest-separators
               step)))))

(test control-flow-sequence-grouping-projects-sequence-value
  "Control-flow sequence grouping should return a typed sequence projection."
  (let* ((header (nshell.domain.parsing:make-command-node "begin" nil))
         (body-command (nshell.domain.parsing:make-command-node "echo" '("inside")))
         (end-command (nshell.domain.parsing:make-command-node "end" nil))
         (after-command (nshell.domain.parsing:make-command-node "echo" '("after")))
         (commands (list header body-command end-command after-command))
         (sequence (nshell.domain.parsing::%group-control-flow-sequence
                    commands
                    '(:semi :semi :and))))
    (is (nshell.domain.parsing::%control-flow-sequence-p sequence))
    (is (= 2
           (length (nshell.domain.parsing::%control-flow-sequence-commands
                    sequence))))
    (is (nshell.domain.parsing:begin-end-node-p
         (first (nshell.domain.parsing::%control-flow-sequence-commands
                 sequence))))
    (is (eq after-command
            (second (nshell.domain.parsing::%control-flow-sequence-commands
                     sequence))))
    (is (equal '(:and)
               (nshell.domain.parsing::%control-flow-sequence-separators
                sequence)))))

(test control-flow-sequence-projects-collapse-boundary
  "Control-flow sequence collapse should consume a projected sequence value."
  (let* ((command (nshell.domain.parsing:make-command-node "echo" '("hello")))
         (foreground-node
           (nshell.domain.parsing::make-sequence-node (list command) nil))
         (background-node
           (nshell.domain.parsing::make-sequence-node (list command) '(:amp)))
         (foreground
           (nshell.domain.parsing::%control-flow-sequence-from-node
            foreground-node))
         (background
           (nshell.domain.parsing::%control-flow-sequence-from-node
            background-node)))
    (is (nshell.domain.parsing::%control-flow-sequence-p foreground))
    (is (eq command
            (first (nshell.domain.parsing::%control-flow-sequence-commands
                    foreground))))
    (is (nshell.domain.parsing::%control-flow-sequence-single-command-p
         foreground))
    (is (not (nshell.domain.parsing::%control-flow-sequence-background-p
              foreground)))
    (is (eq command
            (nshell.domain.parsing::%collapse-control-flow-sequence
             foreground)))
    (is (nshell.domain.parsing::%control-flow-sequence-background-p
         background))
    (let ((collapsed
            (nshell.domain.parsing::%collapse-control-flow-sequence
             background)))
      (is (nshell.domain.parsing:sequence-node-p collapsed))
      (is (equal '(:amp)
                 (nshell.domain.parsing:sequence-node-separators
                  collapsed))))))

(test parse-control-flow-sequence-remaps-and-separator-after-block
  (with-complete-ast (ast "begin; false; end && echo no")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:and)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-control-flow-sequence-remaps-or-separator-after-block
  (with-complete-ast (ast "begin; true; end || echo no")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:or)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-control-flow-sequence-preserves-surrounding-separators
  (with-complete-ast (ast "echo before && begin; false; end || echo fallback")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 3 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:and :or)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-control-flow-sequence-keeps-block-internal-separators-inside-block
  (with-complete-ast (ast "echo before; begin; echo one; echo two; end; echo after")
    (let ((commands (nshell.domain.parsing:sequence-node-commands ast)))
      (is (nshell.domain.parsing:sequence-node-p ast))
      (is (= 3 (length commands)))
      (is (nshell.domain.parsing:begin-end-node-p (second commands)))
      (is (= 2 (length (nshell.domain.parsing:begin-end-node-body
                        (second commands)))))
      (is (equal '(:semi :semi)
                 (nshell.domain.parsing:sequence-node-separators ast))))))

(test parse-single-command-background-preserves-sequence-node
  "A trailing & on a single command should stay as a sequence node."
  (with-complete-ast (ast "echo hello &")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 1 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:amp) (nshell.domain.parsing:sequence-node-separators ast)))))
