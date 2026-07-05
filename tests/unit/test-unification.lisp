(in-package #:nshell/test)


(def-suite unification-tests
  :description "Unification engine tests"
  :in nshell-tests)

(in-suite unification-tests)

(test unify-atoms
  (is (nshell.domain.parsing:unify-p
       (nshell.domain.parsing:unify 'foo 'foo))))

(test unify-different-atoms
  (is (not (nshell.domain.parsing:unify-p
            (nshell.domain.parsing:unify 'foo 'bar)))))

(test unify-variable-with-value
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (b (nshell.domain.parsing:unify x 'hello)))
    (is (nshell.domain.parsing:unify-p b))
    (is (eq 'hello (nshell.domain.parsing:walk x b)))))

(test logic-variable-raw-constructor-is-internal-boundary
  (let ((x (nshell.domain.parsing:make-var "X")))
    (is (nshell.domain.parsing:var-p x))
    (is (fboundp 'nshell.domain.parsing::%make-var))
    (is (not (fboundp 'nshell.domain.parsing::copy-logic-var)))))

(test binding-entry-projects-association-shape
  "Binding lookup should project alist storage before resolving variables."
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (y (nshell.domain.parsing:make-var "Y"))
         (bindings (nshell.domain.parsing:extend-bindings x y nil))
         (entry (nshell.domain.parsing::%binding-entry-for-var x bindings)))
    (is (nshell.domain.parsing::%binding-entry-p entry))
    (is (eq x (nshell.domain.parsing::%binding-entry-variable entry)))
    (is (eq y (nshell.domain.parsing::%binding-entry-value entry)))
    (is (null (nshell.domain.parsing::%binding-entry-for-var y bindings)))
    (is (not (fboundp 'nshell.domain.parsing::copy-%binding-entry)))))

(test cons-term-projects-recursive-term-shape
  "Recursive unification paths should project raw cons terms once."
  (let ((term (nshell.domain.parsing::%cons-term-from-raw '(head . tail))))
    (is (nshell.domain.parsing::%cons-term-p term))
    (is (eq 'head (nshell.domain.parsing::%cons-term-head term)))
    (is (eq 'tail (nshell.domain.parsing::%cons-term-tail term)))
    (is (null (nshell.domain.parsing::%cons-term-from-raw 'atom)))
    (is (not (fboundp 'nshell.domain.parsing::copy-%cons-term)))))

(test unify-lists
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (b (nshell.domain.parsing:unify (list x 'b) '(a b))))
    (is (nshell.domain.parsing:unify-p b))
    (is (eq 'a (nshell.domain.parsing:walk x b)))))

(test unify-reuses-list-head-bindings-in-tail
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (success (nshell.domain.parsing:unify (list x x) '(same same)))
         (failure (nshell.domain.parsing:unify (list x x) '(left right))))
    (is (nshell.domain.parsing:unify-p success))
    (is (eq 'same (nshell.domain.parsing:walk x success)))
    (is (not (nshell.domain.parsing:unify-p failure)))))

(test occurs-check
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (b (nshell.domain.parsing:unify x (list x))))
    (is (not (nshell.domain.parsing:unify-p b)))))

(test backtrack-simple
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (goal (lambda (b) (nshell.domain.parsing:unify x 42 b)))
         (result (nshell.domain.parsing:backtrack (list goal))))
    (is (not (null result)))
    (is (= 42 (nshell.domain.parsing:walk x result)))))

(test backtrack-continues-after-empty-binding-success
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (noop-goal (lambda (b) (nshell.domain.parsing:unify 'same 'same b)))
         (bind-goal (lambda (b) (nshell.domain.parsing:unify x 42 b)))
         (result (nshell.domain.parsing:backtrack (list noop-goal bind-goal))))
    (is (nshell.domain.parsing:unify-p result))
    (is (= 42 (nshell.domain.parsing:walk x result)))))

(test goal-cursor-projects-backtracking-goal-list
  "Backtracking should project the current goal and remaining goals through a cursor."
  (let* ((first-goal (lambda (bindings) bindings))
         (second-goal (lambda (bindings) bindings))
         (cursor (nshell.domain.parsing::%goal-cursor-from-goals
                  (list first-goal second-goal))))
    (is (nshell.domain.parsing::%goal-cursor-p cursor))
    (is (eq first-goal (nshell.domain.parsing::%goal-cursor-goal cursor)))
    (is (eq second-goal
            (first (nshell.domain.parsing::%goal-cursor-rest cursor))))
    (is (null (nshell.domain.parsing::%goal-cursor-from-goals nil)))
    (is (not (fboundp 'nshell.domain.parsing::copy-%goal-cursor)))))

(test walk-resolves-chain
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (y (nshell.domain.parsing:make-var "Y"))
         (b1 (nshell.domain.parsing:unify x y))
         (b2 (nshell.domain.parsing:unify y 10 b1)))
    (is (= 10 (nshell.domain.parsing:walk x b2)))))

(test walk-resolves-nested-bound-terms
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (y (nshell.domain.parsing:make-var "Y"))
         (b1 (nshell.domain.parsing:unify x (list y 'tail)))
         (b2 (nshell.domain.parsing:unify y 'head b1)))
    (is (equal '(head tail) (nshell.domain.parsing:walk x b2)))))

(test pbt-unify-variable-walks-to-term
  "Unifying a fresh variable with a generated term makes WALK resolve to that term."
  (for-all-property (:trials 50) ((term (gen-string)))
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (bindings (nshell.domain.parsing:unify x term)))
      (is (nshell.domain.parsing:unify-p bindings)
          "Generated term ~s should unify with a fresh variable" term)
      (is (equal term (nshell.domain.parsing:walk x bindings))
          "Walking the variable should recover generated term ~s" term))))

(test pbt-occurs-check-rejects-cyclic-bindings
  "Occurs-check rejects generated cyclic bindings."
  (for-all-property (:trials 50) ((term (gen-string)))
    (let* ((x (nshell.domain.parsing:make-var "X"))
           (bindings (nshell.domain.parsing:unify x (list x term))))
      (is (not (nshell.domain.parsing:unify-p bindings))
          "Occurs-check should reject cyclic binding containing ~s" term))))
