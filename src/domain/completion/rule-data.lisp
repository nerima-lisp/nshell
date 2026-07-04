; Prolog-style logic engine: facts, rules, unification, and proof search.
(in-package #:nshell.domain.completion)

(defstruct fact
  (predicate nil :type symbol :read-only t)
  (args '() :type list :read-only t))

(defstruct rule
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

(defun fact-spec-predicate (spec)
  (first spec))

(defun fact-spec-args (spec)
  (rest spec))

(defun rule-spec-head (spec)
  (first spec))

(defun rule-spec-body (spec)
  (rest spec))

(defun next-proof-goal (goals)
  (first goals))

(defun remaining-proof-goals (goals)
  (rest goals))

(defun goal-predicate (goal)
  (first goal))

(defun goal-arguments (goal)
  (rest goal))

(defun %make-fact-from-spec (spec)
  (make-fact :predicate (fact-spec-predicate spec)
             :args (fact-spec-args spec)))

(defun %make-rule-from-spec (spec)
  (make-rule :head (rule-spec-head spec)
             :body (rule-spec-body spec)))

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

(defun logic-variable-symbol-p (x)
  (and (symbolp x)
       (< 0 (length (symbol-name x)))
       (char= #\? (char (symbol-name x) 0))))

(defun variable-name (symbol)
  (subseq (symbol-name symbol) 1))

(declaim (ftype (function (t hash-table) t) convert-logic-variables))

(defun logic-form-pair-head (form)
  (car form))

(defun logic-form-pair-tail (form)
  (cdr form))

(defun make-logic-form-pair (head tail)
  (cons head tail))

(defun convert-logic-form-pair (form env)
  (make-logic-form-pair
   (convert-logic-variables (logic-form-pair-head form) env)
   (convert-logic-variables (logic-form-pair-tail form) env)))

(defun convert-logic-variables (form env)
  (cond
    ((logic-variable-symbol-p form)
     (or (gethash form env)
         (setf (gethash form env)
               (nshell.domain.parsing:make-var (variable-name form)))))
    ((consp form)
     (convert-logic-form-pair form env))
    (t form)))

(defun fact-head (fact env)
  (convert-logic-variables (cons (fact-predicate fact) (fact-args fact)) env))

(defun rule-head-term (rule env)
  (convert-logic-variables (rule-head rule) env))

(defun rule-body-terms (rule env)
  (mapcar (lambda (goal) (convert-logic-variables goal env))
          (rule-body rule)))

(declaim (ftype (function (proof-search) list) prove-internal))

(defun proof-search-for-goal (search goal bindings &optional (depth (proof-search-depth search)))
  (%make-proof-search (proof-search-kb search) goal bindings depth))

(defun prove-body (search goals bindings)
  (if (null goals)
      (list bindings)
      (loop for solution in (prove-internal
                             (proof-search-for-goal search (next-proof-goal goals) bindings))
            append (prove-body search (remaining-proof-goals goals) solution))))

(defun walk-goal-arguments (goal bindings)
  (mapcar (lambda (arg) (nshell.domain.parsing:walk arg bindings))
          (goal-arguments goal)))

(defun prove-built-in-solutions (search)
  (let ((goal (proof-search-goal search))
        (bindings (proof-search-bindings search)))
    (when (predicate-true-p (goal-predicate goal) (walk-goal-arguments goal bindings) bindings)
      (list bindings))))

(defun fact-solution (fact search)
  (let ((candidate
          (nshell.domain.parsing:unify (proof-search-goal search)
                                       (fact-head fact (make-hash-table :test #'eq))
                                       (proof-search-bindings search))))
    (values candidate (nshell.domain.parsing:unify-p candidate))))

(defun collect-fact-solutions (search solutions)
  (dolist (fact (rule-knowledge-base-facts (proof-search-kb search)) solutions)
    (multiple-value-bind (candidate matched-p) (fact-solution fact search)
      (when matched-p
        (push candidate solutions)))))

(defun fresh-rule-terms (rule)
  (let ((env (make-hash-table :test #'eq)))
    (values (rule-head-term rule env)
            (rule-body-terms rule env))))

(defun rule-solutions (search rule)
  (multiple-value-bind (head body) (fresh-rule-terms rule)
    (let ((head-bindings (nshell.domain.parsing:unify (proof-search-goal search)
                                                      head
                                                      (proof-search-bindings search))))
      (when (nshell.domain.parsing:unify-p head-bindings)
        (prove-body (proof-search-for-goal search
                                           (proof-search-goal search)
                                           head-bindings
                                           (1- (proof-search-depth search)))
                    body
                    head-bindings)))))

(defun collect-rule-solutions (search solutions)
  (when (plusp (proof-search-depth search))
    (dolist (rule (rule-knowledge-base-rules (proof-search-kb search)))
      (setf solutions
            (append (rule-solutions search rule)
                    solutions))))
  solutions)

(defun prepend-built-in-solutions (search solutions)
  (let ((built-in-solutions (prove-built-in-solutions search)))
    (if built-in-solutions
        (append solutions built-in-solutions)
        solutions)))

(defun finalize-proof-solutions (search solutions)
  (prepend-built-in-solutions search (nreverse solutions)))

(defun prove-internal (search)
  (let ((solutions '()))
    (setf solutions (collect-fact-solutions search solutions))
    (setf solutions (collect-rule-solutions search solutions))
    (finalize-proof-solutions search solutions)))

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
            (prove-internal
             (%make-proof-search kb internal-goal bindings max-depth)))))

(defun prove-all (kb goal &key (max-depth *max-proof-depth*))
  (prove kb goal '() max-depth))

(defparameter *built-in-rule-knowledge-base*
  (%make-rule-knowledge-base
   :facts (mapcar #'%make-fact-from-spec
                  (builtin-rule-facts))
   :rules (mapcar #'%make-rule-from-spec
                  (builtin-rule-rules))))
