(in-package #:nshell/test)

(describe "parser-tests"
  (it "control-flow-grouper-route-projects-spec-table"
    "Control-flow grouper routes should own raw spec table lookup."
    (let ((route (nshell.domain.parsing::%control-flow-grouper-route "if")))
      (expect (nshell.domain.parsing::%control-flow-grouper-route-p route) :to-be-truthy)
      (expect "if" :to-equal (nshell.domain.parsing::%control-flow-grouper-route-keyword
                    route))
      (expect 'nshell.domain.parsing::%group-control-flow-if :to-be (nshell.domain.parsing::%control-flow-grouper-route-grouper
               route))))

  (it "control-flow-grouping-route-projects-block-grouper-policy"
    "Control-flow grouping should classify block routes before invoking groupers."
    (flet ((route-grouper (keyword)
             (let ((route (nshell.domain.parsing::%control-flow-grouper-route keyword)))
               (and route
                    (nshell.domain.parsing::%control-flow-grouper-route-grouper route)))))
      (expect 'nshell.domain.parsing::%group-control-flow-if :to-be (route-grouper "if"))
      (expect 'nshell.domain.parsing::%group-control-flow-for :to-be (route-grouper "for"))
      (expect 'nshell.domain.parsing::%group-control-flow-switch :to-be (route-grouper "switch"))
      (expect (route-grouper "else") :to-be-null)
      (expect (route-grouper "end") :to-be-null)
      (expect (route-grouper "echo") :to-be-null)
      (expect (route-grouper nil) :to-be-null)))

  (it "control-flow-sequence-step-result-projects-consumed-block-boundary"
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
      (expect (nshell.domain.parsing::%control-flow-boundary-consumption-p
           consumption) :to-be-truthy)
      (expect :and :to-be (nshell.domain.parsing::%control-flow-boundary-consumption-separator
               consumption))
      (expect (nshell.domain.parsing::%control-flow-boundary-consumption-rest-separators
            consumption) :to-be-null)
      (expect (nshell.domain.parsing::%control-flow-sequence-step-p step) :to-be-truthy)
      (expect (nshell.domain.parsing:begin-end-node-p grouped) :to-be-truthy)
      (expect (list body-command) :to-equal (nshell.domain.parsing:begin-end-node-body grouped))
      (expect :and :to-be (nshell.domain.parsing::%control-flow-sequence-step-boundary-separator
               step))
      (expect (nthcdr 3 commands) :to-be (nshell.domain.parsing::%control-flow-sequence-step-rest-commands
               step))
      (expect (nshell.domain.parsing::%control-flow-sequence-step-rest-separators
                 step) :to-be-null)))

  (it "control-flow-sequence-grouping-projects-sequence-value"
    "Control-flow sequence grouping should return a typed sequence projection."
    (let* ((header (nshell.domain.parsing:make-command-node "begin" nil))
           (body-command (nshell.domain.parsing:make-command-node "echo" '("inside")))
           (end-command (nshell.domain.parsing:make-command-node "end" nil))
           (after-command (nshell.domain.parsing:make-command-node "echo" '("after")))
           (commands (list header body-command end-command after-command))
           (sequence (nshell.domain.parsing::%group-control-flow-sequence
                      commands
                      '(:semi :semi :and))))
      (expect (nshell.domain.parsing::%control-flow-sequence-p sequence) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing::%control-flow-sequence-commands
                      sequence)))
      (expect (nshell.domain.parsing:begin-end-node-p
           (first (nshell.domain.parsing::%control-flow-sequence-commands
                   sequence))) :to-be-truthy)
      (expect after-command :to-be (second (nshell.domain.parsing::%control-flow-sequence-commands
                       sequence)))
      (expect '(:and) :to-equal (nshell.domain.parsing::%control-flow-sequence-separators
                  sequence))))

  (it "control-flow-sequence-projects-collapse-boundary"
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
      (expect (nshell.domain.parsing::%control-flow-sequence-p foreground) :to-be-truthy)
      (expect command :to-be (first (nshell.domain.parsing::%control-flow-sequence-commands
                      foreground)))
      (expect (nshell.domain.parsing::%control-flow-sequence-single-command-p
           foreground) :to-be-truthy)
      (expect (nshell.domain.parsing::%control-flow-sequence-background-p
                foreground) :to-be-falsy)
      (expect command :to-be (nshell.domain.parsing::%collapse-control-flow-sequence
               foreground))
      (expect (nshell.domain.parsing::%control-flow-sequence-background-p
           background) :to-be-truthy)
      (let ((collapsed
              (nshell.domain.parsing::%collapse-control-flow-sequence
               background)))
        (expect (nshell.domain.parsing:sequence-node-p collapsed) :to-be-truthy)
        (expect '(:amp) :to-equal (nshell.domain.parsing:sequence-node-separators
                    collapsed)))))

  (it "parse-control-flow-sequence-remaps-and-separator-after-block"
    (with-complete-ast (ast "begin; false; end && echo no")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect '(:and) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-control-flow-sequence-remaps-or-separator-after-block"
    (with-complete-ast (ast "begin; true; end || echo no")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect '(:or) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-control-flow-sequence-preserves-surrounding-separators"
    (with-complete-ast (ast "echo before && begin; false; end || echo fallback")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 3 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect '(:and :or) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-control-flow-sequence-keeps-block-internal-separators-inside-block"
    (with-complete-ast (ast "echo before; begin; echo one; echo two; end; echo after")
      (let ((commands (nshell.domain.parsing:sequence-node-commands ast)))
        (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
        (expect 3 :to-equal (length commands))
        (expect (nshell.domain.parsing:begin-end-node-p (second commands)) :to-be-truthy)
        (expect 2 :to-equal (length (nshell.domain.parsing:begin-end-node-body
                          (second commands))))
        (expect '(:semi :semi) :to-equal (nshell.domain.parsing:sequence-node-separators ast)))))

  (it "parse-single-command-background-preserves-sequence-node"
    "A trailing & on a single command should stay as a sequence node."
    (with-complete-ast (ast "echo hello &")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 1 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect '(:amp) :to-equal (nshell.domain.parsing:sequence-node-separators ast)))))
