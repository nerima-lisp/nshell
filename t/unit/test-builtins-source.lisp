(in-package #:nshell/test)

(describe "builtin-tests"
  (it "source-reader-use-case-boundary-is-public"
    "The application layer exposes source reader use cases for presentation callers."
    (expect (fboundp 'nshell.application:source-lines) :to-be-truthy)
    (expect (fboundp 'nshell.application:collect-source-lines) :to-be-truthy)
    (expect '("echo one" "echo two") :to-equal (with-input-from-string (stream (format nil "echo one~%echo two~%"))
                 (nshell.application:collect-source-lines stream)))))

(defun %source-sequence-call-order (line first-code second-code)
  (let ((calls nil))
    (let ((context (make-test-builtins-context)))
      (with-test-external-capture-runner
          (lambda (command args)
            (expect args :to-be-null)
            (push command calls)
            (values "" (if (string= command "first")
                           first-code
                           second-code)))
        (with-called-source (output code context (list line))
          (values output code (nreverse calls)))))))

(describe "builtin-tests"
  (it "source-sequence-and-short-circuits-on-failure"
    "source stops a sequence after a failing && command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "first && second" 1 0)
      (expect "" :to-equal output)
      (expect 1 :to-equal code)
      (expect '("first") :to-equal calls)))

  (it "source-sequence-and-continues-on-success"
    "source continues past a successful && command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "first && second" 0 0)
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect '("first" "second") :to-equal calls)))

  (it "source-sequence-or-short-circuits-on-success"
    "source stops a sequence after a successful || command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "first || second" 0 0)
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect '("first") :to-equal calls)))

  (it "source-sequence-or-continues-on-failure"
    "source continues past a failing || command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "first || second" 1 0)
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect '("first" "second") :to-equal calls)))

  (it "source-propagates-last-status-to-following-parameter-expansion"
    "A failed command is visible through $? in the next source command."
    (with-builtins-source-ok (output code context '("false" "echo $?"))
        (format nil "1~%")
      (expect 0 :to-equal (nshell.application:shell-context-last-exit-code context))))

  (it "source-stops-after-exit-and-preserves-its-status"
    "exit stops subsequent source lines and returns its explicit status."
    (with-builtins-source (output code context '("exit 7" "echo after"))
      (expect "" :to-equal output)
      (expect 7 :to-equal code)
      (expect 7 :to-equal (nshell.application:shell-context-last-exit-code context))
      (expect (nshell.application:shell-context-running context) :to-be-falsy)))

  (it "source-sequence-amp-spawns-background-command-and-continues"
    "source runs the command before & asynchronously and continues with the next command."
    (let ((foreground-calls nil)
          (spawned nil))
      (let ((context (make-test-builtins-context)))
        (with-test-external-capture-runner
            (lambda (command args)
              (expect args :to-be-null)
              (push command foreground-calls)
              (values (format nil "~a~%" command) 0))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-async
               (lambda (command args &key redirects)
                 (setf spawned (list command args redirects))
                 t))
            (with-called-source (output code context '("first & second"))
              (expect 0 :to-equal code)
              (expect (format nil "second~%") :to-equal output)
              (expect '("second") :to-equal (nreverse foreground-calls))
              (expect '("first" nil nil) :to-equal spawned)))))))

  (it "source-sequence-amp-spawns-background-pipeline-and-continues"
    "source runs the pipeline before & asynchronously and continues with the next command."
    (let ((foreground-calls nil)
          (spawned nil))
      (let ((context (make-test-builtins-context)))
        (with-test-external-capture-runner
            (lambda (command args)
              (expect args :to-be-null)
              (push command foreground-calls)
              (values (format nil "~a~%" command) 0))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-pipeline-async
               (lambda (commands &key redirects)
                 (setf spawned (list (mapcar #'nshell.domain.parsing:command-node-command
                                             commands)
                                     redirects))
                 commands))
            (with-called-source (output code context '("first | second & third"))
              (expect 0 :to-equal code)
              (expect (format nil "third~%") :to-equal output)
              (expect '("third") :to-equal (nreverse foreground-calls))
              (expect '(("first" "second") (nil nil)) :to-equal spawned)))))))

  (it "source-sequence-amp-registers-background-command-job"
    "source registers background commands so jobs can report them."
    (let ((process :background-process))
      (let ((context (make-test-builtins-context)))
        (with-test-external-capture-runner
            (lambda (command args)
              (expect "second" :to-equal command)
              (expect args :to-be-null)
              (values (format nil "~a~%" command) 0))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-async
               (lambda (command args &key redirects)
                 (declare (ignore redirects))
                 (expect "first" :to-equal command)
                 (expect '("arg") :to-equal args)
                 process))
            (with-temporary-function
                ('nshell.application::%background-process-pid
                 (lambda (proc)
                   (when (eq proc process)
                     4321)))
              (with-called-source (output code context '("first arg & second"))
                (expect 0 :to-equal code)
                (expect (format nil "second~%") :to-equal output)
                (let* ((entries (collect-monitor-entries
                                 (nshell.application:shell-context-job-monitor
                                  context)))
                       (entry (first entries))
                       (job-id (test-monitor-entry-job-id entry))
                       (job (test-monitor-entry-job entry)))
                  (expect 1 :to-equal (length entries))
                  (expect '(4321) :to-equal (nshell.domain.execution:job-pids job))
                  (expect 4321 :to-equal (nshell.domain.execution:job-pgid job))
                  (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
                  (expect :running :to-be (nshell.domain.execution:job-state job))
                  (expect "first arg" :to-equal (nshell.domain.execution:job-command-display-string
                                job))
                  (expect process :to-be (nshell.application:shell-context-job-processes
                           context job-id))))))))))

  (it "source-sequence-amp-registers-background-pipeline-job"
    "source registers background pipelines with every spawned process."
    (let ((processes '(:left-process :right-process)))
      (let ((context (make-test-builtins-context)))
        (with-test-external-capture-runner
            (lambda (command args)
              (expect "third" :to-equal command)
              (expect args :to-be-null)
              (values (format nil "~a~%" command) 0))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-pipeline-async
               (lambda (commands &key redirects)
                 (declare (ignore redirects))
                 (expect '("first" "second") :to-equal
                         (mapcar #'nshell.domain.parsing:command-node-command
                                 commands))
                 processes))
            (with-temporary-function
                ('nshell.application::%background-process-pid
                 (lambda (proc)
                   (case proc
                     (:left-process 4321)
                     (:right-process 4322))))
              (with-called-source (output code context
                                          '("first left | second right & third"))
                (expect 0 :to-equal code)
                (expect (format nil "third~%") :to-equal output)
                (let* ((entries (collect-monitor-entries
                                 (nshell.application:shell-context-job-monitor
                                  context)))
                       (entry (first entries))
                       (job-id (test-monitor-entry-job-id entry))
                       (job (test-monitor-entry-job entry)))
                  (expect 1 :to-equal (length entries))
                  (expect '(4321 4322) :to-equal (nshell.domain.execution:job-pids job))
                  (expect 4321 :to-equal (nshell.domain.execution:job-pgid job))
                  (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
                  (expect :running :to-be (nshell.domain.execution:job-state job))
                  (expect "first left | second right" :to-equal
                          (nshell.domain.execution:job-command-display-string job))
                  (expect processes :to-be
                          (nshell.application:shell-context-job-processes
                           context job-id))))))))))

  (it "source-lines-skips-comments-and-keeps-command-lines"
    "source line filtering is verified through the public source-lines use case."
    (let ((calls nil))
      (let ((context (make-test-builtins-context)))
        (with-test-external-capture-runner
            (lambda (command args)
              (expect args :to-be-null)
              (push command calls)
              (values (format nil "~a~%" command) 0))
          (multiple-value-bind (output code)
              (nshell.application:source-lines
               context
               '("#!/usr/bin/env nshell"
                 ""
                 "  "
                 "# a comment"
                 "first"
                 "second"))
            (expect 0 :to-equal code)
            (expect (format nil "first~%second~%") :to-equal output)
            (expect '("first" "second") :to-equal (nreverse calls)))))))

  (it "source-lines-stores-inline-function-and-executes-tail"
    "function scanning is verified by stored definition and tail execution effects."
    (let ((calls nil))
      (let ((context (make-test-builtins-context)))
        (with-test-external-capture-runner
            (lambda (command args)
              (expect args :to-be-null)
              (push command calls)
              (values (format nil "~a~%" command) 0))
          (multiple-value-bind (output code)
              (nshell.application:source-lines
               context
               '("function foo; echo hi; end; tail"))
            (expect 0 :to-equal code)
            (expect (format nil "tail~%") :to-equal output)
            (expect '("tail") :to-equal (nreverse calls))
            (expect '("echo hi") :to-equal
                    (gethash "foo"
                             (nshell.application:shell-context-function-table
                              context))))))))
  (it "source-lines-stores-function-body-with-command-separators"
    "function bodies retain command separators while source reader consumes definitions."
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           (list "function foo"
                 "echo one; echo two"
                 "end"))
        (expect 0 :to-equal code)
        (expect "" :to-equal output)
        (expect (list "echo one; echo two")
                :to-equal
                (gethash "foo"
                         (nshell.application:shell-context-function-table
                          context))))))

  (it "source-lines-stores-nested-function-body"
    "function body depth handling is verified through the public source-lines use case."
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           '("function wrapped"
             "if true"
             "echo nested"
             "end"
             "end"))
        (expect 0 :to-equal code)
        (expect "" :to-equal output)
        (expect '("if true" "echo nested" "end") :to-equal (gethash "wrapped"
                            (nshell.application:shell-context-function-table
                             context))))))

  (it "source-lines-reports-missing-function-end"
    "missing function terminators are reported by the public source-lines use case."
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application:source-lines context '("function foo"))
        (expect 2 :to-equal code)
        (expect (format nil "source: function foo missing end~%") :to-equal output)))))
(describe "builtin-source-branch-tests"
  (it "source-without-path-reports-usage"
    (multiple-value-bind (output code)
        (call-builtin (make-test-builtins-context) "source" nil)
      (expect 1 :to-equal code)
      (expect (search "source: usage: source file" output) :to-be-truthy)))
  (it "source-lines-stops-after-invalid-source-form"
    "source-lines reports a parse error from its public loop and does not execute later lines."
    (let* ((calls nil)
           (context (make-test-builtins-context)))
      (with-test-external-capture-runner
          (lambda (command args)
            (declare (ignore args))
            (push command calls)
            (values (format nil "~a~%" command) 0))
        (multiple-value-bind (output code)
            (nshell.application:source-lines context '("first" "end" "second"))
          (expect 2 :to-equal code)
          (expect (search "source: parse error:" output) :to-be-truthy)
          (expect '("first") :to-equal (nreverse calls))))))
  (it "source-missing-path-reports-open-error"
    (let ((path "/definitely/not/a/nshell-source"))
      (multiple-value-bind (output code)
          (call-builtin (make-test-builtins-context) "source" (list path))
        (expect 1 :to-equal code)
        (expect (search (format nil "source: ~a:" path) output) :to-be-truthy))))
  (it "source-line-branches-report-blank-error-and-incomplete"
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application::%execute-source-line context "   ")
        (expect output :to-be-null)
        (expect 0 :to-equal code))
      (multiple-value-bind (output code)
          (nshell.application::%execute-source-line context "end")
        (expect 2 :to-equal code)
        (expect (search "source: parse error:" output) :to-be-truthy))
      (multiple-value-bind (output code)
          (nshell.application::%execute-source-line context "if true")
        (expect 2 :to-equal code)
        (expect (search "source: parse error:" output) :to-be-truthy)))))
