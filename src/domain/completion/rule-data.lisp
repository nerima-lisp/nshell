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

(defstruct (%fact-spec-projection
            (:constructor %make-fact-spec-projection (predicate args))
            (:conc-name %fact-spec-projection-))
  predicate
  args)

(defstruct (%rule-spec-projection
            (:constructor %make-rule-spec-projection (head body))
            (:conc-name %rule-spec-projection-))
  head
  body)

(defstruct (%proof-goal-sequence
            (:constructor %make-proof-goal-sequence
                (next-goal remaining-goals))
            (:conc-name %proof-goal-sequence-))
  next-goal
  remaining-goals)

(defstruct (%proof-goal-projection
            (:constructor %make-proof-goal-projection (predicate arguments))
            (:conc-name %proof-goal-projection-))
  predicate
  arguments)

(defun %project-fact-spec (spec)
  (%make-fact-spec-projection (first spec) (rest spec)))

(defun %project-rule-spec (spec)
  (%make-rule-spec-projection (first spec) (rest spec)))

(defun %proof-goal-sequence-from-goals (goals)
  (%make-proof-goal-sequence (first goals) (rest goals)))

(defun %project-proof-goal (goal)
  (%make-proof-goal-projection (first goal) (rest goal)))

(defun make-fact (&key predicate (args '()))
  (check-type predicate symbol)
  (check-type args list)
  (%allocate-fact predicate (copy-list args)))

(defun make-rule (&key (head '()) (body '()))
  (check-type head list)
  (check-type body list)
  (%allocate-rule (copy-list head) (copy-list body)))

(defun %make-fact-from-spec (spec)
  (let ((projection (%project-fact-spec spec)))
    (make-fact :predicate (%fact-spec-projection-predicate projection)
               :args (%fact-spec-projection-args projection))))

(defun %make-rule-from-spec (spec)
  (let ((projection (%project-rule-spec spec)))
    (make-rule :head (%rule-spec-projection-head projection)
               :body (%rule-spec-projection-body projection))))

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
               (nshell.domain.parsing:make-var (%logic-variable-name form)))))
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

(declaim (ftype (function (proof-search) list) prove-internal))

(defun proof-search-for-goal (search goal bindings &optional (depth (proof-search-depth search)))
  (%make-proof-search (proof-search-kb search) goal bindings depth))

(defun prove-body (search goals bindings)
  (if (null goals)
      (list bindings)
      (let ((goal-sequence (%proof-goal-sequence-from-goals goals)))
        (loop for solution in (prove-internal
                               (proof-search-for-goal
                                search
                                (%proof-goal-sequence-next-goal goal-sequence)
                                bindings))
              append (prove-body
                      search
                      (%proof-goal-sequence-remaining-goals goal-sequence)
                      solution)))))

(defun walk-goal-arguments (goal bindings)
  (let ((projection (%project-proof-goal goal)))
    (mapcar (lambda (arg) (nshell.domain.parsing:walk arg bindings))
            (%proof-goal-projection-arguments projection))))

(defun prove-built-in-solutions (search)
  (let ((goal (proof-search-goal search))
        (bindings (proof-search-bindings search)))
    (when (predicate-true-p
           (%proof-goal-projection-predicate (%project-proof-goal goal))
           (walk-goal-arguments goal bindings)
           bindings)
      (list bindings))))

(defun fact-solution (fact search)
  (let ((candidate
          (nshell.domain.parsing:unify (proof-search-goal search)
                                       (%fact-head fact (make-hash-table :test #'eq))
                                       (proof-search-bindings search))))
    (values candidate (nshell.domain.parsing:unify-p candidate))))

(defun collect-fact-solutions (search solutions)
  (dolist (fact (rule-knowledge-base-facts (proof-search-kb search)) solutions)
    (multiple-value-bind (candidate matched-p) (fact-solution fact search)
      (when matched-p
        (push candidate solutions)))))

(defun fresh-rule-terms (rule)
  (let ((env (make-hash-table :test #'eq)))
    (values (%rule-head-term rule env)
            (%rule-body-terms rule env))))

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
         (internal-goal (%convert-logic-variables goal env)))
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
