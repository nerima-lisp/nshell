(in-package #:nshell/test)

(def-suite environment-tests
  :description "Environment domain tests"
  :in nshell-tests)

(in-suite environment-tests)

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

(test make-env-var-derives-scalar-view-from-values
  "The constructor keeps structured values and derives the scalar view on demand."
  (let* ((values (list "hello world" "tail"))
         (var (nshell.domain.environment:make-env-var "FILES" values nil)))
    (setf (first values) "changed")
    (is (equal '("hello world" "tail")
               (nshell.domain.environment:env-var-values var)))
    (is (string= "hello world tail"
                 (nshell.domain.environment:env-var-value var)))
    (is (not (nshell.domain.environment:env-var-exported-p var)))))

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
    (is (equal '("FOO" . "bar")
               (assoc "FOO" (nshell.domain.environment:env-list exported) :test #'string=)))))

(test env-export-preserves-list-values
  "Exporting a variable preserves its structured list values."
  (let* ((env (nshell.domain.environment:make-environment))
         (with-var (nshell.domain.environment:env-set-values
                    env "FILES" '("hello world" "tail") nil))
         (exported (nshell.domain.environment:env-export with-var "FILES")))
    (is (equal '("hello world" "tail")
               (nshell.domain.environment:env-get-values exported "FILES")))
    (is (equal '("FILES" . "hello world tail")
               (assoc "FILES" (nshell.domain.environment:env-list exported)
                      :test #'string=)))))

(test env-list-only-returns-exported-vars
  "Only exported variables are included in ENV-LIST."
  (let* ((env (nshell.domain.environment:make-environment))
         (env (nshell.domain.environment:env-set env "LOCAL" "no" nil))
         (env (nshell.domain.environment:env-set env "EXPORTED" "yes" t))
         (pairs (nshell.domain.environment:env-list env)))
    (is (null (assoc "LOCAL" pairs :test #'string=)))
    (is (equal '("EXPORTED" . "yes")
               (assoc "EXPORTED" pairs :test #'string=)))))

(test env-bindings-returns-all-vars-sorted-with-export-state
  "ENV-BINDINGS exposes local and exported variables for shell-local display."
  (let* ((env (nshell.domain.environment:make-environment))
         (env (nshell.domain.environment:env-set env "ZED" "last" nil))
         (env (nshell.domain.environment:env-set env "ALPHA" "first" t))
         (bindings (nshell.domain.environment:env-bindings env)))
    (is (equal '("ALPHA" "ZED")
               (mapcar #'nshell.domain.environment:env-var-name bindings)))
    (is (nshell.domain.environment:env-var-exported-p (first bindings)))
    (is (not (nshell.domain.environment:env-var-exported-p (second bindings))))))

(test default-environment-has-core-variables
  "The default environment contains core shell variables."
  (let ((env (nshell.domain.environment:make-default-environment)))
    (dolist (name '("HOME" "PATH" "USER"))
      (is (stringp (nshell.domain.environment:env-get env name))))))
