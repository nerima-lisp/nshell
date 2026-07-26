; Prolog-style logic engine: facts, rules, unification, and proof search.
(in-package #:nshell.domain.completion)

(define-value-struct fact
    ((predicate nil :type symbol)
     (args '() :type list))
  :constructor %allocate-fact)

(define-value-struct rule
    ((head '() :type list)
     (body '() :type list))
  :constructor %allocate-rule)

(defstruct (rule-knowledge-base
            (:constructor %make-rule-knowledge-base
                (&key (facts nil) (rules nil))))
  (facts nil :type list)
  (rules nil :type list))

(defparameter *max-proof-depth* 32
  "Maximum rule-expansion depth for completion proof search.")

(defun make-fact (&key predicate (args '()))
  (check-type predicate symbol)
  (check-type args list)
  (%allocate-fact predicate (copy-list args)))

(defun make-rule (&key (head '()) (body '()))
  (check-type head list)
  (check-type body list)
  (%allocate-rule (copy-list head) (copy-list body)))

(defun %make-fact-from-spec (spec)
  (make-fact :predicate (first spec)
             :args (rest spec)))

(defun %make-rule-from-spec (spec)
  (make-rule :head (first spec)
             :body (rest spec)))

(defgeneric predicate-true-p (predicate args bindings)
  (:documentation
   "Return true when PREDICATE with walked ARGS is true in the current environment."))

(defmethod predicate-true-p ((predicate symbol) args bindings)
  (declare (ignore predicate args bindings))
  nil)

(defun make-empty-rule-knowledge-base ()
  (%make-rule-knowledge-base))

(defun assert-fact! (kb fact)
  (push fact (rule-knowledge-base-facts kb))
  kb)

(defun assert-rule! (kb rule)
  (push rule (rule-knowledge-base-rules kb))
  kb)

(defun %make-prolog-fact (fact)
  (cl-prolog:make-clause (list* (fact-predicate fact) (fact-args fact))))

(defun %make-prolog-rule (rule)
  (cl-prolog:make-clause (copy-tree (rule-head rule)) (copy-tree (rule-body rule))))

(defun completion-rulebase (kb)
  "Compile the completion KB into a first-class CL-PROLOG:RULEBASE.

Every completion fact and rule becomes a Prolog clause, so the resulting
rulebase answers the full cl-prolog query API (QUERY-PROLOG, FINDALL,
negation-as-failure, ...) over nshell's completion knowledge, not just the
depth-bounded PROVE search used on the interactive path.  Facts and rules are
inserted in definition order (the KB accumulates them reversed via PUSH) so
solution order stays stable for callers that depend on it."
  (let ((rulebase (cl-prolog:make-rulebase)))
    (dolist (fact (reverse (rule-knowledge-base-facts kb)) rulebase)
      (cl-prolog:rulebase-insert-clause! rulebase (%make-prolog-fact fact)))
    (dolist (rule (reverse (rule-knowledge-base-rules kb)) rulebase)
      (cl-prolog:rulebase-insert-clause! rulebase (%make-prolog-rule rule)))))

(defun %ground-term-p (term)
  "True when TERM contains no unbound logic (?-prefixed) variables."
  (cond
    ((cl-prolog:logic-var-p term) nil)
    ((consp term) (and (%ground-term-p (car term)) (%ground-term-p (cdr term))))
    (t t)))

(defun %built-in-solution (goal)
  "Return a list containing one empty solution when GOAL is a ground term
satisfied directly by a PREDICATE-TRUE-P extension, else NIL.

This only covers a fully-instantiated top-level goal: PREDICATE-TRUE-P is a
boolean check over concrete arguments, not a generator of bindings, so it
cannot itself resolve a goal containing unbound query variables. A goal
appearing as a sub-goal inside a rule body is walked through the partial
bindings accumulated by clause resolution before reaching here, so this
still applies once earlier body goals have grounded it."
  (when (and (consp goal)
             (%ground-term-p goal)
             (predicate-true-p (first goal) (rest goal) '()))
    (list '())))

(defun prove (kb goal &optional (bindings '()) (max-depth *max-proof-depth*))
  (declare (ignore bindings))
  ;; cl-prolog signals an ISO PROLOG-RUNTIME-ERROR (existence_error for a
  ;; goal naming an undefined predicate, resource_error/PROLOG-DEPTH-LIMIT-
  ;; EXCEEDED past MAX-DEPTH, and so on) and unwinds QUERY-PROLOG's whole
  ;; search, discarding solutions already found on other branches. Standard
  ;; ISO behavior for a real Prolog program, but the completion engine's
  ;; rule bodies routinely reference predicates that only PREDICATE-TRUE-P
  ;; resolves (never a cl-prolog clause or foreign predicate), and searches
  ;; are deliberately depth-bounded for an interactive tool — both are
  ;; "this path found nothing," not a program error. Collect via MAP-
  ;; PROLOG-SOLUTIONS and treat any such runtime error as exactly that,
  ;; keeping whatever solutions were already found on other branches.
  (let ((rulebase (completion-rulebase kb))
        (solutions '()))
    (handler-case
        (cl-prolog:map-prolog-solutions
         (lambda (solution) (push solution solutions))
         rulebase (copy-tree goal) :max-depth max-depth)
      (cl-prolog:prolog-runtime-error () nil))
    (append (nreverse solutions) (%built-in-solution goal))))

(defun prove-all (kb goal &key (max-depth *max-proof-depth*))
  (prove kb goal '() max-depth))

(defparameter *built-in-rule-knowledge-base*
  (%make-rule-knowledge-base
   :facts (mapcar #'%make-fact-from-spec
                  (builtin-rule-facts))
   :rules (mapcar #'%make-rule-from-spec
                  (builtin-rule-rules))))
