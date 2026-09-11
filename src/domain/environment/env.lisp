;;; Environment variable model
(in-package #:nshell.domain.environment)

(nshell.util:define-value-struct
  env-var
  ((name "" :type string)
   (values nil :type list :copy :list)
   (exported-p nil :type boolean))
  :documentation
  "A read-only shell environment variable."
  :constructor
  %allocate-env-var
  :predicate
  nil
  :public-accessors
  nil)

(defun %copy-env-value-list (values)
  "Return a detached environment value list after validating its elements."
  (check-type values list)
  (dolist (value values)
    (check-type value string))
  (copy-list values))

(defun %make-env-var-with-invariants (name values &optional exported-p)
  "Create a shell environment variable from structured VALUES.
The scalar string view is derived from VALUES on demand."
  (check-type name string)
  (%allocate-env-var name (%copy-env-value-list values) (not (null exported-p))))

(defun %env-var-value (var)
  "Return the scalar string view of VAR."
  (format nil "~{~a~^ ~}" (%env-var-values var)))

(define-value-struct
  env-binding
  ((name "" :type string)
    (values nil :type list :copy :list)
    (exported-p nil :type boolean))
  :documentation
  "Read-only projection of an environment variable."
  :constructor
  %allocate-env-binding
  :predicate
  nil)

(defun %make-env-binding-with-invariants (name values exported-p)
  "Create a detached read-only binding projection."
  (check-type name string)
  (%allocate-env-binding
    name
    (%copy-env-value-list values)
    (not (null exported-p))))

(defun env-binding-value (binding)
  "Return BINDING's scalar string value."
  (format nil "~{~a~^ ~}" (%env-binding-values binding)))

(define-value-struct
  env-entry
  ((name "" :type string) (value "" :type string))
  :documentation
  "Read-only projection of an exported environment variable."
  :constructor
  %allocate-env-entry)

(defun %make-env-entry-with-invariants (name value)
  "Create a read-only exported environment entry projection."
  (check-type name string)
  (check-type value string)
  (%allocate-env-entry name value))

(defstruct (environment
    (:constructor %allocate-environment (scopes))
    (:conc-name %environment-)
    (:copier nil))
  "A collection of shell environment variables organized as a scope chain.
SCOPES is a list of variable hash-tables, innermost (current) scope first; a
name lookup walks the list outward and a plain write updates whichever scope
already defines the name, following fish's function-scoping rules."
  (scopes (list (make-hash-table :test #'equal)) :type list :read-only t))

(defun make-environment ()
  "Create an empty environment with a single scope."
  (%allocate-environment (list (make-hash-table :test #'equal))))

(defun %copy-hash-table (table)
  "Return a shallow copy of TABLE."
  (let ((copy (make-hash-table :test #'equal)))
    (maphash
      (lambda (name var)
        (setf (gethash name copy) var))
      table)
    copy))

(defun %copy-environment-scopes (scopes)
  "Return a fresh list of shallow copies of each table in SCOPES."
  (mapcar #'%copy-hash-table scopes))

(defun %environment-find-var (env name)
  "Return the env-var record for NAME from the innermost scope defining it,
or NIL when NAME is not defined in any scope of ENV."
  (dolist (scope (%environment-scopes env))
    (multiple-value-bind (var found) (gethash name scope)
      (when found (return-from %environment-find-var var))))
  nil)

(defun %environment-scope-index (scopes name)
  "Return the index in SCOPES of the innermost scope defining NAME, or NIL."
  (position-if (lambda (table) (nth-value 1 (gethash name table))) scopes))

(defun %environment-visible-vars (env)
  "Return an alist of (NAME . VAR) for every name visible in ENV, using the
innermost scope's binding for a name shadowed by an outer scope."
  (let ((seen (make-hash-table :test #'equal))
        (result nil))
    (dolist (scope (%environment-scopes env) result)
      (maphash
        (lambda (name var)
          (unless (gethash name seen)
            (setf (gethash name seen) t)
            (push (cons name var) result)))
        scope))))

(defun %environment-write-index (scopes name scope)
  "Return the SCOPES index a write for NAME under keyword SCOPE targets.
:LOCAL always targets the innermost scope, :GLOBAL always targets the
outermost one, and NIL (the fish default) targets the innermost scope
already defining NAME, falling back to the innermost scope for a new name."
  (case scope
    (:local 0)
    (:global (1- (length scopes)))
    (t (or (%environment-scope-index scopes name) 0))))

(defun env-set-values (env name values exported &key scope)
  "Return ENV updated with NAME set to VALUES in the scope SCOPE selects.
The structured VALUES list is the source of truth; scalar accessors derive
their result by joining VALUES with spaces. SCOPE is :LOCAL, :GLOBAL, or NIL
for the fish default described at %ENVIRONMENT-WRITE-INDEX."
  (check-type name string)
  (let* ((copied (%copy-environment-scopes (%environment-scopes env)))
         (index (%environment-write-index copied name scope))
         (table (nth index copied)))
    (setf (gethash name table) (%make-env-var-with-invariants name values exported))
    (%allocate-environment copied)))

(defun env-set (env name value exported &key scope)
  "Return ENV updated with NAME set to scalar VALUE.
EXPORTED controls whether the variable appears in ENV-LIST; SCOPE is as in
ENV-SET-VALUES."
  (check-type value string)
  (env-set-values env name (list value) exported :scope scope))

(defun %make-default-environment-var-table ()
  "Return a new variable table seeded with fallback environment values."
  (let ((vars (make-hash-table :test #'equal)))
    (setf (gethash "HOME" vars) (%make-env-var-with-invariants "HOME" (list "/") t))
    (setf (gethash "PATH" vars) (%make-env-var-with-invariants "PATH" (list "/bin:/usr/bin") t))
    (setf (gethash "USER" vars) (%make-env-var-with-invariants "USER" (list "nobody") t))
    (setf (gethash "PWD" vars) (%make-env-var-with-invariants "PWD" (list "/") t))
    (setf (gethash "SHELL" vars) (%make-env-var-with-invariants "SHELL" (list "/bin/sh") t))
    (setf (gethash "TERM" vars) (%make-env-var-with-invariants "TERM" (list "dumb") t))
    vars))

(defun make-default-environment ()
  "Create a default environment with fallback values.
Pure domain function - callers should provide OS values via inject-os-environment."
  (%allocate-environment (list (%make-default-environment-var-table))))

(defun env-get (env name)
  "Return the value of NAME in ENV, or NIL when it is not defined."
  (let ((var (%environment-find-var env name)))
    (when var
      (%env-var-value var))))

(defun env-get-values (env name)
  "Return the structured values of NAME in ENV, or NIL when it is not defined."
  (let ((var (%environment-find-var env name)))
    (when var
      (copy-list (%env-var-values var)))))

(defun env-defined-p (env name)
  "Return true when NAME is defined in any scope of ENV."
  (not (null (%environment-find-var env name))))

(defun env-exported-p (env name)
  "Return true when NAME is defined and exported in its innermost scope."
  (let ((var (%environment-find-var env name)))
    (and var (%env-var-exported-p var))))

(defun %inject-os-environment-entry (vars entry)
  (let ((separator (position #\= entry)))
    (when (and separator (plusp separator))
      (let ((name (subseq entry 0 separator))
            (value (subseq entry (1+ separator))))
        (setf (gethash name vars) (%make-env-var-with-invariants name (list value) t))))))

(defun %inject-os-environment-entries (env entries getcwd)
  (let* ((scopes (%copy-environment-scopes (%environment-scopes env)))
         (global (car (last scopes))))
    (dolist (entry entries)
      (%inject-os-environment-entry global entry))
    (let ((pwd
          (handler-case (namestring (funcall getcwd))
            (error ()
              (let ((var (gethash "PWD" global)))
                (and var (%env-var-value var)))))))
      (setf (gethash "PWD" global) (%make-env-var-with-invariants "PWD" (list pwd) t)))
    (%allocate-environment scopes)))

(defun inject-os-environment (env entries getcwd)
  "Return ENV with ENTRIES and GETCWD supplied by the infrastructure boundary.
ENTRIES contains \"KEY=VALUE\" strings and GETCWD is a zero-argument function.
Injection always lands in ENV's outermost (global) scope."
  (check-type entries list)
  (check-type getcwd function)
  (%inject-os-environment-entries env entries getcwd))

(defun env-unset (env name)
  "Return ENV without NAME, removing it from whichever scope currently
defines it (innermost first), so a shadowed outer binding reappears."
  (check-type name string)
  (let* ((copied (%copy-environment-scopes (%environment-scopes env)))
         (index (%environment-scope-index copied name)))
    (when index
      (remhash name (nth index copied)))
    (%allocate-environment copied)))

(defun env-export (env name)
  "Return ENV with NAME marked exported in its innermost scope, preserving
its current value."
  (check-type name string)
  (let* ((copied (%copy-environment-scopes (%environment-scopes env)))
         (index (%environment-scope-index copied name)))
    (when index
      (let* ((table (nth index copied))
             (var (gethash name table)))
        (setf (gethash name table) (%make-env-var-with-invariants name (%env-var-values var) t))))
    (%allocate-environment copied)))

(defun env-push-scope (env)
  "Return ENV with a new, empty scope innermost, shadowing existing bindings
until it is popped."
  (%allocate-environment (cons (make-hash-table :test #'equal) (%environment-scopes env))))

(defun env-push-call-scope (env)
  "Return ENV as a called function sees it: one new empty scope over the global
one, with the caller's locals dropped. A caller's `set -l' must not reach the
function it calls, and `set -lx' must not reach that function's subprocesses."
  (%allocate-environment
   (list (make-hash-table :test #'equal)
         (first (last (%environment-scopes env))))))

(defun env-restore-scopes (env source)
  "Return ENV's innermost-scope contents discarded and SOURCE's scope chain
restored, keeping any write the callee made to the global scope."
  (let ((scopes (%environment-scopes env))
        (outer (%environment-scopes source)))
    (%allocate-environment
     (append (butlast outer) (last scopes)))))

(defun env-pop-scope (env)
  "Return ENV with its innermost scope removed. A single-scope ENV is
returned unchanged, since the outermost (global) scope is never popped."
  (let ((scopes (%environment-scopes env)))
    (if (rest scopes)
        (%allocate-environment (rest scopes))
        env)))

(defun env-assign-default! (env name value)
  "Assign VALUE to NAME inside ENV, preserving NAME's export state.
This operation is intentionally destructive for parameter expansion
assignments, which apply to the active shell environment object. NAME is
assigned in whichever scope already defines it, or in the innermost scope
when it is not yet defined anywhere, matching ENV-SET-VALUES's fish default."
  (check-type name string)
  (check-type value string)
  (let* ((scopes (%environment-scopes env))
         (index (%environment-write-index scopes name nil))
         (table (nth index scopes))
         (exported (let ((var (gethash name table))) (and var (%env-var-exported-p var)))))
    (setf (gethash name table) (%make-env-var-with-invariants name (list value) exported)))
  value)

(defun env-bindings (env)
  "Return every visible variable in ENV as read-only projections sorted by
name, using the innermost scope's binding for a shadowed name."
  (let ((bindings nil))
    (dolist (pair (%environment-visible-vars env))
      (let ((name (car pair)) (var (cdr pair)))
        (push
          (%make-env-binding-with-invariants
            name
            (%env-var-values var)
            (%env-var-exported-p var))
          bindings)))
    (sort bindings #'string< :key #'env-binding-name)))

(defun env-list (env)
  "Return exported variables in ENV as ENV-ENTRY values sorted by name.
Every scope contributes, with an inner scope's binding of a name shadowing an
outer scope's, whether or not the inner one is itself exported."
  (let ((entries nil))
    (dolist (pair (%environment-visible-vars env))
      (let ((name (car pair)) (var (cdr pair)))
        (when (%env-var-exported-p var)
          (push (%make-env-entry-with-invariants name (%env-var-value var)) entries))))
    (sort entries #'string< :key #'env-entry-name)))
