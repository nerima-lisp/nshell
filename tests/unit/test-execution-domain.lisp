(in-package #:nshell/test)

(def-suite execution-domain-tests
  :description "Execution domain value object tests"
  :in nshell-tests)

(in-suite execution-domain-tests)

(defun execution-domain-external-symbol-p (name)
  (eq :external
      (nth-value 1 (find-symbol name '#:nshell.domain.execution))))

;;; Command tests
(test command-value-boundary-is-public-api-only
  "Command exposes constructor and projections, not raw structure internals."
  (is (execution-domain-external-symbol-p "MAKE-COMMAND"))
  (is (execution-domain-external-symbol-p "COMMAND-NAME"))
  (is (execution-domain-external-symbol-p "COMMAND-ARGS"))
  (is (execution-domain-external-symbol-p "COMMAND-TO-LIST"))
  (is (not (execution-domain-external-symbol-p "COMMAND-NAME-STR")))
  (is (not (execution-domain-external-symbol-p "COMMAND-ARGS-LIST")))
  (is (not (fboundp 'nshell.domain.execution::%make-command)))
  (is (not (fboundp 'nshell.domain.execution::copy-command)))
  (is (not (fboundp 'nshell.domain.execution::command-p)))
  (is (fboundp 'nshell.domain.execution::%allocate-command))
  (is (fboundp 'nshell.domain.execution::%make-command-with-invariants)))

(test command-creation
  "Command can be created with name and optional args"
  (let ((cmd (nshell.domain.execution:make-command "ls" '("-l" "-a"))))
    (is (string= "ls" (nshell.domain.execution:command-name cmd)))
    (is (equal '("-l" "-a") (nshell.domain.execution:command-args cmd)))))

(test command-without-args
  "Command can be created without arguments"
  (let ((cmd (nshell.domain.execution:make-command "pwd")))
    (is (string= "pwd" (nshell.domain.execution:command-name cmd)))
    (is (null (nshell.domain.execution:command-args cmd)))))

(test command-to-list
  "Command converts to flat list of strings"
  (let ((cmd (nshell.domain.execution:make-command "echo" '("hello" "world"))))
    (is (equal '("echo" "hello" "world")
               (nshell.domain.execution:command-to-list cmd)))))

(test command-rejects-invalid-values-at-domain-boundary
  "Command construction validates values before allocating the structure."
  (signals type-error
    (nshell.domain.execution:make-command :echo '("hello")))
  (signals type-error
    (nshell.domain.execution:make-command "echo" "hello")))

(test command-projections-are-domain-owned
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
    (is (string= "echo" (nshell.domain.execution:command-name cmd)))
    (is (equal '("hello" "world")
               (nshell.domain.execution:command-args cmd)))
    (is (equal '("echo" "hello" "world")
               (nshell.domain.execution:command-to-list cmd)))))

;;; Pipeline tests
(test pipeline-creation
  "Pipeline can be created with multiple commands"
  (let* ((cmd1 (nshell.domain.execution:make-command "ls"))
         (cmd2 (nshell.domain.execution:make-command "grep" '("foo")))
         (pipe (nshell.domain.execution:make-pipeline cmd1 cmd2)))
    (is (= 2 (nshell.domain.execution:pipeline-length pipe)))
    (is (not (nshell.domain.execution:pipeline-single-command-p pipe)))
    (is (not (nshell.domain.execution:pipeline-empty-p pipe)))))

(test pipeline-single-command
  "Pipeline with one command reports as single"
  (let* ((cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd)))
    (is (nshell.domain.execution:pipeline-single-command-p pipe))))

(test pipeline-empty
  "Empty pipeline reports correctly"
  (let ((pipe (nshell.domain.execution:make-pipeline)))
    (is (nshell.domain.execution:pipeline-empty-p pipe))
    (is (= 0 (nshell.domain.execution:pipeline-length pipe)))))

;;; Job tests
(test job-creation
  "Job created with initial :created state"
  (let* ((cmd (nshell.domain.execution:make-command "sleep" '("10")))
         (pipe (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job 1 pipe)))
    (is (= 1 (nshell.domain.execution:job-id job)))
    (is (eq :created (nshell.domain.execution:job-state job)))
    (is (zerop (nshell.domain.execution:job-pgid job)))))

(test job-state-transitions
  "Job state transitions are owned by the job aggregate."
  (let* ((cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job 42 pipe)))
    (nshell.domain.execution:job-state-transition job :running)
    (is (nshell.domain.execution:job-running-p job))
    (nshell.domain.execution:job-state-transition job :stopped)
    (is (nshell.domain.execution:job-stopped-p job))
    (nshell.domain.execution:job-state-transition job :completed)
    (is (eq t (nshell.domain.execution:job-completed-p job)))))

(test terminal-job-state-cannot-return-to-active
  "Completed jobs are terminal and cannot be restarted by callers."
  (let* ((cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job 42 pipe)))
    (nshell.domain.execution:job-state-transition job :running)
    (nshell.domain.execution:job-state-transition job :completed)
    (signals error
      (nshell.domain.execution:job-state-transition job :running))
    (is (eq :completed (nshell.domain.execution:job-state job)))))

(test job-register-background-processes-initializes-runtime-metadata
  "Job aggregate owns process metadata initialization."
  (let ((job (make-test-job 0 "left")))
    (is (eq job (nshell.domain.execution:job-register-background-processes
                 job '(4321 4322) "left | right")))
    (is (equal '(4321 4322) (nshell.domain.execution:job-pids job)))
    (is (= 4321 (nshell.domain.execution:job-pgid job)))
    (is (string= "left | right" (nshell.domain.execution:job-command-line job)))
    (is (nshell.domain.execution:job-background-p job))
    (is (eq :running (nshell.domain.execution:job-state job)))))

(test job-runtime-metadata-projections-are-domain-owned
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
    (is (equal '(4321 4322) (nshell.domain.execution:job-pids job)))
    (is (string= "left | right"
                 (nshell.domain.execution:job-command-line job)))
    (is (string= "left | right"
                 (nshell.domain.execution:job-command-display-string job)))))

(test job-visibility-and-terminal-exit-code-updates-are-domain-operations
  "Mutable job facts are changed through explicit domain operations."
  (let ((job (make-test-job 0 "sleep")))
    (is (eq job (nshell.domain.execution:job-set-background-visible job t)))
    (is (nshell.domain.execution:job-background-p job))
    (nshell.domain.execution:job-set-background-visible job nil)
    (is (not (nshell.domain.execution:job-background-p job)))
    (nshell.domain.execution:job-record-terminal-exit-code job 7)
    (is (null (nshell.domain.execution:job-exit-code job)))
    (nshell.domain.execution:job-state-transition job :completed)
    (is (eq job (nshell.domain.execution:job-record-terminal-exit-code job 7)))
    (is (= 7 (nshell.domain.execution:job-exit-code job)))))

(test job-control-query-normalizes-process-group-id
  "Job control queries expose only usable process-group ids."
  (let ((job (make-test-job 0 "sleep" :pgid 4321))
        (invalid-job (make-test-job 1 "sleep" :pgid 0)))
    (is (nshell.domain.execution:valid-process-group-id-p 4321))
    (is (not (nshell.domain.execution:valid-process-group-id-p 0)))
    (is (not (nshell.domain.execution:valid-process-group-id-p nil)))
    (is (= 4321 (nshell.domain.execution:job-control-pgid job)))
    (is (null (nshell.domain.execution:job-control-pgid invalid-job)))))

(test job-command-display-string-prefers-recorded-command-line
  "Job display command is a domain query over runtime metadata and pipeline fallback."
  (let* ((recorded (make-test-job 0 "sleep" :args '("10")))
         (cmd (nshell.domain.execution:make-command "echo" '("hello")))
         (pipeline-only (nshell.domain.execution:make-job
                         1
                         (nshell.domain.execution:make-pipeline cmd))))
    (nshell.domain.execution:job-register-background-processes
     recorded '(4321) "sleep 10 &")
    (is (string= "sleep 10 &"
                 (nshell.domain.execution:job-command-display-string recorded)))
    (is (string= "echo hello"
                 (nshell.domain.execution:job-command-display-string pipeline-only)))))

(test job-completed-p-recognizes-done
  "Terminal done state is treated as completed."
  (let* ((cmd (nshell.domain.execution:make-command "ls"))
         (pipe (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job 43 pipe)))
    (nshell.domain.execution:job-state-transition job :done)
    (is (eq t (nshell.domain.execution:job-completed-p job)))))

(test job-state-validation
  "Valid states are recognized, invalid are not"
  (is (nshell.domain.execution:job-state-valid-p :running))
  (is (nshell.domain.execution:job-state-valid-p :created))
  (is (nshell.domain.execution:job-state-valid-p :stopped))
  (is (nshell.domain.execution:job-state-valid-p :done))
  (is (not (nshell.domain.execution:job-state-valid-p :invalid)))
  (is (not (nshell.domain.execution:job-state-valid-p :zombie))))

(test job-known-pids-filters-positive-integers
  "Job PID queries return only positive integer pids."
  (let ((job (make-test-job 0 "sleep" :pids '(111 nil 222 0 333))))
    (is (equal '(111 222 333)
               (nshell.domain.execution:job-known-pids job)))))

(test job-last-pid-returns-last-known-pid
  "Job PID queries expose the last positive-integer pid, or nil when none exist."
  (let ((job (make-test-job 0 "sleep" :pids '(111 222 333)))
        (empty-job (make-test-job 1 "sleep")))
    (is (= 333 (nshell.domain.execution:job-last-pid job)))
    (is (null (nshell.domain.execution:job-last-pid empty-job)))))
