(in-package #:nshell/test)

(describe "shell-context-tests"
  (it "shell-context-constructs-with-all-dependencies"
    "MAKE-SHELL-CONTEXT stores each public dependency behind the context boundary."
    (let ((context (make-test-shell-context
                    :filesystem-fns (list :list-dir (lambda (dir) (declare (ignore dir)) '("a" "b"))
                                          :stat (lambda (path) (declare (ignore path)) t)
                                          :cwd (lambda () #p"/tmp/")
                                          :chdir (lambda (path) (declare (ignore path)) t))
                    :process-fns (list :spawn (lambda (&rest args) (declare (ignore args)) :spawned)
                                       :wait (lambda (&rest args) (declare (ignore args)) :waited)
                                       :signal (lambda (&rest args) (declare (ignore args)) :signaled))
                    :terminal-fns (list :get-size (lambda () (values 80 24))
                                        :raw-mode (lambda () t)
                                        :restore-mode (lambda () t)))))
      (expect (nshell.application:shell-context-p context) :to-be-truthy)
      (expect (history-kit:history-p
           (nshell.application:shell-context-history context)) :to-be-truthy)
      (expect (nshell.domain.configuration:config-p
           (nshell.application:shell-context-config context)) :to-be-truthy)
      (expect (null (nshell.application:shell-context-knowledge-base context)) :to-be-falsy)
      (expect (nshell.domain.environment:environment-p
           (nshell.application:shell-context-environment context)) :to-be-truthy)
      (expect (null (nshell.application:shell-context-dispatcher context)) :to-be-falsy)
      (expect (null (nshell.application:shell-context-job-monitor context)) :to-be-falsy)
      (expect (hash-table-p (nshell.application:shell-context-alias-table context)) :to-be-truthy)
      (expect (hash-table-p (nshell.application:shell-context-abbreviation-table context)) :to-be-truthy)
      (expect :cps :to-be (nshell.application:shell-context-execution-strategy context))))

  (it "shell-context-construction-boundary-is-public-factory-only"
    "The context can be built only through the public factory, not copied as a raw struct."
    (let ((context (make-test-shell-context :terminal-fns nil)))
      (expect (nshell.application:shell-context-p context) :to-be-truthy)
      (expect (fboundp 'nshell.application::copy-shell-context) :to-be-falsy)
      (expect (fboundp 'nshell.application::%allocate-shell-context) :to-be-truthy)
      (multiple-value-bind (_ status)
          (find-symbol "%ALLOCATE-SHELL-CONTEXT" :nshell.application)
        (declare (ignore _))
        (expect (eq :external status) :to-be-falsy))))

  (it "shell-context-factory-validates-composition-values"
    "Invalid session composition is rejected before the context is allocated."
    (expect (lambda () (nshell.application:make-shell-context :execution-strategy :unsupported)) :to-throw 'type-error)
    (expect (lambda () (nshell.application:make-shell-context :terminal-rows 0)) :to-throw 'type-error)
    (expect (lambda () (nshell.application:make-shell-context :terminal-cols 0)) :to-throw 'type-error)
    (expect (lambda () (nshell.application:make-shell-context :alias-table nil)) :to-throw 'type-error)
    (expect (lambda () (nshell.application:make-shell-context :process-registry nil)) :to-throw 'type-error)
    (expect (lambda () (nshell.application:make-shell-context :filesystem-fns :not-a-plist)) :to-throw 'type-error))

  (it "shell-context-process-registry-exposes-job-query-only"
    "Process registry storage stays internal; callers query by job id."
    (let ((context (make-test-shell-context)))
      (nshell.application::%store-shell-process-registry-entry
       context 42 '(:left-process :right-process))
      (expect '(:left-process :right-process) :to-equal (nshell.application:shell-context-job-processes context 42))
      (expect (nshell.application:shell-context-job-processes context 99) :to-be-null)
      (multiple-value-bind (_ status)
          (find-symbol "SHELL-CONTEXT-PROCESS-REGISTRY" :nshell.application)
        (declare (ignore _))
        (expect (eq :external status) :to-be-falsy))
      (expect :external :to-be (nth-value 1
                         (find-symbol "SHELL-CONTEXT-JOB-PROCESSES"
                                      :nshell.application)))))

  (it "shell-context-supports-fake-adapters"
    "Adapter plists can be replaced with test fakes."
    (let* ((context (make-test-shell-context))
           (filesystem-fns (nshell.application:shell-context-filesystem-fns context))
           (process-fns (nshell.application:shell-context-process-fns context))
           (terminal-fns (nshell.application:shell-context-terminal-fns context)))
      (expect '("a" "b") :to-equal (funcall (getf filesystem-fns :list-dir) #p"/tmp/"))
      (expect :spawned :to-be (funcall (getf process-fns :spawn) "echo" '("ok")))
      (multiple-value-bind (columns rows) (funcall (getf terminal-fns :get-size))
        (expect 80 :to-equal columns)
        (expect 24 :to-equal rows)))))
