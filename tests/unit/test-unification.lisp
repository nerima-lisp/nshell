(in-package #:nshell/test)

(describe "unification-tests"
  (it "unify-atoms"
    (expect (nshell.domain.parsing:unify-p
         (nshell.domain.parsing:unify 'foo 'foo)) :to-be-truthy))

  (it "unify-different-atoms"
    (expect (nshell.domain.parsing:unify-p
              (nshell.domain.parsing:unify 'foo 'bar)) :to-be-falsy))

  (it "unify-variable-with-value"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (b (nshell.domain.parsing:unify x 'hello)))
      (expect (nshell.domain.parsing:unify-p b) :to-be-truthy)
      (expect 'hello :to-be (nshell.domain.parsing:walk x b))))

  (it "logic-variable-raw-constructor-is-internal-boundary"
    (let ((x (nshell.domain.parsing:make-var "X")))
      (expect (nshell.domain.parsing:var-p x) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::%make-var) :to-be-truthy)
      (expect (fboundp 'nshell.domain.parsing::copy-logic-var) :to-be-falsy)))

  (it "binding-entry-projects-association-shape"
    "Binding lookup should project alist storage before resolving variables."
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (y (nshell.domain.parsing:make-var "Y"))
           (bindings (nshell.domain.parsing:extend-bindings x y nil))
           (entry (nshell.domain.parsing::%binding-entry-for-var x bindings)))
      (expect (nshell.domain.parsing::%binding-entry-p entry) :to-be-truthy)
      (expect x :to-be (nshell.domain.parsing::%binding-entry-variable entry))
      (expect y :to-be (nshell.domain.parsing::%binding-entry-value entry))
      (expect (nshell.domain.parsing::%binding-entry-for-var y bindings) :to-be-null)
      (expect (fboundp 'nshell.domain.parsing::copy-%binding-entry) :to-be-falsy)))

  (it "cons-term-projects-recursive-term-shape"
    "Recursive unification paths should project raw cons terms once."
    (let ((term (nshell.domain.parsing::%cons-term-from-raw '(head . tail))))
      (expect (nshell.domain.parsing::%cons-term-p term) :to-be-truthy)
      (expect 'head :to-be (nshell.domain.parsing::%cons-term-head term))
      (expect 'tail :to-be (nshell.domain.parsing::%cons-term-tail term))
      (expect (nshell.domain.parsing::%cons-term-from-raw 'atom) :to-be-null)
      (expect (fboundp 'nshell.domain.parsing::copy-%cons-term) :to-be-falsy)))

  (it "unify-lists"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (b (nshell.domain.parsing:unify (list x 'b) '(a b))))
      (expect (nshell.domain.parsing:unify-p b) :to-be-truthy)
      (expect 'a :to-be (nshell.domain.parsing:walk x b))))

  (it "unify-reuses-list-head-bindings-in-tail"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (success (nshell.domain.parsing:unify (list x x) '(same same)))
           (failure (nshell.domain.parsing:unify (list x x) '(left right))))
      (expect (nshell.domain.parsing:unify-p success) :to-be-truthy)
      (expect 'same :to-be (nshell.domain.parsing:walk x success))
      (expect (nshell.domain.parsing:unify-p failure) :to-be-falsy)))

  (it "occurs-check"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (b (nshell.domain.parsing:unify x (list x))))
      (expect (nshell.domain.parsing:unify-p b) :to-be-falsy)))

  (it "backtrack-simple"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (goal (lambda (b) (nshell.domain.parsing:unify x 42 b)))
           (result (nshell.domain.parsing:backtrack (list goal))))
      (expect (null result) :to-be-falsy)
      (expect 42 :to-equal (nshell.domain.parsing:walk x result))))

  (it "backtrack-continues-after-empty-binding-success"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (noop-goal (lambda (b) (nshell.domain.parsing:unify 'same 'same b)))
           (bind-goal (lambda (b) (nshell.domain.parsing:unify x 42 b)))
           (result (nshell.domain.parsing:backtrack (list noop-goal bind-goal))))
      (expect (nshell.domain.parsing:unify-p result) :to-be-truthy)
      (expect 42 :to-equal (nshell.domain.parsing:walk x result))))

  (it "goal-cursor-projects-backtracking-goal-list"
    "Backtracking should project the current goal and remaining goals through a cursor."
    (let* ((first-goal (lambda (bindings) bindings))
           (second-goal (lambda (bindings) bindings))
           (cursor (nshell.domain.parsing::%goal-cursor-from-goals
                    (list first-goal second-goal))))
      (expect (nshell.domain.parsing::%goal-cursor-p cursor) :to-be-truthy)
      (expect first-goal :to-be (nshell.domain.parsing::%goal-cursor-goal cursor))
      (expect second-goal :to-be (first (nshell.domain.parsing::%goal-cursor-rest cursor)))
      (expect (nshell.domain.parsing::%goal-cursor-from-goals nil) :to-be-null)
      (expect (fboundp 'nshell.domain.parsing::copy-%goal-cursor) :to-be-falsy)))

  (it "walk-resolves-chain"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (y (nshell.domain.parsing:make-var "Y"))
           (b1 (nshell.domain.parsing:unify x y))
           (b2 (nshell.domain.parsing:unify y 10 b1)))
      (expect 10 :to-equal (nshell.domain.parsing:walk x b2))))

  (it "walk-resolves-nested-bound-terms"
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (y (nshell.domain.parsing:make-var "Y"))
           (b1 (nshell.domain.parsing:unify x (list y 'tail)))
           (b2 (nshell.domain.parsing:unify y 'head b1)))
      (expect '(head tail) :to-equal (nshell.domain.parsing:walk x b2)))))
