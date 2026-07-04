(in-package #:nshell/test)

(def-suite execution-domain-tests
  :description "Execution domain value object tests"
  :in nshell-tests)

(in-suite execution-domain-tests)

;;; Command tests
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
