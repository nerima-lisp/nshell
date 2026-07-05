(in-package #:nshell/test)

(def-suite environment-tests
  :description "Environment domain tests"
  :in nshell-tests)

(in-suite environment-tests)

(defun env-entry-value (entries name)
  (let ((entry (find name entries
                     :key #'nshell.domain.environment:env-entry-name
                     :test #'string=)))
    (when entry
      (nshell.domain.environment:env-entry-value entry))))

(test env-set-and-get-roundtrip
  "Variables set in an environment can be retrieved."
  (let* ((env (nshell.domain.environment:make-environment))
         (updated (nshell.domain.environment:env-set env "FOO" "bar" nil)))
    (is (string= "bar" (nshell.domain.environment:env-get updated "FOO")))
    (is (equal '("bar") (nshell.domain.environment:env-get-values updated "FOO")))
    (is (null (nshell.domain.environment:env-get env "FOO")))))

(test env-set-values-preserves-list-elements
  "Structured environment values preserve fish-style list elements losslessly."
  (let* ((env (nshell.domain.environment:make-environment))
         (updated (nshell.domain.environment:env-set-values
                   env "FILES" '("hello world" "tail") nil)))
    (is (string= "hello world tail"
                 (nshell.domain.environment:env-get updated "FILES")))
    (is (equal '("hello world" "tail")
               (nshell.domain.environment:env-get-values updated "FILES")))
    (is (null (nshell.domain.environment:env-get-values env "FILES")))))

(test env-var-structure-is-not-public-api
  "Internal variable records stay behind the environment aggregate API."
  (dolist (name '("ENV-VAR" "ENV-VAR-P" "MAKE-ENV-VAR"
                  "ENV-VAR-NAME" "ENV-VAR-VALUE" "ENV-VAR-VALUES"
                  "ENV-VAR-EXPORTED-P" "ENVIRONMENT-VARS" "ENV-ENTRY"))
    (multiple-value-bind (symbol status)
        (find-symbol name :nshell.domain.environment)
      (declare (ignore symbol))
      (is (not (eq :external status)))))
  (dolist (symbol '(nshell.domain.environment::env-var-p
                    nshell.domain.environment::copy-env-var
                    nshell.domain.environment::make-env-var
                    nshell.domain.environment::env-var-name
                    nshell.domain.environment::env-var-value
                    nshell.domain.environment::env-var-values
                    nshell.domain.environment::env-var-exported-p
                    nshell.domain.environment::environment-vars
                    nshell.domain.environment::copy-environment
                    nshell.domain.environment::copy-env-binding
                    nshell.domain.environment::copy-env-entry))
    (is (not (fboundp symbol)))))

(test env-values-are-detached-from-input-and-output-lists
  "Environment variables own their structured value lists."
  (let* ((values (list "hello world" "tail"))
         (env (nshell.domain.environment:make-environment))
         (updated (nshell.domain.environment:env-set-values
                   env "FILES" values nil))
         (returned (nshell.domain.environment:env-get-values updated "FILES")))
    (setf (first values) "mutated input")
    (setf (first returned) "mutated output")
    (is (equal '("hello world" "tail")
               (nshell.domain.environment:env-get-values updated "FILES")))
    (is (string= "hello world tail"
                 (nshell.domain.environment:env-get updated "FILES")))))

(test env-unset-removes-variable
  "Unsetting a variable removes it from the environment."
  (let* ((env (nshell.domain.environment:make-environment))
         (with-var (nshell.domain.environment:env-set env "FOO" "bar" nil))
         (without-var (nshell.domain.environment:env-unset with-var "FOO")))
    (is (null (nshell.domain.environment:env-get without-var "FOO")))))

(test env-export-marks-existing-variable
  "Exporting a variable makes it appear in the exported environment list."
  (let* ((env (nshell.domain.environment:make-environment))
         (with-var (nshell.domain.environment:env-set env "FOO" "bar" nil))
         (exported (nshell.domain.environment:env-export with-var "FOO")))
    (is (string= "bar"
                 (env-entry-value (nshell.domain.environment:env-list exported)
                                  "FOO")))))

(test env-export-preserves-list-values
  "Exporting a variable preserves its structured list values."
  (let* ((env (nshell.domain.environment:make-environment))
         (with-var (nshell.domain.environment:env-set-values
                    env "FILES" '("hello world" "tail") nil))
         (exported (nshell.domain.environment:env-export with-var "FILES")))
    (is (equal '("hello world" "tail")
               (nshell.domain.environment:env-get-values exported "FILES")))
    (is (string= "hello world tail"
                 (env-entry-value (nshell.domain.environment:env-list exported)
                                  "FILES")))))

(test env-list-only-returns-exported-vars
  "Only exported variables are included in ENV-LIST."
  (let* ((env (nshell.domain.environment:make-environment))
         (env (nshell.domain.environment:env-set env "LOCAL" "no" nil))
         (env (nshell.domain.environment:env-set env "EXPORTED" "yes" t))
         (entries (nshell.domain.environment:env-list env)))
    (is (null (find "LOCAL" entries
                    :key #'nshell.domain.environment:env-entry-name
                    :test #'string=)))
    (is (string= "yes" (env-entry-value entries "EXPORTED")))))

(test env-bindings-returns-all-vars-sorted-with-export-state
  "ENV-BINDINGS exposes local and exported variables for shell-local display."
  (let* ((env (nshell.domain.environment:make-environment))
         (env (nshell.domain.environment:env-set env "ZED" "last" nil))
         (env (nshell.domain.environment:env-set env "ALPHA" "first" t))
         (bindings (nshell.domain.environment:env-bindings env)))
    (is (equal '("ALPHA" "ZED")
               (mapcar #'nshell.domain.environment:env-binding-name bindings)))
    (is (equal '("first")
               (nshell.domain.environment:env-binding-values (first bindings))))
    (is (string= "first"
                 (nshell.domain.environment:env-binding-value (first bindings))))
    (is (nshell.domain.environment:env-binding-exported-p (first bindings)))
    (is (not (nshell.domain.environment:env-binding-exported-p (second bindings))))))

(test env-binding-values-are-detached-projections
  "Environment binding projections cannot mutate aggregate state."
  (let* ((env (nshell.domain.environment:make-environment))
         (env (nshell.domain.environment:env-set-values
               env "FILES" '("hello world" "tail") nil))
         (binding (first (nshell.domain.environment:env-bindings env)))
         (values (nshell.domain.environment:env-binding-values binding)))
    (setf (first values) "mutated projection")
    (is (equal '("hello world" "tail")
               (nshell.domain.environment:env-binding-values binding)))
    (is (equal '("hello world" "tail")
               (nshell.domain.environment:env-get-values env "FILES")))))

(test env-assign-default-preserves-export-state
  "Parameter default assignment updates the aggregate without exposing internals."
  (let* ((env (nshell.domain.environment:make-environment))
         (env (nshell.domain.environment:env-set env "EMPTY" "" t)))
    (is (nshell.domain.environment:env-defined-p env "EMPTY"))
    (is (nshell.domain.environment:env-exported-p env "EMPTY"))
    (is (string= "filled"
                 (nshell.domain.environment:env-assign-default!
                  env "EMPTY" "filled")))
    (is (string= "filled" (nshell.domain.environment:env-get env "EMPTY")))
    (is (nshell.domain.environment:env-exported-p env "EMPTY"))))

(test default-environment-has-core-variables
  "The default environment contains core shell variables."
  (let ((env (nshell.domain.environment:make-default-environment)))
    (dolist (name '("HOME" "PATH" "USER"))
      (is (stringp (nshell.domain.environment:env-get env name))))))
