; Prolog-style logic engine: facts, rules, unification, and proof search.
(in-package #:nshell.domain.completion)

(defstruct fact
  (predicate nil :type symbol :read-only t)
  (args '() :type list :read-only t))

(defstruct rule
  (head '() :type list :read-only t)
  (body '() :type list :read-only t))

(defstruct (rule-knowledge-base (:constructor make-rule-knowledge-base (&key (facts nil) (rules nil))))
  (facts nil :type list)
  (rules nil :type list))

(defparameter *max-proof-depth* 32
  "Maximum rule-expansion depth for completion proof search.")

(defun make-fact-from-spec (spec)
  (make-fact :predicate (first spec) :args (rest spec)))

(defun make-rule-from-spec (spec)
  (make-rule :head (first spec) :body (rest spec)))

(defgeneric predicate-true-p (predicate args bindings)
  (:documentation "Return true when PREDICATE with walked ARGS is true in the current environment."))

(defmethod predicate-true-p ((predicate symbol) args bindings)
  (declare (ignore predicate args bindings))
  nil)

(defun assert-fact! (kb fact)
  (push fact (rule-knowledge-base-facts kb))
  kb)

(defun assert-rule! (kb rule)
  (push rule (rule-knowledge-base-rules kb))
  kb)

(defun logic-variable-symbol-p (x)
  (and (symbolp x)
       (< 0 (length (symbol-name x)))
       (char= #\? (char (symbol-name x) 0))))

(defun variable-name (symbol)
  (subseq (symbol-name symbol) 1))

(defun convert-logic-variables (form env)
  (cond
    ((logic-variable-symbol-p form)
     (or (gethash form env)
         (setf (gethash form env)
               (nshell.domain.parsing:make-var (variable-name form)))))
    ((consp form)
     (cons (convert-logic-variables (car form) env)
           (convert-logic-variables (cdr form) env)))
    (t form)))

(defun fact-head (fact env)
  (convert-logic-variables (cons (fact-predicate fact) (fact-args fact)) env))

(defun rule-head-term (rule env)
  (convert-logic-variables (rule-head rule) env))

(defun rule-body-terms (rule env)
  (mapcar (lambda (goal) (convert-logic-variables goal env))
          (rule-body rule)))

(defun prove-body (kb goals bindings depth)
  (if (null goals)
      (list bindings)
      (loop for solution in (prove-internal kb (first goals) bindings depth)
            append (prove-body kb (rest goals) solution depth))))

(defun prove-built-in-solutions (goal bindings)
  (let* ((predicate (first goal))
         (args (mapcar (lambda (arg) (nshell.domain.parsing:walk arg bindings))
                       (rest goal))))
    (when (predicate-true-p predicate args bindings)
      (list bindings))))

(defun prove-internal (kb goal bindings depth)
  (let ((solutions '()))
    (dolist (fact (rule-knowledge-base-facts kb))
      (let ((candidate (nshell.domain.parsing:unify goal (fact-head fact (make-hash-table :test #'eq)) bindings)))
        (when (nshell.domain.parsing:unify-p candidate)
          (push candidate solutions))))
    (when (plusp depth)
      (dolist (rule (rule-knowledge-base-rules kb))
        (let* ((env (make-hash-table :test #'eq))
               (head (rule-head-term rule env))
               (body (rule-body-terms rule env))
               (head-bindings (nshell.domain.parsing:unify goal head bindings)))
          (when (nshell.domain.parsing:unify-p head-bindings)
            (setf solutions
                  (append (prove-body kb body head-bindings (1- depth))
                          solutions))))))
    (append (nreverse solutions)
            (prove-built-in-solutions goal bindings))))

(defun externalize-bindings (env bindings)
  (let ((result '()))
    (maphash (lambda (symbol var)
               (let ((value (nshell.domain.parsing:walk var bindings)))
                 (unless (nshell.domain.parsing:var-p value)
                   (push (cons symbol value) result))))
             env)
    (nreverse result)))

(defun prove (kb goal &optional (bindings '()) (max-depth *max-proof-depth*))
  (let* ((env (make-hash-table :test #'eq))
         (internal-goal (convert-logic-variables goal env)))
    (mapcar (lambda (solution)
              (externalize-bindings env solution))
            (prove-internal kb internal-goal bindings max-depth))))

(defun prove-all (kb goal &key (max-depth *max-proof-depth*))
  (prove kb goal '() max-depth))

(defparameter *built-in-rule-knowledge-base*
  (make-rule-knowledge-base
   :facts (mapcar #'make-fact-from-spec
                  (builtin-rule-facts))
   :rules (mapcar #'make-rule-from-spec
                  (builtin-rule-rules))))
