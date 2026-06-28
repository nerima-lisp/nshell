;;; Environment variable model
(in-package #:nshell.domain.environment)

(defstruct (env-var (:constructor %make-env-var (name values &optional exported-p)))
  "A shell environment variable."
  (name "" :type string :read-only t)
  (values nil :type list :read-only t)
  (exported-p nil :type boolean :read-only t))

(defun make-env-var (name values &optional exported-p)
  "Create a shell environment variable from structured VALUES.
The scalar string view is derived from VALUES on demand."
  (check-type name string)
  (dolist (value values)
    (check-type value string))
  (%make-env-var name (copy-list values) (not (null exported-p))))

(defun env-var-value (var)
  "Return the scalar string view of VAR."
  (format nil "~{~a~^ ~}" (env-var-values var)))

(defstruct (environment (:constructor %make-environment (vars)))
  "A collection of shell environment variables keyed by name."
  (vars (make-hash-table :test #'equal) :type hash-table :read-only t))

(defun make-environment ()
  "Create an empty environment."
  (%make-environment (make-hash-table :test #'equal)))

(defun copy-env-vars (env)
  "Return a shallow copy of ENV's variable table."
  (let ((copy (make-hash-table :test #'equal)))
    (maphash (lambda (name var)
               (setf (gethash name copy) var))
             (environment-vars env))
    copy))

(defun env-set-values (env name values exported)
  "Return ENV updated with NAME set to VALUES.
The structured VALUES list is the source of truth; scalar accessors derive
their result by joining VALUES with spaces."
  (check-type name string)
  (dolist (value values)
    (check-type value string))
  (let ((vars (copy-env-vars env)))
    (setf (gethash name vars)
          (make-env-var name values exported))
    (%make-environment vars)))

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
  (let ((var (gethash name (environment-vars env))))
    (when var (env-var-value var))))

(defun env-get-values (env name)
  "Return the structured values of NAME in ENV, or NIL when it is not defined."
  (let ((var (gethash name (environment-vars env))))
    (when var (copy-list (env-var-values var)))))

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
  (let ((vars (copy-env-vars env)))
    (remhash name vars)
    (%make-environment vars)))

(defun env-export (env name)
  "Return ENV with NAME marked exported, preserving its current value."
  (check-type name string)
  (let* ((vars (copy-env-vars env))
         (var (gethash name vars)))
    (when var
      (setf (gethash name vars)
            (make-env-var name (env-var-values var) t)))
    (%make-environment vars)))

(defun env-bindings (env)
  "Return all variables in ENV sorted by name."
  (let ((vars nil))
    (maphash (lambda (name var)
               (declare (ignore name))
               (push var vars))
             (environment-vars env))
    (sort vars #'string< :key #'env-var-name)))

(defun env-list (env)
  "Return exported variables in ENV as a list of (NAME . VALUE) pairs."
  (let ((pairs nil))
    (maphash (lambda (name var)
               (when (env-var-exported-p var)
                 (push (cons name (env-var-value var)) pairs)))
             (environment-vars env))
    (sort pairs #'string< :key #'car)))
