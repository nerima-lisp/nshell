(in-package #:nshell/test)

(describe "shell-context-tests"
  (it "shell-context-constructs-with-session-state"
    "MAKE-SHELL-CONTEXT stores session state behind the application boundary."
    (let ((context (make-test-shell-context)))
      (expect (nshell.application:shell-context-p context) :to-be-truthy)
      (expect (history-kit:history-p
           (nshell.application:shell-context-history context)) :to-be-truthy)
      (expect (nshell.domain.configuration:config-p
           (nshell.application:shell-context-config context)) :to-be-truthy)
      (expect (nshell.domain.completion::knowledge-base-p
               (nshell.application:shell-context-knowledge-base context)) :to-be-truthy)
      (expect (nshell.domain.environment:environment-p
           (nshell.application:shell-context-environment context)) :to-be-truthy)
      (expect (nshell.domain.job-control:job-monitor-p
               (nshell.application:shell-context-job-monitor context)) :to-be-truthy)
      (expect (hash-table-p (nshell.application:shell-context-alias-table context)) :to-be-truthy)
      (expect (hash-table-p (nshell.application:shell-context-abbreviation-table context)) :to-be-truthy)
      (expect :cps :to-be (nshell.application:shell-context-execution-strategy context))))

  (it "shell-context-factory-provides-safe-defaults"
    "The public factory supplies valid session defaults."
    (let ((context (nshell.application:make-shell-context)))
      (expect :cps :to-be
              (nshell.application:shell-context-execution-strategy context))
      (expect (nshell.application:shell-context-pipefail-p context)
              :to-be-falsy)
      (expect (nshell.application:shell-context-running context)
              :to-be-falsy)
      (expect 0 :to-equal
              (nshell.application:shell-context-last-exit-code context))
      (expect 24 :to-equal
              (nshell.application:shell-context-terminal-rows context))
      (expect 80 :to-equal
              (nshell.application:shell-context-terminal-cols context))
      (expect (hash-table-p
               (nshell.application:shell-context-alias-table context))
              :to-be-truthy)
      (expect (hash-table-p
               (nshell.application:shell-context-abbreviation-table context))
              :to-be-truthy)
      (expect (hash-table-p
               (nshell.application::shell-context-process-registry context))
              :to-be-truthy)))

  (it "shell-context-construction-boundary-is-public-factory-only"
    "The context can be built only through the public factory, not copied as a raw struct."
    (let ((context (make-test-shell-context)))
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
    (expect (lambda () (nshell.application:make-shell-context :pipefail-p :yes)) :to-throw 'type-error)
    (expect (lambda () (nshell.application:make-shell-context :running :yes)) :to-throw 'type-error)
    (expect (lambda () (nshell.application:make-shell-context :last-exit-code "0")) :to-throw 'type-error))

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

  (it "shell-context-manages-functions"
  "Runtime function metadata stays behind the context boundary."
  (let ((context (make-test-shell-context)))
    (nshell.application::%store-shell-function-definition
     context "demo" (list "echo one") "demo.ns")
    (expect (list "echo one")
            :to-equal
            (gethash "demo" (nshell.application:shell-context-function-table context)))
    (expect "demo.ns"
            :to-equal
            (gethash "demo" (nshell.application:shell-context-function-source-table context)))
    (nshell.application::%store-shell-function-definition
     context "demo" (list "echo two") nil)
    (expect (list "echo two")
            :to-equal
            (gethash "demo" (nshell.application:shell-context-function-table context)))
    (expect (gethash "demo" (nshell.application:shell-context-function-source-table context))
            :to-be-null)
    (nshell.application::%remove-shell-function-definition context "demo")
    (expect (gethash "demo" (nshell.application:shell-context-function-table context))
            :to-be-null)
    (setf (nshell.application:shell-context-running context) t)
    (expect context :to-be (nshell.application::%stop-shell-context context))
    (expect (nshell.application:shell-context-running context) :to-be-falsy))))
