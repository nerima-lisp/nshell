(in-package #:nshell.application)

(defvar *active-shell-function-scope*
  nil)

(defvar *current-user-evaluator-context*
  nil)

(defvar *current-user-evaluator-position*
  :value)

(defun active-shell-function-scope ()
  *active-shell-function-scope*)

(defun context-shell-function-registry (context)
  (shell-context-shell-function-registry context))

(defun %shell-function-name-text (name)
  (etypecase name
    (string name)
    (symbol (symbol-name name))))

(defun %shell-function-canonical-key (name escaped-p)
  (let ((name-text (%shell-function-name-text name)))
    (if escaped-p
        (list :escaped name-text)
        (string-upcase name-text))))

(defun %shell-function-equal-hash-table-p (table)
  (and (hash-table-p table)
       (let ((test (hash-table-test table)))
         (or (eq test 'equal) (eq test #'equal)))))

(defun %check-shell-function-registry (registry)
  (check-type registry shell-function-registry)
  (unless
      (%shell-function-equal-hash-table-p
       (shell-function-registry-global-table registry))
    (error 'type-error
           :datum
           (shell-function-registry-global-table registry)
           :expected-type
           '(satisfies %shell-function-equal-hash-table-p)))
  registry)

(defun %check-shell-function-scope (scope)
  (when scope
    (check-type scope shell-function-scope)
    (unless
        (%shell-function-equal-hash-table-p (shell-function-scope-table scope))
      (error 'type-error
             :datum
             (shell-function-scope-table scope)
             :expected-type
             '(satisfies %shell-function-equal-hash-table-p))))
  scope)

(defun %find-shell-function (registry canonical-key scope)
  (block found
    (loop for current-scope = scope then (shell-function-scope-parent
                                          current-scope)
          while current-scope
          do (multiple-value-bind (binding present-p)
                 (gethash canonical-key
                          (shell-function-scope-table current-scope))
               (when present-p
                 (return-from found
                   (values binding t)))))
    (gethash canonical-key (shell-function-registry-global-table registry))))

(defun register-shell-function (registry name binding &key escaped-p)
  (%check-shell-function-registry registry)
  (check-type name (or string symbol))
  (check-type binding shell-function-binding)
  (check-type escaped-p boolean)
  (setf (gethash (%shell-function-canonical-key name escaped-p)
                 (shell-function-registry-global-table registry)) binding))

(defun peek-shell-function (registry name &key scope escaped-p)
  (%check-shell-function-registry registry)
  (check-type name (or string symbol))
  (check-type escaped-p boolean)
  (%check-shell-function-scope scope)
  (%find-shell-function registry
                        (%shell-function-canonical-key name escaped-p)
                        scope))

(defun lookup-shell-function (registry name &key scope escaped-p)
  (%check-shell-function-registry registry)
  (check-type name (or string symbol))
  (check-type escaped-p boolean)
  (%check-shell-function-scope scope)
  (let* ((canonical-key (%shell-function-canonical-key name escaped-p))
         (hook (shell-function-registry-lookup-miss-hook registry)))
    (multiple-value-bind (binding found-p)
        (%find-shell-function registry canonical-key scope)
      (when found-p
        (return-from lookup-shell-function
          (values binding t))))
    (when hook
      (funcall hook registry canonical-key))
    (%find-shell-function registry canonical-key scope)))

(defmacro define-shell-function (name lambda-list &body body)
  "Define a shell function; string names preserve exact escaped spelling."
  (let* ((name-text (%shell-function-name-text name))
         (escaped-p (or (stringp name)
                        (and (symbolp name)
                             (not (string= name-text
                                           (string-upcase name-text))))))
         (source-path (or *compile-file-truename* *load-truename*)))
    `(register-shell-function
      (context-shell-function-registry *current-user-evaluator-context*)
      ,name-text
      (make-shell-function-binding
       (lambda (context evaluated-command-args call-position)
         (let ((*current-user-evaluator-context* context)
               (*current-user-evaluator-position* call-position))
           (apply
            (lambda ,lambda-list
              ,@body)
            (mapcar #'nshell.domain.parsing:evaluated-command-arg-value
                    evaluated-command-args))))
       ',lambda-list
       ,name-text
       ',source-path
       nil)
      :escaped-p
      ,escaped-p)))

(defmacro with-shell-functions (bindings &body body)
  "Bind shell functions in a child scope; string names preserve exact spelling."
  (let ((scope (gensym "SCOPE")))
    `(let* ((,scope
             (make-shell-function-scope (make-hash-table :test #'equal)
                                        (active-shell-function-scope))))
       ,@(loop for (name binding) in bindings
               for name-text = (%shell-function-name-text name)
               for escaped-p = (or (stringp name)
                                   (and (symbolp name)
                                        (not
                                         (string= name-text
                                                  (string-upcase name-text)))))
               collect `(setf (gethash
                               (%shell-function-canonical-key ',name ,escaped-p)
                               (shell-function-scope-table ,scope)) ,binding))
       (let ((*active-shell-function-scope* ,scope))
         ,@body))))
