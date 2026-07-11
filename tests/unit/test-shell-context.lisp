(in-package #:nshell/test)

(def-suite shell-context-tests
  :description "Application shell context unit tests"
  :in nshell-tests)

(in-suite shell-context-tests)

(test shell-context-constructs-with-all-dependencies
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
    (is (nshell.application:shell-context-p context))
    (is (nshell.domain.history:command-history-p
         (nshell.application:shell-context-history context)))
    (is (nshell.domain.configuration:config-p
         (nshell.application:shell-context-config context)))
    (is (not (null (nshell.application:shell-context-knowledge-base context))))
    (is (nshell.domain.environment:environment-p
         (nshell.application:shell-context-environment context)))
    (is (not (null (nshell.application:shell-context-dispatcher context))))
    (is (not (null (nshell.application:shell-context-job-monitor context))))
    (is (hash-table-p (nshell.application:shell-context-alias-table context)))
    (is (hash-table-p (nshell.application:shell-context-abbreviation-table context)))
    (is (eq :cps (nshell.application:shell-context-execution-strategy context)))))

(test shell-context-construction-boundary-is-public-factory-only
  "The context can be built only through the public factory, not copied as a raw struct."
  (let ((context (make-test-shell-context :terminal-fns nil)))
    (is (nshell.application:shell-context-p context))
    (is (not (fboundp 'nshell.application::copy-shell-context)))
    (is (fboundp 'nshell.application::%allocate-shell-context))
    (multiple-value-bind (_ status)
        (find-symbol "%ALLOCATE-SHELL-CONTEXT" :nshell.application)
      (declare (ignore _))
      (is (not (eq :external status))))))

(test shell-context-factory-validates-composition-values
  "Invalid session composition is rejected before the context is allocated."
  (signals type-error
    (nshell.application:make-shell-context :execution-strategy :unsupported))
  (signals type-error
    (nshell.application:make-shell-context :terminal-rows 0))
  (signals type-error
    (nshell.application:make-shell-context :terminal-cols 0))
  (signals type-error
    (nshell.application:make-shell-context :alias-table nil))
  (signals type-error
    (nshell.application:make-shell-context :process-registry nil))
  (signals type-error
    (nshell.application:make-shell-context :filesystem-fns :not-a-plist)))

(test shell-context-process-registry-exposes-job-query-only
  "Process registry storage stays internal; callers query by job id."
  (let ((context (make-test-shell-context)))
    (nshell.application::%store-shell-process-registry-entry
     context 42 '(:left-process :right-process))
    (is (equal '(:left-process :right-process)
               (nshell.application:shell-context-job-processes context 42)))
    (is (null (nshell.application:shell-context-job-processes context 99)))
    (multiple-value-bind (_ status)
        (find-symbol "SHELL-CONTEXT-PROCESS-REGISTRY" :nshell.application)
      (declare (ignore _))
      (is (not (eq :external status))))
    (is (eq :external
            (nth-value 1
                       (find-symbol "SHELL-CONTEXT-JOB-PROCESSES"
                                    :nshell.application))))))

(test shell-context-supports-fake-adapters
  "Adapter plists can be replaced with test fakes."
  (let* ((context (make-test-shell-context))
         (filesystem-fns (nshell.application:shell-context-filesystem-fns context))
         (process-fns (nshell.application:shell-context-process-fns context))
         (terminal-fns (nshell.application:shell-context-terminal-fns context)))
    (is (equal '("a" "b") (funcall (getf filesystem-fns :list-dir) #p"/tmp/")))
    (is (eq :spawned (funcall (getf process-fns :spawn) "echo" '("ok"))))
    (multiple-value-bind (columns rows) (funcall (getf terminal-fns :get-size))
      (is (= 80 columns))
      (is (= 24 rows)))))
