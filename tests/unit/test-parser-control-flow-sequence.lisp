(in-package #:nshell/test)

(in-suite parser-tests)

(test control-flow-grouper-route-projects-spec-table
  "Control-flow grouper routes should own raw spec table lookup."
  (let ((route (nshell.domain.parsing::%control-flow-grouper-route "if")))
    (is (nshell.domain.parsing::%control-flow-grouper-route-p route))
    (is (string= "if"
                 (nshell.domain.parsing::%control-flow-grouper-route-keyword
                  route)))
    (is (eq 'nshell.domain.parsing::%group-control-flow-if
            (nshell.domain.parsing::%control-flow-grouper-route-grouper
             route)))))

(test control-flow-grouping-route-projects-block-grouper-policy
  "Control-flow grouping should classify block routes before invoking groupers."
  (flet ((route-grouper (keyword)
           (let ((route (nshell.domain.parsing::%control-flow-grouper-route keyword)))
             (and route
                  (nshell.domain.parsing::%control-flow-grouper-route-grouper route)))))
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
