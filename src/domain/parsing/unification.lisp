(in-package #:nshell.domain.parsing)

(defstruct (logic-var
            (:constructor %make-var (name))
            (:predicate var-p)
            (:copier nil))
  name)

(defun make-var (name)
  (%make-var name))

(defvar *unify-fail* (cons :fail :fail))

(defun %unify-failed-p (result)
  (eq result *unify-fail*))

(defstruct (%binding-entry
            (:constructor %make-binding-entry (variable value))
            (:copier nil))
  (variable nil :read-only t)
  (value nil :read-only t))

(defun %binding-entry-from-pair (pair)
  (when pair
    (%make-binding-entry (car pair) (cdr pair))))

(defun %binding-entry-for-var (var bindings)
  (%binding-entry-from-pair (assoc var bindings :test #'eq)))

(defstruct (%cons-term
            (:constructor %make-cons-term (head tail))
            (:copier nil))
  (head nil :read-only t)
  (tail nil :read-only t))

(defun %cons-term-from-raw (term)
  (when (consp term)
    (%make-cons-term (car term) (cdr term))))

(defstruct (%goal-cursor
            (:constructor %make-goal-cursor (goal rest))
            (:copier nil))
  (goal nil :read-only t)
  (rest nil :read-only t))

(defun %goal-cursor-from-goals (goals)
  (when goals
    (%make-goal-cursor (car goals) (cdr goals))))

(defun lookup-var (var bindings)
  (let ((entry (%binding-entry-for-var var bindings)))
    (if entry
        (let ((val (%binding-entry-value entry)))
          (if (var-p val)
              (lookup-var val bindings)
              val))
        var)))

(defun %resolve-term (term bindings)
  (if (var-p term)
      (lookup-var term bindings)
      term))

(defun extend-bindings (var value bindings)
  (acons var value bindings))

(defun occurs-check (var term bindings)
  (cond
    ((eq var term) t)
    ((var-p term)
     (let ((val (lookup-var term bindings)))
       (if (eq val term) nil (occurs-check var val bindings))))
    ((consp term)
     (let ((cons-term (%cons-term-from-raw term)))
       (or (occurs-check var (%cons-term-head cons-term) bindings)
           (occurs-check var (%cons-term-tail cons-term) bindings))))
    (t nil)))

(defun %bind-var (var value bindings)
  (if (occurs-check var value bindings)
      *unify-fail*
      (extend-bindings var value bindings)))

(declaim (ftype (function (t t &optional t) t) unify))

(defun %unify-conses (x y bindings)
  (let* ((x-term (%cons-term-from-raw x))
         (y-term (%cons-term-from-raw y))
         (head-bindings (unify (%cons-term-head x-term)
                               (%cons-term-head y-term)
                               bindings)))
    (if (%unify-failed-p head-bindings)
        *unify-fail*
        (unify (%cons-term-tail x-term)
               (%cons-term-tail y-term)
               head-bindings))))

(defun unify (x y &optional (bindings '()))
  "Unify X and Y under BINDINGS. Returns bindings on success, *UNIFY-FAIL* on failure.
Use UNIFY-P to check success."
  (let ((x1 (%resolve-term x bindings))
        (y1 (%resolve-term y bindings)))
    (cond
      ((and (var-p x1) (var-p y1) (eq x1 y1)) bindings)
      ((var-p x1) (%bind-var x1 y1 bindings))
      ((var-p y1) (%bind-var y1 x1 bindings))
      ((and (atom x1) (atom y1)) (if (equal x1 y1) bindings *unify-fail*))
      ((and (consp x1) (consp y1)) (%unify-conses x1 y1 bindings))
      (t *unify-fail*))))

(defun unify-p (result)
  "True if unification succeeded (not *UNIFY-FAIL*)."
  (not (%unify-failed-p result)))

(defun %backtrack (goals bindings)
  (if (null goals)
      (values bindings t)
      (let ((cursor (%goal-cursor-from-goals goals)))
        (let ((result (funcall (%goal-cursor-goal cursor) bindings)))
          (if (unify-p result)
              (multiple-value-bind (final-bindings succeeded-p)
                  (%backtrack (%goal-cursor-rest cursor) result)
                (if succeeded-p
                    (values final-bindings t)
                    (values nil nil)))
              (values nil nil))))))

(defun backtrack (goals &optional (bindings '()))
  (multiple-value-bind (final-bindings succeeded-p)
      (%backtrack goals bindings)
    (and succeeded-p final-bindings)))

(defun walk (term bindings)
  (let ((resolved (%resolve-term term bindings)))
    (cond ((var-p resolved) resolved)
          ((consp resolved)
           (let ((cons-term (%cons-term-from-raw resolved)))
             (cons (walk (%cons-term-head cons-term) bindings)
                   (walk (%cons-term-tail cons-term) bindings))))
          (t resolved))))
