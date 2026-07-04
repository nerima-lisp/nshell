(in-package #:nshell.domain.parsing)

(defstruct (logic-var
            (:constructor %make-var (name))
            (:predicate var-p))
  name)

(defun make-var (name)
  (%make-var name))

(defvar *unify-fail* (cons :fail :fail))

(defun %unify-failed-p (result)
  (eq result *unify-fail*))

(defstruct (%binding-entry
            (:constructor %make-binding-entry (variable value)))
  (variable nil :read-only t)
  (value nil :read-only t))

(defun %binding-entry-from-pair (pair)
  (when pair
    (%make-binding-entry (car pair) (cdr pair))))

(defun %binding-entry-for-var (var bindings)
  (%binding-entry-from-pair (assoc var bindings :test #'eq)))

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
     (or (occurs-check var (car term) bindings)
         (occurs-check var (cdr term) bindings)))
    (t nil)))

(defun %bind-var (var value bindings)
  (if (occurs-check var value bindings)
      *unify-fail*
      (extend-bindings var value bindings)))

(declaim (ftype (function (t t &optional t) t) unify))

(defun %unify-conses (x y bindings)
  (let ((car-bindings (unify (car x) (car y) bindings)))
    (if (%unify-failed-p car-bindings)
        *unify-fail*
        (unify (cdr x) (cdr y) car-bindings))))

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
      (let ((goal (car goals))
            (rest (cdr goals)))
        (let ((result (funcall goal bindings)))
          (if (unify-p result)
              (multiple-value-bind (final-bindings succeeded-p)
                  (%backtrack rest result)
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
          ((consp resolved) (cons (walk (car resolved) bindings) (walk (cdr resolved) bindings)))
          (t resolved))))
