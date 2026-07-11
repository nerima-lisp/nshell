; Prolog-style logic engine: facts, rules, unification, and proof search.
(in-package #:nshell.domain.completion)

(defstruct (fact (:constructor %allocate-fact (predicate args))
                 (:copier nil))
  (predicate nil :type symbol :read-only t)
  (args '() :type list :read-only t))

(defstruct (rule (:constructor %allocate-rule (head body))
                 (:copier nil))
  (head '() :type list :read-only t)
  (body '() :type list :read-only t))

(defstruct (rule-knowledge-base (:constructor %make-rule-knowledge-base (&key (facts nil) (rules nil))))
  (facts nil :type list)
  (rules nil :type list))

(defstruct (proof-search (:constructor %make-proof-search (kb goal bindings depth)))
  (kb nil :read-only t)
  (goal '() :type list :read-only t)
  (bindings '() :type list :read-only t)
  (depth 0 :type integer :read-only t))

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
  (:documentation "Return true when PREDICATE with walked ARGS is true in the current environment."))

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

(defun %logic-variable-symbol-p (x)
  (and (symbolp x)
       (< 0 (length (symbol-name x)))
       (char= #\? (char (symbol-name x) 0))))

(defun %logic-variable-name (symbol)
  (subseq (symbol-name symbol) 1))

(declaim (ftype (function (t hash-table) t) %convert-logic-variables))

(defun %logic-form-pair-head (form)
  (car form))

(defun %logic-form-pair-tail (form)
  (cdr form))

(defun %make-logic-form-pair (head tail)
  (cons head tail))

(defun %convert-logic-form-pair (form env)
  (%make-logic-form-pair
   (%convert-logic-variables (%logic-form-pair-head form) env)
   (%convert-logic-variables (%logic-form-pair-tail form) env)))

(defun %convert-logic-variables (form env)
  (cond
    ((%logic-variable-symbol-p form)
     (or (gethash form env)
         (setf (gethash form env)
               (make-symbol (symbol-name form)))))
    ((consp form)
     (%convert-logic-form-pair form env))
    (t form)))

(defun %fact-head (fact env)
  (%convert-logic-variables (cons (fact-predicate fact) (fact-args fact)) env))

(defun %rule-head-term (rule env)
  (%convert-logic-variables (rule-head rule) env))

(defun %rule-body-terms (rule env)
  (mapcar (lambda (goal) (%convert-logic-variables goal env))
          (rule-body rule)))

(defun %walk-built-in-args (args bindings)
  (mapcar (lambda (arg)
            (fx.prolog:substitute-term arg bindings))
          args))

(defmethod fx.prolog:predicate-true-p :around ((predicate symbol) args bindings)
  (or (predicate-true-p predicate
                        (%walk-built-in-args args bindings)
                        bindings)
      (call-next-method)))

(defun %binding-variable-symbol-p (binding)
  (and (consp binding)
       (%logic-variable-symbol-p (car binding))))

(defun %normalize-bindings (bindings)
  (remove-if-not #'%binding-variable-symbol-p bindings))

(defun %make-prolog-fact (fact)
  (fx.prolog:make-fact :predicate (fact-predicate fact)
                       :args (copy-list (fact-args fact))))

(defun %make-prolog-rule (rule)
  (fx.prolog:make-rule :head (copy-tree (rule-head rule))
                       :body (copy-tree (rule-body rule))))

(defun %make-prolog-rulebase (kb)
  (let ((rulebase (fx.prolog:make-empty-rule-knowledge-base)))
    (dolist (fact (reverse (rule-knowledge-base-facts kb)) rulebase)
      (fx.prolog:assert-fact! rulebase (%make-prolog-fact fact)))
    (dolist (rule (reverse (rule-knowledge-base-rules kb)) rulebase)
      (fx.prolog:assert-rule! rulebase (%make-prolog-rule rule)))))

(defun prove (kb goal &optional (bindings '()) (max-depth *max-proof-depth*))
  (declare (ignore bindings))
  (let ((rulebase (%make-prolog-rulebase kb)))
    (fx.prolog:query-prolog rulebase
                            (copy-tree goal)
                            :max-depth max-depth)))

(defun prove-all (kb goal &key (max-depth *max-proof-depth*))
  (prove kb goal '() max-depth))

(defparameter *built-in-rule-knowledge-base*
  (%make-rule-knowledge-base
   :facts (mapcar #'%make-fact-from-spec
                  (builtin-rule-facts))
   :rules (mapcar #'%make-rule-from-spec
                  (builtin-rule-rules))))
