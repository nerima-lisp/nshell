;;; Environment variable model
(in-package #:nshell.domain.environment)

(defstruct (env-var
            (:constructor %allocate-env-var (name values exported-p))
            (:conc-name %env-var-)
            (:predicate nil)
            (:copier nil))
  "A shell environment variable."
  (name "" :type string :read-only t)
  (values nil :type list :read-only t)
  (exported-p nil :type boolean :read-only t))

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
  (%allocate-env-var name
                     (%copy-env-value-list values)
                     (not (null exported-p))))

(defun %env-var-value (var)
  "Return the scalar string view of VAR."
  (format nil "~{~a~^ ~}" (%env-var-values var)))

(defstruct (env-binding
            (:constructor %allocate-env-binding (name values exported-p))
            (:conc-name %env-binding-)
            (:predicate nil)
            (:copier nil))
  "Read-only projection of an environment variable."
  (name "" :type string :read-only t)
  (values nil :type list :read-only t)
  (exported-p nil :type boolean :read-only t))

(defun %make-env-binding-with-invariants (name values exported-p)
  "Create a detached read-only binding projection."
  (check-type name string)
  (%allocate-env-binding name
                         (%copy-env-value-list values)
                         (not (null exported-p))))

(defun env-binding-name (binding)
  "Return BINDING's variable name."
  (%env-binding-name binding))

(defun env-binding-values (binding)
  "Return BINDING's structured values."
  (copy-list (%env-binding-values binding)))

(defun env-binding-value (binding)
  "Return BINDING's scalar string value."
  (format nil "~{~a~^ ~}" (%env-binding-values binding)))

(defun env-binding-exported-p (binding)
  "Return true when BINDING is exported."
  (%env-binding-exported-p binding))

(defstruct (env-entry
            (:constructor %allocate-env-entry (name value))
            (:copier nil))
  "Read-only projection of an exported environment variable."
  (name "" :type string :read-only t)
  (value "" :type string :read-only t))

(defun %make-env-entry-with-invariants (name value)
  "Create a read-only exported environment entry projection."
  (check-type name string)
  (check-type value string)
  (%allocate-env-entry name value))

(defstruct (environment
            (:constructor %allocate-environment (vars))
            (:conc-name %environment-)
            (:copier nil))
  "A collection of shell environment variables keyed by name."
  (vars (make-hash-table :test #'equal) :type hash-table :read-only t))

(defun make-environment ()
  "Create an empty environment."
  (%allocate-environment (make-hash-table :test #'equal)))

(defun %copy-env-var-table (env)
  "Return a shallow copy of ENV's variable table."
  (let ((copy (make-hash-table :test #'equal)))
    (maphash (lambda (name var)
               (setf (gethash name copy) var))
             (%environment-vars env))
    copy))

(defun env-set-values (env name values exported)
  "Return ENV updated with NAME set to VALUES.
The structured VALUES list is the source of truth; scalar accessors derive
their result by joining VALUES with spaces."
  (check-type name string)
  (let ((vars (%copy-env-var-table env)))
    (setf (gethash name vars)
          (%make-env-var-with-invariants name values exported))
    (%allocate-environment vars)))

(defun env-set (env name value exported)
  "Return ENV updated with NAME set to scalar VALUE.
EXPORTED controls whether the variable appears in ENV-LIST."
  (check-type value string)
  (env-set-values env name (list value) exported))

(defun make-default-environment ()
  "Create a default environment with fallback values.
   Pure domain function - callers should provide OS values via inject-os-environment."
  (let ((env (make-environment)))
    (setf env (env-set env "HOME" "/" t))
    (setf env (env-set env "PATH" "/bin:/usr/bin" t))
    (setf env (env-set env "USER" "nobody" t))
    (setf env (env-set env "PWD" "/" t))
    (setf env (env-set env "SHELL" "/bin/sh" t))
    (setf env (env-set env "TERM" "dumb" t))
    env))

(defun env-get (env name)
  "Return the value of NAME in ENV, or NIL when it is not defined."
  (let ((var (gethash name (%environment-vars env))))
    (when var (%env-var-value var))))

(defun env-get-values (env name)
  "Return the structured values of NAME in ENV, or NIL when it is not defined."
  (let ((var (gethash name (%environment-vars env))))
    (when var (copy-list (%env-var-values var)))))

(defun env-defined-p (env name)
  "Return true when NAME is defined in ENV."
  (nth-value 1 (gethash name (%environment-vars env))))

(defun env-exported-p (env name)
  "Return true when NAME is defined and exported in ENV."
  (let ((var (gethash name (%environment-vars env))))
    (and var (%env-var-exported-p var))))

(defun %inject-os-environment-entry (env entry)
  (let ((separator (position #\= entry)))
    (if (and separator (plusp separator))
        (env-set env
                 (subseq entry 0 separator)
                 (subseq entry (1+ separator))
                 t)
        env)))

(defun inject-os-environment (env)
  "Inject OS environment values into ENV. Used by infrastructure layer.
   Returns a new environment with OS values overwriting defaults."
  (let ((result env))
    #+sbcl
    (dolist (entry (sb-ext:posix-environ))
      (setf result (%inject-os-environment-entry result entry)))
    #-sbcl
    (dolist (name '("HOME" "PATH" "USER" "SHELL" "TERM"))
      (let ((value (uiop:getenv name)))
        (when value
          (setf result (env-set result name value t)))))
    (setf result
          (env-set result
                   "PWD"
                   (handler-case
                       (namestring (uiop:getcwd))
                     (error () (env-get result "PWD")))
                   t))
    result))

(defun env-unset (env name)
  "Return ENV without NAME."
  (check-type name string)
  (let ((vars (%copy-env-var-table env)))
    (remhash name vars)
    (%allocate-environment vars)))

(defun env-export (env name)
  "Return ENV with NAME marked exported, preserving its current value."
  (check-type name string)
  (let* ((vars (%copy-env-var-table env))
         (var (gethash name vars)))
    (when var
      (setf (gethash name vars)
            (%make-env-var-with-invariants name (%env-var-values var) t)))
    (%allocate-environment vars)))

(defun env-assign-default! (env name value)
  "Assign VALUE to NAME inside ENV, preserving NAME's export state.
This operation is intentionally destructive for parameter expansion assignments,
which apply to the active shell environment object."
  (check-type name string)
  (check-type value string)
  (let ((exported (env-exported-p env name)))
    (setf (gethash name (%environment-vars env))
          (%make-env-var-with-invariants name (list value) exported)))
  value)

(defun env-bindings (env)
  "Return all variables in ENV as read-only projections sorted by name."
  (let ((bindings nil))
    (maphash (lambda (name var)
               (push (%make-env-binding-with-invariants
                      name
                      (%env-var-values var)
                      (%env-var-exported-p var))
                     bindings))
             (%environment-vars env))
    (sort bindings #'string< :key #'env-binding-name)))

(defun env-list (env)
  "Return exported variables in ENV as ENV-ENTRY values sorted by name."
  (let ((entries nil))
    (maphash (lambda (name var)
               (when (%env-var-exported-p var)
                 (push (%make-env-entry-with-invariants
                        name
                        (%env-var-value var))
                       entries)))
             (%environment-vars env))
    (sort entries #'string< :key #'env-entry-name)))
