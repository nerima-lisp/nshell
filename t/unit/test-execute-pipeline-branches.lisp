(in-package #:nshell/test)

+(describe "execute-pipeline-branch-tests"
  (it "continues-stopped-external-process-and-ignores-signal-errors"
    "A stopped process group receives SIGCONT while delivery failures remain best effort."
    (let ((calls nil))
      (with-temporary-function
          ((quote nshell.infrastructure.acl:kill-process)
           (lambda (pid signal)
             (push (list pid signal) calls)
             (error "signal delivery failure")))
        (expect :continue-wait :to-be
                (nshell.application::%continue-stopped-external-process 4321)))
      (expect '((-4321 :sigcont)) :to-equal calls)))
  (it "process-substitution-spec-and-direction-are-classified"
    (expect (nshell.application::%process-substitution-spec-p nil) :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "") :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "<(") :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "<(printf") :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "<(printf)") :to-be-truthy)
    (expect (nshell.application::%process-substitution-spec-p ">(printf)") :to-be-truthy)
    (expect (nshell.application::%process-substitution-spec-p "x(printf)") :to-be-falsy)
    (expect :input :to-be (nshell.application::%process-substitution-direction "<(printf)"))
    (expect :output :to-be (nshell.application::%process-substitution-direction ">(printf)")))
  (it "process-substitution-error-and-inner-commands-are-pure"
    (expect (format nil "nshell: process substitution: ~a~%" "failed") :to-equal (nshell.application::%process-substitution-error "failed"))
    (with-complete-ast (command "echo hi")
      (expect (list command)
              :to-equal
              (nshell.application::%process-substitution-inner-commands command)))
    (with-complete-ast (pipeline "echo hi | cat")
      (expect 2
              :to-equal
              (length (nshell.application::%process-substitution-inner-commands pipeline))))
    (expect (nshell.application::%process-substitution-inner-commands nil) :to-be-null))
  (it "process-substitution-resource-cleanup-is-best-effort"
    (let ((released nil))
      (with-temporary-functions
          (((quote nshell.infrastructure.acl:release-process-substitution-fd)
            (lambda (resource)
              (push resource released)
              (when (eq resource :bad)
                (error "release failure")))))
        (nshell.application::%release-process-substitution-resources
         (list :first :bad :last)))
      (expect (list :last :bad :first) :to-equal released)))
  (it "process-substitution-finish-and-abort-release-all-resources"
    (let ((waited nil)
          (released nil)
          (closed nil))
      (with-temporary-functions
          (((quote nshell.infrastructure.acl:wait-process-substitution)
            (lambda (resource)
              (push resource waited)
              (when (eq resource :bad)
                (error "wait failure"))))
           ((quote nshell.infrastructure.acl:release-process-substitution-fd)
            (lambda (resource)
              (push resource released)))
           ((quote nshell.infrastructure.acl:close-process-substitution)
            (lambda (resource)
              (push resource closed))))
        (nshell.application::%finish-process-substitution-resources (list :ok :bad))
        (nshell.application::%abort-process-substitution-resources (list :left :right)))
      (expect (list :bad :ok) :to-equal waited)
      (expect (list :bad :ok) :to-equal released)
      (expect (list :right :left) :to-equal closed)))
  (it "process-substitution-resource-fds-project-in-order"
    (with-temporary-function
        ((quote nshell.infrastructure.acl:process-substitution-resource-fd)
         (lambda (resource)
           (getf resource :fd)))
      (expect (list 3 4)
              :to-equal
              (nshell.application::%process-substitution-resource-fds
               (list (list :fd 3) (list :fd 4))))))
  (it "source-pipeline-exit-status-honors-pipefail"
    (expect 2 :to-equal (nshell.application::%source-pipeline-exit-status (list 0 2) nil))
    (expect 2 :to-equal (nshell.application::%source-pipeline-exit-status (list 0 2 0) t))
    (expect 0 :to-equal (nshell.application::%source-pipeline-exit-status (list 0 0) t))
    (expect 0 :to-equal (nshell.application::%source-pipeline-exit-status nil nil)))
  (it "records-pipeline-statuses-as-normalized-environment-values"
    (let ((context (make-test-builtins-context)))
      (expect (list 0) :to-equal
              (nshell.application::%record-pipeline-statuses context nil))
      (expect (list "0") :to-equal
              (nshell.domain.environment:env-get-values
               (nshell.application:shell-context-environment context)
               "pipestatus"))
      (expect (list 2 nil 7) :to-equal
              (nshell.application::%record-pipeline-statuses context (list 2 nil 7)))
      (expect (list "2" "0" "7") :to-equal
              (nshell.domain.environment:env-get-values
               (nshell.application:shell-context-environment context)
               "pipestatus")))))

