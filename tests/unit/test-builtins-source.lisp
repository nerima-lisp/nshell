(in-package #:nshell/test)

(in-suite builtin-tests)

(test source-reader-use-case-boundary-is-public
  "The application layer exposes source reader use cases for presentation callers."
  (is (fboundp 'nshell.application:source-lines))
  (is (fboundp 'nshell.application:collect-source-lines))
  (is (equal '("echo one" "echo two")
             (with-input-from-string (stream (format nil "echo one~%echo two~%"))
               (nshell.application:collect-source-lines stream)))))

(defun %source-sequence-call-order (line first-code second-code)
  (let ((calls nil))
    (let ((context (make-test-builtins-context
                    :external-capture-runner
                    (lambda (command args)
                      (is (null args))
                      (push command calls)
                      (values "" (if (string= command "first")
                                     first-code
                                     second-code))))))
      (with-called-source (output code context (list line))
        (values output code (nreverse calls))))))

(test source-sequence-and-short-circuits-on-failure
  "source stops a sequence after a failing && command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order "first && second" 1 0)
    (is (string= "" output))
    (is (= 1 code))
    (is (equal '("first") calls))))

(test source-sequence-and-continues-on-success
  "source continues past a successful && command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order "first && second" 0 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first" "second") calls))))

(test source-sequence-or-short-circuits-on-success
  "source stops a sequence after a successful || command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order "first || second" 0 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first") calls))))

(test source-sequence-or-continues-on-failure
  "source continues past a failing || command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order "first || second" 1 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first" "second") calls))))

(test source-sequence-amp-spawns-background-command-and-continues
  "source runs the command before & asynchronously and continues with the next command."
  (let ((foreground-calls nil)
        (spawned nil))
    (let ((context (make-test-builtins-context
                    :external-capture-runner
                    (lambda (command args)
                      (is (null args))
                      (push command foreground-calls)
                      (values (format nil "~a~%" command) 0)))))
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-async
           (lambda (command args &key redirects)
             (setf spawned (list command args redirects))
             t))
        (with-called-source (output code context '("first & second"))
          (is (= 0 code))
          (is (string= (format nil "second~%") output))
          (is (equal '("second") (nreverse foreground-calls)))
          (is (equal '("first" nil nil) spawned)))))))

(test source-sequence-amp-spawns-background-pipeline-and-continues
  "source runs the pipeline before & asynchronously and continues with the next command."
  (let ((foreground-calls nil)
        (spawned nil))
    (let ((context (make-test-builtins-context
                    :external-capture-runner
                    (lambda (command args)
                      (is (null args))
                      (push command foreground-calls)
                      (values (format nil "~a~%" command) 0)))))
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline-async
           (lambda (commands &key redirects)
             (setf spawned (list (mapcar #'nshell.domain.parsing:command-node-command
                                         commands)
                                 redirects))
             commands))
        (with-called-source (output code context '("first | second & third"))
          (is (= 0 code))
          (is (string= (format nil "third~%") output))
          (is (equal '("third") (nreverse foreground-calls)))
          (is (equal '(("first" "second") (nil nil)) spawned)))))))

(test source-sequence-amp-registers-background-command-job
  "source registers background commands so jobs can report them."
  (let ((process :background-process))
    (let ((context (make-test-builtins-context
                    :external-capture-runner
                    (lambda (command args)
                      (is (string= "second" command))
                      (is (null args))
                      (values (format nil "~a~%" command) 0)))))
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-async
           (lambda (command args &key redirects)
             (declare (ignore redirects))
             (is (string= "first" command))
             (is (equal '("arg") args))
             process))
        (with-temporary-function
            ('nshell.application::%background-process-pid
             (lambda (proc)
               (when (eq proc process)
                 4321)))
          (with-called-source (output code context '("first arg & second"))
            (is (= 0 code))
            (is (string= (format nil "second~%") output))
            (let* ((entries (collect-monitor-entries
                             (nshell.application:shell-context-job-monitor
                              context)))
                   (entry (first entries))
                   (job-id (test-monitor-entry-job-id entry))
                   (job (test-monitor-entry-job entry)))
              (is (= 1 (length entries)))
              (is (equal '(4321) (nshell.domain.execution:job-pids job)))
              (is (= 4321 (nshell.domain.execution:job-pgid job)))
              (is (nshell.domain.execution:job-background-p job))
              (is (eq :running (nshell.domain.execution:job-state job)))
              (is (string= "first arg"
                           (nshell.domain.execution:job-command-display-string
                            job)))
              (is (eq process
                      (nshell.application:shell-context-job-processes
                       context job-id))))))))))

(test source-sequence-amp-registers-background-pipeline-job
  "source registers background pipelines with every spawned process."
  (let ((processes '(:left-process :right-process)))
    (let ((context (make-test-builtins-context
                    :external-capture-runner
                    (lambda (command args)
                      (is (string= "third" command))
                      (is (null args))
                      (values (format nil "~a~%" command) 0)))))
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline-async
           (lambda (commands &key redirects)
             (declare (ignore redirects))
             (is (equal '("first" "second")
                        (mapcar #'nshell.domain.parsing:command-node-command
                                commands)))
             processes))
        (with-temporary-function
            ('nshell.application::%background-process-pid
             (lambda (proc)
               (case proc
                 (:left-process 4321)
                 (:right-process 4322))))
          (with-called-source (output code context
                                      '("first left | second right & third"))
            (is (= 0 code))
            (is (string= (format nil "third~%") output))
            (let* ((entries (collect-monitor-entries
                             (nshell.application:shell-context-job-monitor
                              context)))
                   (entry (first entries))
                   (job-id (test-monitor-entry-job-id entry))
                   (job (test-monitor-entry-job entry)))
              (is (= 1 (length entries)))
              (is (equal '(4321 4322)
                         (nshell.domain.execution:job-pids job)))
              (is (= 4321 (nshell.domain.execution:job-pgid job)))
              (is (nshell.domain.execution:job-background-p job))
              (is (eq :running (nshell.domain.execution:job-state job)))
              (is (string= "first left | second right"
                           (nshell.domain.execution:job-command-display-string
                            job)))
              (is (eq processes
                      (nshell.application:shell-context-job-processes
                       context job-id))))))))))

(test source-lines-skips-comments-and-keeps-command-lines
  "source line filtering is verified through the public source-lines use case."
  (let ((calls nil))
    (let ((context (make-test-builtins-context
                    :external-capture-runner
                    (lambda (command args)
                      (is (null args))
                      (push command calls)
                      (values (format nil "~a~%" command) 0)))))
    (multiple-value-bind (output code)
        (nshell.application:source-lines
         context
         '("#!/usr/bin/env nshell"
           ""
           "  "
           "# a comment"
           "first"
           "second"))
      (is (= 0 code))
      (is (string= (format nil "first~%second~%") output))
      (is (equal '("first" "second") (nreverse calls)))))))

(test source-lines-stores-inline-function-and-executes-tail
  "function scanning is verified by stored definition and tail execution effects."
  (let ((calls nil))
    (let ((context (make-test-builtins-context
                    :external-capture-runner
                    (lambda (command args)
                      (is (null args))
                      (push command calls)
                      (values (format nil "~a~%" command) 0)))))
    (multiple-value-bind (output code)
        (nshell.application:source-lines
         context
         '("function foo; echo hi; end; tail"))
      (is (= 0 code))
      (is (string= (format nil "tail~%") output))
      (is (equal '("tail") (nreverse calls)))
      (is (equal '("echo hi")
                 (gethash "foo"
                          (nshell.application:shell-context-function-table
                           context))))))))

(test source-lines-stores-nested-function-body
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
      (is (= 0 code))
      (is (string= "" output))
      (is (equal '("if true" "echo nested" "end")
                 (gethash "wrapped"
                          (nshell.application:shell-context-function-table
                           context)))))))

(test source-lines-reports-missing-function-end
  "missing function terminators are reported by the public source-lines use case."
  (let ((context (make-test-builtins-context)))
    (multiple-value-bind (output code)
        (nshell.application:source-lines context '("function foo"))
      (is (= 2 code))
      (is (string= (format nil "source: function foo missing end~%")
                   output)))))
