(in-package #:nshell/test)

(defun env-entry-value (entries name)
  (let ((entry
        (find
          name
          entries
          :key
          #'nshell.domain.environment:env-entry-name
          :test
          #'string=)))
    (when entry
      (nshell.domain.environment:env-entry-value entry))))

(describe
  "environment-tests"
  (it
    "env-set-and-get-roundtrip"
    "Variables set in an environment can be retrieved."
    (let* ((env (nshell.domain.environment:make-environment))
           (updated (nshell.domain.environment:env-set env "FOO" "bar" nil)))
      (expect "bar" :to-equal (nshell.domain.environment:env-get updated "FOO"))
      (expect
        '("bar")
        :to-equal
        (nshell.domain.environment:env-get-values updated "FOO"))
      (expect (nshell.domain.environment:env-get env "FOO") :to-be-null)))
  (it
    "env-set-values-preserves-list-elements"
    "Structured environment values preserve fish-style list elements losslessly."
    (let* ((env (nshell.domain.environment:make-environment))
           (updated
          (nshell.domain.environment:env-set-values
            env
            "FILES"
            '("hello world" "tail")
            nil)))
      (expect
        "hello world tail"
        :to-equal
        (nshell.domain.environment:env-get updated "FILES"))
      (expect
        '("hello world" "tail")
        :to-equal
        (nshell.domain.environment:env-get-values updated "FILES"))
      (expect (nshell.domain.environment:env-get-values env "FILES") :to-be-null)))
  (it
    "env-var-structure-is-not-public-api"
    "Internal variable records stay behind the environment aggregate API."
    (dolist (name
        '("ENV-VAR"
          "ENV-VAR-P"
          "MAKE-ENV-VAR"
          "ENV-VAR-NAME"
          "ENV-VAR-VALUE"
          "ENV-VAR-VALUES"
          "ENV-VAR-EXPORTED-P"
          "ENVIRONMENT-VARS"
          "ENV-ENTRY"))
      (multiple-value-bind (symbol status) (find-symbol name :nshell.domain.environment)
        (declare (ignore symbol))
        (expect (eq :external status) :to-be-falsy)))
    (dolist (symbol
        '(nshell.domain.environment::env-var-p
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
      (expect (fboundp symbol) :to-be-falsy)))
  (it
    "env-values-are-detached-from-input-and-output-lists"
    "Environment variables own their structured value lists."
    (let* ((values (list "hello world" "tail"))
           (env (nshell.domain.environment:make-environment))
           (updated (nshell.domain.environment:env-set-values env "FILES" values nil))
           (returned (nshell.domain.environment:env-get-values updated "FILES")))
      (setf (first values) "mutated input")
      (setf (first returned) "mutated output")
      (expect
        '("hello world" "tail")
        :to-equal
        (nshell.domain.environment:env-get-values updated "FILES"))
      (expect
        "hello world tail"
        :to-equal
        (nshell.domain.environment:env-get updated "FILES"))))
  (it
    "env-unset-removes-variable"
    "Unsetting a variable removes it from the environment."
    (let* ((env (nshell.domain.environment:make-environment))
           (with-var (nshell.domain.environment:env-set env "FOO" "bar" nil))
           (without-var (nshell.domain.environment:env-unset with-var "FOO")))
      (expect (nshell.domain.environment:env-get without-var "FOO") :to-be-null)))
  (it
    "env-export-marks-existing-variable"
    "Exporting a variable makes it appear in the exported environment list."
    (let* ((env (nshell.domain.environment:make-environment))
           (with-var (nshell.domain.environment:env-set env "FOO" "bar" nil))
           (exported (nshell.domain.environment:env-export with-var "FOO")))
      (expect
        "bar"
        :to-equal
        (env-entry-value (nshell.domain.environment:env-list exported) "FOO"))))
  (it
    "env-export-preserves-list-values"
    "Exporting a variable preserves its structured list values."
    (let* ((env (nshell.domain.environment:make-environment))
           (with-var
          (nshell.domain.environment:env-set-values
            env
            "FILES"
            '("hello world" "tail")
            nil))
           (exported (nshell.domain.environment:env-export with-var "FILES")))
      (expect
        '("hello world" "tail")
        :to-equal
        (nshell.domain.environment:env-get-values exported "FILES"))
      (expect
        "hello world tail"
        :to-equal
        (env-entry-value (nshell.domain.environment:env-list exported) "FILES"))))
  (it
    "env-list-only-returns-exported-vars"
    "Only exported variables are included in ENV-LIST."
    (let* ((env (nshell.domain.environment:make-environment))
           (env (nshell.domain.environment:env-set env "LOCAL" "no" nil))
           (env (nshell.domain.environment:env-set env "EXPORTED" "yes" t))
           (entries (nshell.domain.environment:env-list env)))
      (expect
        (find
          "LOCAL"
          entries
          :key
          #'nshell.domain.environment:env-entry-name
          :test
          #'string=)
        :to-be-null)
      (expect "yes" :to-equal (env-entry-value entries "EXPORTED"))))
  (it
    "env-bindings-returns-all-vars-sorted-with-export-state"
    "ENV-BINDINGS exposes local and exported variables for shell-local display."
    (let* ((env (nshell.domain.environment:make-environment))
           (env (nshell.domain.environment:env-set env "ZED" "last" nil))
           (env (nshell.domain.environment:env-set env "ALPHA" "first" t))
           (bindings (nshell.domain.environment:env-bindings env)))
      (expect
        '("ALPHA" "ZED")
        :to-equal
        (mapcar #'nshell.domain.environment:env-binding-name bindings))
      (expect
        '("first")
        :to-equal
        (nshell.domain.environment:env-binding-values (first bindings)))
      (expect
        "first"
        :to-equal
        (nshell.domain.environment:env-binding-value (first bindings)))
      (expect
        (nshell.domain.environment:env-binding-exported-p (first bindings))
        :to-be-truthy)
      (expect
        (nshell.domain.environment:env-binding-exported-p (second bindings))
        :to-be-falsy)))
  (it
    "env-binding-values-are-detached-projections"
    "Environment binding projections cannot mutate aggregate state."
    (let* ((env (nshell.domain.environment:make-environment))
           (env
          (nshell.domain.environment:env-set-values
            env
            "FILES"
            '("hello world" "tail")
            nil))
           (binding (first (nshell.domain.environment:env-bindings env)))
           (values (nshell.domain.environment:env-binding-values binding)))
      (setf (first values) "mutated projection")
      (expect
        '("hello world" "tail")
        :to-equal
        (nshell.domain.environment:env-binding-values binding))
      (expect
        '("hello world" "tail")
        :to-equal
        (nshell.domain.environment:env-get-values env "FILES"))))
  (it
    "env-assign-default-preserves-export-state"
    "Parameter default assignment updates the aggregate without exposing internals."
    (let* ((env (nshell.domain.environment:make-environment))
           (env (nshell.domain.environment:env-set env "EMPTY" "" t)))
      (expect (nshell.domain.environment:env-defined-p env "EMPTY") :to-be-truthy)
      (expect (nshell.domain.environment:env-exported-p env "EMPTY") :to-be-truthy)
      (expect
        "filled"
        :to-equal
        (nshell.domain.environment:env-assign-default! env "EMPTY" "filled"))
      (expect "filled" :to-equal (nshell.domain.environment:env-get env "EMPTY"))
      (expect (nshell.domain.environment:env-exported-p env "EMPTY") :to-be-truthy)))
  (it
    "default-environment-has-exported-fallback-values"
    "The default environment provides exported fallback values for core variables."
    (let ((env (nshell.domain.environment:make-default-environment)))
      (dolist (expected
               '(("HOME" "/")
                 ("PATH" "/bin:/usr/bin")
                 ("USER" "nobody")
                 ("PWD" "/")
                 ("SHELL" "/bin/sh")
                 ("TERM" "dumb")))
        (destructuring-bind (name value) expected
          (expect value :to-equal (nshell.domain.environment:env-get env name))
          (expect (nshell.domain.environment:env-exported-p env name) :to-be-truthy)))))
  (property
    "pbt-env-set-then-get-round-trips"
    "env-get returns exactly the scalar value env-set stored."
    ((name
        (gen-shell-variable-name :min-length 1 :max-length 10)
        #'shrink-shell-word)
      (value (gen-shell-word :min-length 1 :max-length 12) #'shrink-shell-word))
    (string=
      value
      (nshell.domain.environment:env-get
        (nshell.domain.environment:env-set
          (nshell.domain.environment:make-environment)
          name
          value
          nil)
        name)))
  (property
    "pbt-env-unset-removes-the-binding"
    "After env-unset the name is no longer defined."
    ((name
        (gen-shell-variable-name :min-length 1 :max-length 10)
        #'shrink-shell-word)
      (value (gen-shell-word :min-length 1 :max-length 12) #'shrink-shell-word))
    (not
      (nshell.domain.environment:env-defined-p
        (nshell.domain.environment:env-unset
          (nshell.domain.environment:env-set
            (nshell.domain.environment:make-environment)
            name
            value
            nil)
          name)
        name)))
  (it
    "pbt-env-set-exported-marks-exported"
    "env-set with exported=t makes the binding report as exported."
    (check-property
      (:trials 50)
      ((name
          (gen-shell-variable-name :min-length 1 :max-length 10)
          #'shrink-shell-word)
        (value (gen-shell-word :min-length 1 :max-length 12) #'shrink-shell-word))
      (nshell.domain.environment:env-exported-p
        (nshell.domain.environment:env-set
          (nshell.domain.environment:make-environment)
          name
          value
          t)
        name))))

(describe
  "environment-os-injection-tests"
  (it
    "bulk-injection-preserves-order-values-and-base-environment"
    "OS entries are applied once in input order without mutating the base environment."
    (let* ((base
          (nshell.domain.environment:env-set
            (nshell.domain.environment:env-set
              (nshell.domain.environment:make-environment)
              "BASE"
              "local"
              nil)
            "PWD"
            "/base"
            nil))
           (result
          (nshell.domain.environment::%inject-os-environment-entries
            base
            (quote
              ("BASE=new" "EMPTY=" "EQUAL=a=b" "=bad" "MALFORMED" "DUP=first" "DUP=last"))
            (lambda ()
              #P"/tmp/nshell-bulk/"))))
      (expect "local" :to-equal (nshell.domain.environment:env-get base "BASE"))
      (expect (nshell.domain.environment:env-exported-p base "BASE") :to-be-falsy)
      (expect "/base" :to-equal (nshell.domain.environment:env-get base "PWD"))
      (expect "new" :to-equal (nshell.domain.environment:env-get result "BASE"))
      (expect (nshell.domain.environment:env-exported-p result "BASE") :to-be-truthy)
      (expect "" :to-equal (nshell.domain.environment:env-get result "EMPTY"))
      (expect "a=b" :to-equal (nshell.domain.environment:env-get result "EQUAL"))
      (expect "last" :to-equal (nshell.domain.environment:env-get result "DUP"))
      (expect (nshell.domain.environment:env-defined-p result "") :to-be-falsy)
      (expect
        (nshell.domain.environment:env-defined-p result "MALFORMED")
        :to-be-falsy)
      (expect
        "/tmp/nshell-bulk/"
        :to-equal
        (nshell.domain.environment:env-get result "PWD"))))
  (it
    "bulk-injection-falls-back-to-imported-pwd"
    "A getcwd failure retains the last imported PWD value."
    (let* ((base
          (nshell.domain.environment:env-set
            (nshell.domain.environment:make-environment)
            "PWD"
            "/base"
            nil))
           (result
          (nshell.domain.environment::%inject-os-environment-entries
            base
            (quote ("PWD=/first" "PWD=/imported"))
            (lambda ()
              (error "getcwd failed")))))
      (expect "/imported" :to-equal (nshell.domain.environment:env-get result "PWD"))
      (expect (nshell.domain.environment:env-exported-p result "PWD") :to-be-truthy)
      (expect "/base" :to-equal (nshell.domain.environment:env-get base "PWD")))))
