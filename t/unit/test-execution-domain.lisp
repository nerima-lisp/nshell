(in-package #:nshell/test)

(defun execution-domain-external-symbol-p (name)
  (eq :external
      (nth-value 1 (find-symbol name '#:nshell.domain.execution))))

;;; Command tests
(describe "execution-domain-tests"
  (it "command-value-boundary-is-public-api-only"
    "Command exposes constructor and projections, not raw structure internals."
    (expect (execution-domain-external-symbol-p "MAKE-COMMAND") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "COMMAND-NAME") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "COMMAND-ARGS") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "COMMAND-TO-LIST") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "COMMAND-NAME-STR") :to-be-falsy)
    (expect (execution-domain-external-symbol-p "COMMAND-ARGS-LIST") :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%make-command) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::copy-command) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::command-p) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%allocate-command) :to-be-truthy)
    (expect (fboundp 'nshell.domain.execution::%make-command-with-invariants) :to-be-truthy))

  (it "command-creation"
    "Command can be created with name and optional args"
    (let ((cmd (nshell.domain.execution:make-command "ls" '("-l" "-a"))))
      (expect "ls" :to-equal (nshell.domain.execution:command-name cmd))
      (expect '("-l" "-a") :to-equal (nshell.domain.execution:command-args cmd))))

  (it "command-without-args"
    "Command can be created without arguments"
    (let ((cmd (nshell.domain.execution:make-command "pwd")))
      (expect "pwd" :to-equal (nshell.domain.execution:command-name cmd))
      (expect (nshell.domain.execution:command-args cmd) :to-be-null)))

  (it "command-to-list"
    "Command converts to flat list of strings"
    (let ((cmd (nshell.domain.execution:make-command "echo" '("hello" "world"))))
      (expect '("echo" "hello" "world") :to-equal (nshell.domain.execution:command-to-list cmd))))

  (it "command-rejects-invalid-values-at-domain-boundary"
    "Command construction validates values before allocating the structure."
    (expect (lambda () (nshell.domain.execution:make-command :echo '("hello"))) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.execution:make-command "echo" "hello")) :to-throw 'type-error))

  (it "command-projections-are-domain-owned"
    "Command name and argument projections cannot mutate command state."
    (let* ((args (list "hello" "world"))
           (cmd (nshell.domain.execution:make-command "echo" args))
           (name-view (nshell.domain.execution:command-name cmd))
           (args-view (nshell.domain.execution:command-args cmd))
           (list-view (nshell.domain.execution:command-to-list cmd)))
      (setf (first args) "caller-mutated")
      (setf (char name-view 0) #\x)
      (setf (first args-view) "projection-mutated")
      (setf (second list-view) "list-mutated")
      (expect "echo" :to-equal (nshell.domain.execution:command-name cmd))
      (expect '("hello" "world") :to-equal (nshell.domain.execution:command-args cmd))
      (expect '("echo" "hello" "world") :to-equal (nshell.domain.execution:command-to-list cmd))))

  ;;; Pipeline tests
  (it "pipeline-value-boundary-is-public-api-only"
    "Pipeline exposes construction and projections without raw allocation helpers."
    (expect (execution-domain-external-symbol-p "MAKE-PIPELINE") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-P") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-COMMANDS") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-LENGTH") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-EMPTY-P") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-SINGLE-COMMAND-P") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-COMMANDS-LIST") :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%make-pipeline) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::copy-pipeline) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%allocate-pipeline) :to-be-truthy)
    (expect (fboundp 'nshell.domain.execution::%make-pipeline-with-invariants) :to-be-truthy))

  (it "pipeline-plan-value-boundary-is-public-api-only"
    "Pipeline plans expose behavior queries, not stage/config allocation details."
    (expect (execution-domain-external-symbol-p "MAKE-PIPELINE-PLAN") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-PLAN-P") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-PLAN-STAGE-COUNT") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-PLAN-COMMANDS") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-PLAN-STAGE-PIPED-INPUT-P") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-PLAN-STAGE-PIPED-OUTPUT-P") :to-be-truthy)
    (expect (execution-domain-external-symbol-p "PIPELINE-PLAN-STAGES") :to-be-falsy)
    (expect (execution-domain-external-symbol-p "PIPELINE-STAGE-STAGE-COMMAND") :to-be-falsy)
    (expect (execution-domain-external-symbol-p "PIPELINE-STAGE-PIPE-CONFIG") :to-be-falsy)
    (expect (execution-domain-external-symbol-p "PIPE-CONFIG-STDIN") :to-be-falsy)
    (expect (execution-domain-external-symbol-p "PIPE-CONFIG-STDOUT") :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%make-pipeline-plan) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%make-pipe-config) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%make-pipeline-stage) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::copy-pipeline-plan) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::copy-pipe-config) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::copy-pipeline-stage) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::pipe-config-p) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::pipeline-stage-p) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::%allocate-pipeline-plan) :to-be-truthy)
    (expect (fboundp 'nshell.domain.execution::%allocate-pipe-config) :to-be-truthy)
    (expect (fboundp 'nshell.domain.execution::%allocate-pipeline-stage) :to-be-truthy)
    (expect (fboundp 'nshell.domain.execution::%make-pipeline-plan-with-invariants) :to-be-truthy)
    (expect (fboundp 'nshell.domain.execution::%make-pipe-config-with-invariants) :to-be-truthy)
    (expect (fboundp 'nshell.domain.execution::%make-pipeline-stage-with-invariants) :to-be-truthy))

  (it "pipeline-creation"
    "Pipeline can be created with multiple commands"
    (let* ((cmd1 (nshell.domain.execution:make-command "ls"))
           (cmd2 (nshell.domain.execution:make-command "grep" '("foo")))
           (pipe (nshell.domain.execution:make-pipeline cmd1 cmd2)))
      (expect 2 :to-equal (nshell.domain.execution:pipeline-length pipe))
      (expect (nshell.domain.execution:pipeline-single-command-p pipe) :to-be-falsy)
      (expect (nshell.domain.execution:pipeline-empty-p pipe) :to-be-falsy)))

  (it "pipeline-single-command"
    "Pipeline with one command reports as single"
    (let* ((cmd (nshell.domain.execution:make-command "ls"))
           (pipe (nshell.domain.execution:make-pipeline cmd)))
      (expect (nshell.domain.execution:pipeline-single-command-p pipe) :to-be-truthy)))

  (it "pipeline-empty"
    "Empty pipeline reports correctly"
    (let ((pipe (nshell.domain.execution:make-pipeline)))
      (expect (nshell.domain.execution:pipeline-empty-p pipe) :to-be-truthy)
      (expect 0 :to-equal (nshell.domain.execution:pipeline-length pipe))))

  ;;; Job tests
  (it "job-creation"
    "Job created with initial :created state"
    (let* ((cmd (nshell.domain.execution:make-command "sleep" '("10")))
           (pipe (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 1 pipe)))
      (expect 1 :to-equal (nshell.domain.execution:job-id job))
      (expect :created :to-be (nshell.domain.execution:job-state job))
      (expect (zerop (nshell.domain.execution:job-pgid job)) :to-be-truthy)))

  (it "job-creation-validates-aggregate-boundary"
    "Job aggregate construction validates identity and pipeline value."
    (let* ((cmd (nshell.domain.execution:make-command "sleep" '("10")))
           (pipe (nshell.domain.execution:make-pipeline cmd)))
      (expect (nshell.domain.execution:make-job 1 pipe) :to-be-truthy)
      (expect (lambda () (nshell.domain.execution:make-job "1" pipe)) :to-throw 'error)
      (expect (lambda () (nshell.domain.execution:make-job 1 :not-a-pipeline)) :to-throw 'error)))

  (it "job-struct-allocation-is-internal"
    "Callers cannot bypass job aggregate construction via exported struct helpers."
    (expect (fboundp 'nshell.domain.execution::%make-job) :to-be-falsy)
    (expect (fboundp 'nshell.domain.execution::copy-job) :to-be-falsy)
    (expect :internal :to-be (nth-value 1
                       (find-symbol "JOB-STATE-KW" "NSHELL.DOMAIN.EXECUTION"))))

  (it "job-state-transitions"
    "Job state transitions are owned by the job aggregate."
    (let* ((cmd (nshell.domain.execution:make-command "ls"))
           (pipe (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 42 pipe)))
      (nshell.domain.execution:job-state-transition job :running)
      (expect (nshell.domain.execution:job-running-p job) :to-be-truthy)
      (nshell.domain.execution:job-state-transition job :stopped)
      (expect (nshell.domain.execution:job-stopped-p job) :to-be-truthy)
      (nshell.domain.execution:job-state-transition job :completed)
      (expect t :to-be (nshell.domain.execution:job-completed-p job))))

  (it "terminal-job-state-cannot-return-to-active"
    "Completed jobs are terminal and cannot be restarted by callers."
    (let* ((cmd (nshell.domain.execution:make-command "ls"))
           (pipe (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 42 pipe)))
      (nshell.domain.execution:job-state-transition job :running)
      (nshell.domain.execution:job-state-transition job :completed)
      (expect (lambda () (nshell.domain.execution:job-state-transition job :running)) :to-throw 'error)
      (expect :completed :to-be (nshell.domain.execution:job-state job))))

  (it "job-register-background-processes-initializes-runtime-metadata"
    "Job aggregate owns process metadata initialization."
    (let ((job (make-test-job 0 "left")))
      (expect job :to-be (nshell.domain.execution:job-register-background-processes
                   job '(4321 4322) "left | right"))
      (expect '(4321 4322) :to-equal (nshell.domain.execution:job-pids job))
      (expect 4321 :to-equal (nshell.domain.execution:job-pgid job))
      (expect "left | right" :to-equal (nshell.domain.execution:job-command-line job))
      (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
      (expect :running :to-be (nshell.domain.execution:job-state job))))

  (it "job-record-runtime-metadata-is-domain-owned"
    "Job runtime metadata is updated through one aggregate operation."
    (let ((job (make-test-job 0 "sleep")))
      (expect job :to-be (nshell.domain.execution:job-record-runtime-metadata
               job
               :pids '(10 nil 20)
               :pgid 10
               :command-line "sleep 10"))
      (expect '(10 nil 20) :to-equal (nshell.domain.execution:job-pids job))
      (expect 10 :to-equal (nshell.domain.execution:job-pgid job))
      (expect "sleep 10" :to-equal (nshell.domain.execution:job-command-line job))
      (expect (lambda () (nshell.domain.execution:job-record-runtime-metadata job :pids #(1))) :to-throw 'error)
      (expect (lambda () (nshell.domain.execution:job-record-runtime-metadata job :pgid nil)) :to-throw 'error)
      (expect (lambda () (nshell.domain.execution:job-record-runtime-metadata job :command-line :sleep)) :to-throw 'error)))

  (it "job-runtime-metadata-projections-are-domain-owned"
    "Job runtime metadata projections cannot mutate job state."
    (let* ((pids (list 4321 4322))
           (command-line (copy-seq "left | right"))
           (job (make-test-job 0 "left")))
      (nshell.domain.execution:job-register-background-processes
       job pids command-line)
      (setf (first pids) 9999)
      (setf (char command-line 0) #\X)
      (let ((pids-view (nshell.domain.execution:job-pids job))
            (line-view (nshell.domain.execution:job-command-line job))
            (display-view (nshell.domain.execution:job-command-display-string job)))
        (setf (first pids-view) 1111)
        (setf (char line-view 0) #\Y)
        (setf (char display-view 0) #\Z))
      (expect '(4321 4322) :to-equal (nshell.domain.execution:job-pids job))
      (expect "left | right" :to-equal (nshell.domain.execution:job-command-line job))
      (expect "left | right" :to-equal (nshell.domain.execution:job-command-display-string job))))

  (it "job-visibility-and-terminal-exit-code-updates-are-domain-operations"
    "Mutable job facts are changed through explicit domain operations."
    (let ((job (make-test-job 0 "sleep")))
      (expect job :to-be (nshell.domain.execution:job-set-background-visible job t))
      (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
      (nshell.domain.execution:job-set-background-visible job nil)
      (expect (nshell.domain.execution:job-background-p job) :to-be-falsy)
      (nshell.domain.execution:job-record-terminal-exit-code job 7)
      (expect (nshell.domain.execution:job-exit-code job) :to-be-null)
      (nshell.domain.execution:job-state-transition job :completed)
      (expect job :to-be (nshell.domain.execution:job-record-terminal-exit-code job 7))
      (expect 7 :to-equal (nshell.domain.execution:job-exit-code job))))

  (it "job-control-query-normalizes-process-group-id"
    "Job control queries expose only usable process-group ids."
    (let ((job (make-test-job 0 "sleep" :pgid 4321))
          (invalid-job (make-test-job 1 "sleep" :pgid 0)))
      (expect (nshell.domain.execution:valid-process-group-id-p 4321) :to-be-truthy)
      (expect (nshell.domain.execution:valid-process-group-id-p 0) :to-be-falsy)
      (expect (nshell.domain.execution:valid-process-group-id-p nil) :to-be-falsy)
      (expect 4321 :to-equal (nshell.domain.execution:job-control-pgid job))
      (expect (nshell.domain.execution:job-control-pgid invalid-job) :to-be-null)))

  (it "job-command-display-string-prefers-recorded-command-line"
    "Job display command is a domain query over runtime metadata and pipeline fallback."
    (let* ((recorded (make-test-job 0 "sleep" :args '("10")))
           (cmd (nshell.domain.execution:make-command "echo" '("hello")))
           (pipeline-only (nshell.domain.execution:make-job
                           1
                           (nshell.domain.execution:make-pipeline cmd))))
      (nshell.domain.execution:job-register-background-processes
       recorded '(4321) "sleep 10 &")
      (expect "sleep 10 &" :to-equal (nshell.domain.execution:job-command-display-string recorded))
      (expect "echo hello" :to-equal (nshell.domain.execution:job-command-display-string pipeline-only))))

  (it "job-completed-p-recognizes-done"
    "Terminal done state is treated as completed."
    (let* ((cmd (nshell.domain.execution:make-command "ls"))
           (pipe (nshell.domain.execution:make-pipeline cmd))
           (job (nshell.domain.execution:make-job 43 pipe)))
      (nshell.domain.execution:job-state-transition job :done)
      (expect t :to-be (nshell.domain.execution:job-completed-p job))))

  (it "job-state-validation"
    "Valid states are recognized, invalid are not"
    (expect (nshell.domain.execution:job-state-valid-p :running) :to-be-truthy)
    (expect (nshell.domain.execution:job-state-valid-p :created) :to-be-truthy)
    (expect (nshell.domain.execution:job-state-valid-p :stopped) :to-be-truthy)
    (expect (nshell.domain.execution:job-state-valid-p :done) :to-be-truthy)
    (expect (nshell.domain.execution:job-state-valid-p :invalid) :to-be-falsy)
    (expect (nshell.domain.execution:job-state-valid-p :zombie) :to-be-falsy))

  (it "job-known-pids-filters-positive-integers"
    "Job PID queries return only positive integer pids."
    (let ((job (make-test-job 0 "sleep" :pids '(111 nil 222 0 333))))
      (expect '(111 222 333) :to-equal (nshell.domain.execution:job-known-pids job))))

  (it "job-last-pid-returns-last-known-pid"
    "Job PID queries expose the last positive-integer pid, or nil when none exist."
    (let ((job (make-test-job 0 "sleep" :pids '(111 222 333)))
          (empty-job (make-test-job 1 "sleep")))
      (expect 333 :to-equal (nshell.domain.execution:job-last-pid job))
      (expect (nshell.domain.execution:job-last-pid empty-job) :to-be-null))))
