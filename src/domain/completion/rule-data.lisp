; Prolog-style logic engine: facts, rules, unification, and proof search.
(in-package #:nshell.domain.completion)

(define-value-struct
  fact
  ((predicate nil :type symbol) (args '() :type list))
  :constructor
  %allocate-fact)

(define-value-struct
  rule
  ((head '() :type list) (body '() :type list))
  :constructor
  %allocate-rule)

(defstruct (rule-knowledge-base
    (:constructor %make-rule-knowledge-base (&key (facts nil) (rules nil)))) (facts nil :type list)
  (rules nil :type list)
  (revision 0 :type fixnum)
  (compiled-revision -1 :type fixnum)
  (compiled-rulebase nil)
  (lock
    (sb-thread:make-mutex :name "completion rule knowledge base")
    :read-only
    t))

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
  (make-fact :predicate (first spec) :args (rest spec)))

(defun %make-rule-from-spec (spec)
  (make-rule :head (first spec) :body (rest spec)))

(defgeneric predicate-true-p (predicate args bindings)
  (:documentation
    "Return true when PREDICATE with walked ARGS is true in the current environment."))

(defmethod predicate-true-p ((predicate symbol) args bindings)
  (declare (ignore predicate args bindings))
  nil)

(defun make-empty-rule-knowledge-base ()
  (%make-rule-knowledge-base))

(defun assert-fact! (kb fact)
  (sb-thread:with-mutex
    ((rule-knowledge-base-lock kb))
    (push fact (rule-knowledge-base-facts kb))
    (incf (rule-knowledge-base-revision kb))
    (setf (rule-knowledge-base-compiled-rulebase kb) nil
          (rule-knowledge-base-compiled-revision kb) -1))
  kb)

(defun assert-rule! (kb rule)
  (sb-thread:with-mutex
    ((rule-knowledge-base-lock kb))
    (push rule (rule-knowledge-base-rules kb))
    (incf (rule-knowledge-base-revision kb))
    (setf (rule-knowledge-base-compiled-rulebase kb) nil
          (rule-knowledge-base-compiled-revision kb) -1))
  kb)

(defun %make-prolog-fact (fact)
  (cl-prolog:make-clause (list* (fact-predicate fact) (fact-args fact))))

(defun %make-prolog-rule (rule)
  (cl-prolog:make-clause
    (copy-tree (rule-head rule))
    (copy-tree (rule-body rule))))

(defun completion-rulebase (kb)
  "Compile and cache the completion KB as a first-class CL-PROLOG:RULEBASE. Compilation and mutation share the KB lock, so readers never observe a partially constructed rulebase. Facts and rules are inserted in definition order to preserve stable solution order."
  (sb-thread:with-mutex
    ((rule-knowledge-base-lock kb))
    (let ((revision (rule-knowledge-base-revision kb)))
      (if (and
          (rule-knowledge-base-compiled-rulebase kb)
          (= revision (rule-knowledge-base-compiled-revision kb))) (rule-knowledge-base-compiled-rulebase kb)
        (let ((rulebase (cl-prolog:make-rulebase)))
          (dolist (fact (reverse (rule-knowledge-base-facts kb)))
            (cl-prolog:rulebase-insert-clause! rulebase (%make-prolog-fact fact)))
          (dolist (rule (reverse (rule-knowledge-base-rules kb)))
            (cl-prolog:rulebase-insert-clause! rulebase (%make-prolog-rule rule)))
          (setf (rule-knowledge-base-compiled-rulebase kb) rulebase
                (rule-knowledge-base-compiled-revision kb) revision)
          rulebase)))))

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
  (when (and
      (consp goal)
      (%ground-term-p goal)
      (predicate-true-p (first goal) (rest goal) '()))
    (list '())))

(defun %prove-rulebase (rulebase goal &optional (bindings '()) (max-depth *max-proof-depth*))
    (declare (ignore bindings))
    ;; Completion treats undefined predicates and depth limits as an empty path.
    (let ((solutions '()))
      (handler-case
          (cl-prolog:map-prolog-solutions
           (lambda (solution) (push solution solutions))
           rulebase (copy-tree goal) :max-depth max-depth)
        (cl-prolog:prolog-runtime-error () nil))
      (append (nreverse solutions) (%built-in-solution goal))))

(defun prove (kb goal &optional (bindings '()) (max-depth *max-proof-depth*))
  (%prove-rulebase (completion-rulebase kb) goal bindings max-depth))

(defun prove-all (kb goal &key (max-depth *max-proof-depth*))
  (prove kb goal '() max-depth))

(defparameter *built-in-rule-knowledge-base* (%make-rule-knowledge-base
    :facts
    (mapcar #'%make-fact-from-spec (builtin-rule-facts))
    :rules
    (mapcar #'%make-rule-from-spec (builtin-rule-rules))))
