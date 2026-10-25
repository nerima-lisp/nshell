(in-package #:nshell/test)

(describe "reader-preflight-and-sequence-control"
  (it "returns the process-substitution stages in pipeline order"
    (let* ((first (nshell.domain.parsing:make-command-node "first" nil))
           (second (nshell.domain.parsing:make-command-node "second" nil))
           (pipeline
             (nshell.domain.parsing:make-pipeline-node (list first second)))
           (entry
             (nshell.domain.parsing:make-ast-redirect-entry
              :process-substitution-input
              nil
              (nshell.domain.parsing:make-redirect-procsub-target
               :input pipeline)
              '(2 15)
              0))
           (commands
             (nshell.application::%preflight-reader-process-substitution-entry
              entry)))
      (expect 2 :to-equal (length commands))
      (expect first :to-be (first commands))
      (expect second :to-be (second commands))))
  (it "evaluation plans retain process-substitution command and pipeline forms"
    (let* ((command-form (nshell.domain.parsing:make-command-node "producer" nil))
           (first-stage (nshell.domain.parsing:make-command-node "first" nil))
           (second-stage (nshell.domain.parsing:make-command-node "second" nil))
           (pipeline-form
             (nshell.domain.parsing:make-pipeline-node
              (list first-stage second-stage)))
           (command-entry
             (nshell.domain.parsing:make-ast-redirect-entry
              :process-substitution-input
              nil
              (nshell.domain.parsing:make-redirect-procsub-target
               :input command-form)
              (list 1 2)
              0))
           (pipeline-entry
             (nshell.domain.parsing:make-ast-redirect-entry
              :process-substitution-input
              nil
              (nshell.domain.parsing:make-redirect-procsub-target
               :input pipeline-form)
              (list 3 4)
              0))
           (evaluated
             (nshell.application::%reader-evaluate-process-substitutions
              nil
              (list (list 0 command-entry (list command-form))
                    (list 1 pipeline-entry (list first-stage second-stage)))
              (lambda (context command)
                (declare (ignore context))
                command))))
      (expect command-form :to-be (third (first evaluated)))
      (expect command-form :to-be (first (fourth (first evaluated))))
      (expect pipeline-form :to-be (third (second evaluated)))
      (expect first-stage :to-be (first (fourth (second evaluated))))
      (expect second-stage :to-be (second (fourth (second evaluated))))))
  (it "preflight reports direction mismatches for unvalidated redirect entries"
    (let* ((form (nshell.domain.parsing:make-command-node "producer" nil))
           (entry
             (nshell.domain.parsing::%make-ast-redirect-entry
              :kind :process-substitution-input
              :file-descriptor nil
              :target
              (nshell.domain.parsing:make-redirect-procsub-target
               :output form)
              :source-span (list 4 19)
              :source-order 0))
           (condition nil))
      (handler-case
          (nshell.application::%preflight-reader-process-substitution-entry
           entry)
        (nshell.application:command-execution-plan-error (caught)
          (setf condition caught)))
      (expect (list 4 19) :to-equal
              (nshell.application:command-execution-plan-error-source-span
               condition))
      (expect :preflight :to-be
              (nshell.application:command-execution-plan-error-operation
               condition))))
  (it "rejects nested substitutions at the outer substitution span"
    (let* ((nested-entry
             (nshell.domain.parsing:make-ast-redirect-entry
              :process-substitution-input
              nil
              (nshell.domain.parsing:make-redirect-procsub-target
               :input
               (nshell.domain.parsing:make-command-node "nested" nil))
              '(30 40)
              0))
           (inner-command
             (nshell.domain.parsing:make-command-node
              "inner" nil nil nil nil (list nested-entry)))
           (outer-entry
             (nshell.domain.parsing:make-ast-redirect-entry
              :input-file
              0
              (nshell.domain.parsing:make-redirect-procsub-target
               :input inner-command)
              '(8 27)
              0))
           (condition nil))
      (handler-case
          (nshell.application::%preflight-reader-process-substitution-entry
           outer-entry)
        (nshell.application:command-execution-plan-error (caught)
          (setf condition caught)))
      (expect '(8 27) :to-equal
              (nshell.application:command-execution-plan-error-source-span
               condition))
      (expect :preflight :to-be
              (nshell.application:command-execution-plan-error-operation
               condition))))
  (it "reader-sequence-short-circuits-and-records-final-status"
    (let* ((context (nshell.application:make-shell-context :running t))
           (executor-symbol
             (find-symbol "EXECUTE-READER-AST-IN-CONTEXT"
                          "NSHELL.APPLICATION"))
           (original-executor (symbol-function executor-symbol))
           (last-result
             (nshell.application:make-pipeline-execution-result
              7 '(7) '(nil)))
           (calls nil)
           (sequence
             (nshell.domain.parsing:make-sequence-node
              (list
               (nshell.domain.parsing:make-command-node "false" nil)
               (nshell.domain.parsing:make-command-node "skipped" nil)
               (nshell.domain.parsing:make-command-node "condition" nil)
               (nshell.domain.parsing:make-command-node "last" nil))
              (list :and :or :and))))
      (unwind-protect
           (progn
             (setf (symbol-function executor-symbol)
                   (lambda (ignored-context command ignored-stage-evaluator)
                     (declare (ignore ignored-context ignored-stage-evaluator))
                     (let ((name
                             (nshell.domain.parsing:command-node-command
                              command)))
                       (push
                        (list name
                              nshell.application::*command-test-position-p*)
                        calls)
                       (cond
                         ((string= name "false")
                          (values nil 1
                                  (nshell.application:make-pipeline-execution-result
                                   1 '(1) '(nil))))
                         ((string= name "condition")
                          (values nil 0
                                  (nshell.application:make-pipeline-execution-result
                                   0 '(0) '(nil))))
                         ((string= name "last")
                          (values name 7 last-result))
                         (t (error "Unexpected command ~A" name))))))
             (multiple-value-bind (value status result)
                 (nshell.application::%execute-reader-sequence-node-in-context
                  context sequence nil)
               (expect
                (list (list "false" t)
                      (list "condition" t)
                      (list "last" nil))
                :to-equal
                (nreverse calls))
               (expect "last" :to-equal value)
               (expect 7 :to-equal status)
               (expect last-result :to-be result)
               (expect
                7
                :to-equal
                (nshell.application:shell-context-last-exit-code context)))
             (dolist (stop-kind (list :loop-control :shell-shutdown))
               (let* ((stop-context
                        (nshell.application:make-shell-context :running t))
                      (stop-calls nil)
                      (stop-sequence
                        (nshell.domain.parsing:make-sequence-node
                         (list
                          (nshell.domain.parsing:make-command-node "stop" nil)
                          (nshell.domain.parsing:make-command-node "after" nil))
                         (list :semi))))
                 (let ((nshell.application::*loop-control-signal* nil))
                   (setf (symbol-function executor-symbol)
                         (lambda (ignored-context command ignored-stage-evaluator)
                           (declare (ignore ignored-context ignored-stage-evaluator))
                           (let ((name
                                   (nshell.domain.parsing:command-node-command
                                    command)))
                             (push name stop-calls)
                             (when (string= name "stop")
                               (if (eq stop-kind :loop-control)
                                   (setf nshell.application::*loop-control-signal*
                                         (cons :break 1))
                                   (setf
                                    (nshell.application:shell-context-running
                                     stop-context)
                                    nil)))
                             (values
                              nil 0
                              (nshell.application:make-pipeline-execution-result
                               0 '(0) '(nil))))))
                   (nshell.application::%execute-reader-sequence-node-in-context
                    stop-context stop-sequence nil)
                   (expect '("stop") :to-equal (nreverse stop-calls))))))
        (setf (symbol-function executor-symbol) original-executor)))))

(describe "reader-process-substitution-fd-flags"
  (it "sets close-on-exec on both pipeline endpoints"
    (multiple-value-bind (read-fd write-fd)
        (nshell.infrastructure.acl::make-reader-pipeline-pipe)
      (unwind-protect
           (dolist (fd (list read-fd write-fd))
             (expect t :to-be
                     (logtest
                      nshell.infrastructure.acl::+spawn-fd-cloexec+
                      (sb-posix:fcntl
                       fd nshell.infrastructure.acl::+spawn-f-getfd+))))
        (nshell.infrastructure.acl::close-reader-descriptor read-fd)
        (nshell.infrastructure.acl::close-reader-descriptor write-fd))))
  (it "clears close-on-exec only on the parent endpoint"
    (dolist (direction (list :input :output))
      (let ((resource
              (nshell.infrastructure.acl::make-reader-process-substitution-resource
               direction)))
        (unwind-protect
             (let ((parent-fd
                     (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
                      resource))
                   (inner-fd
                     (nshell.infrastructure.acl::reader-process-substitution-resource-inner-fd
                      resource)))
               (expect nil :to-be
                       (logtest
                        nshell.infrastructure.acl::+spawn-fd-cloexec+
                        (sb-posix:fcntl
                         parent-fd nshell.infrastructure.acl::+spawn-f-getfd+)))
               (expect t :to-be
                       (logtest
                        nshell.infrastructure.acl::+spawn-fd-cloexec+
                        (sb-posix:fcntl
                         inner-fd nshell.infrastructure.acl::+spawn-f-getfd+))))
          (nshell.infrastructure.acl::close-reader-process-substitution-resource
           resource)))))
  (it "limits inherited process-substitution descriptors to their owning pipeline stage"
    (let* ((state (nshell.application::%make-reader-execution-state))
           (resource
             (nshell.infrastructure.acl::%make-reader-process-substitution-resource
              :input 91 92))
           (substitution
             (nshell.application::%make-reader-process-substitution
              nil resource nil 1))
           (bindings
             (list (cons (make-hash-table :test #'eql) nil)
                   (cons (make-hash-table :test #'eql) nil))))
      (setf (nshell.application::%reader-execution-state-process-substitutions
             state)
            (list substitution))
      (let ((outer-stage-io
              (nshell.application::%reader-stage-io-list bindings state))
            (body-stage-io
              (nshell.application::%reader-stage-io-list bindings state nil)))
        (expect nil :to-equal
                (nshell.application:pipeline-stage-io-preserved-descriptors
                 (first outer-stage-io)))
        (expect '(91) :to-equal
                (nshell.application:pipeline-stage-io-preserved-descriptors
                 (second outer-stage-io)))
        (expect '(91) :to-equal
                (nshell.application:pipeline-stage-io-transient-descriptors
                 (second outer-stage-io)))
        (expect nil :to-equal
                (nshell.application:pipeline-stage-io-preserved-descriptors
                 (first body-stage-io)))
        (expect nil :to-equal
                (nshell.application:pipeline-stage-io-preserved-descriptors
                 (second body-stage-io))))))
)

(describe "reader-allocation-error-wrapping"
  (it "wraps allocation errors with a source span and allocate operation"
    (let ((caught nil))
      (handler-case
          (nshell.application::%reader-allocate-with-plan-error
           '(12 19)
           (lambda () (error "injected allocation failure")))
        (nshell.application:command-execution-plan-error (condition)
          (setf caught condition)))
      (expect '(12 19) :to-equal
              (nshell.application:command-execution-plan-error-source-span
               caught))
      (expect :allocate :to-be
              (nshell.application:command-execution-plan-error-operation
               caught))))
  (it "re-signals existing plan and L06 conditions unchanged"
    (let* ((span '(4 8))
           (plan-error
             (make-condition
              'nshell.application:command-execution-plan-error
              :source-span span
              :operation :preflight
              :cause (make-condition 'simple-error
                                     :format-control "existing"
                                     :format-arguments nil)))
           (conversion-error
             (make-condition
              'nshell.application:command-argument-type-error
              :value nil
              :source-span span))
           (caught-plan-error nil)
           (caught-conversion-error nil))
      (handler-case
          (nshell.application::%reader-allocate-with-plan-error
           span (lambda () (error plan-error)))
        (nshell.application:command-execution-plan-error (condition)
          (setf caught-plan-error condition)))
      (handler-case
          (nshell.application::%reader-allocate-with-plan-error
           span (lambda () (error conversion-error)))
        (nshell.application:command-argument-type-error (condition)
          (setf caught-conversion-error condition)))
      (expect plan-error :to-be caught-plan-error)
      (expect conversion-error :to-be caught-conversion-error))))
