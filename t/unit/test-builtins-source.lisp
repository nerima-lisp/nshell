(in-package #:nshell/test)

(describe "builtin-tests"
  (it "source-reader-use-case-boundary-is-public"
    "The application layer exposes source reader use cases for presentation callers."
    (expect (fboundp 'nshell.application:source-lines) :to-be-truthy)
    (expect (fboundp 'nshell.application:collect-source-lines) :to-be-truthy)
    (expect '("echo one" "echo two") :to-equal
            (with-input-from-string (stream (format nil "echo one~%echo two~%"))
              (nshell.application:collect-source-lines stream))))
  (it "source-lines-default-to-the-production-reader-for-both-paths"
    (let ((source '("(if t 1 2)")))
      (multiple-value-bind (batch-output batch-code)
          (nshell.application:source-lines
           (make-test-builtins-context)
           source)
        (multiple-value-bind (file-output file-code)
            (nshell.application:source-lines
             (make-test-builtins-context)
             source
             "source-test.nsh")
          (expect 0 :to-equal batch-code)
          (expect (format nil "1~%") :to-equal batch-output)
          (expect batch-code :to-equal file-code)
          (expect batch-output :to-equal file-output)))
      (let* ((stream-code nil)
             (stream-output
               (capture-standard-output
                 (setf stream-code
                       (nth-value
                        1
                        (nshell.application:source-lines-to-stream
                         (make-test-builtins-context)
                         source))))))
        (expect 0 :to-equal stream-code)
        (expect (format nil "1~%") :to-equal stream-output))))
  (it "source-expands-reader-command-arguments-from-shell-environment"
    (let* ((context (make-test-builtins-context))
           (environment (nshell.application:shell-context-environment context)))
      (setf (nshell.application:shell-context-environment context)
            (nshell.domain.environment:env-set
             environment "TARGET" "/fixture/target" t))
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context (list "echo \"$TARGET\""
                "printf \"source-$((2+3))\\n\""
                "printf \"escaped-\\$((2+3))\\n\""))
        (expect 0 :to-equal code)
        (expect (format nil "/fixture/target~%source-5~%escaped-$((2+3))~%") :to-equal output))))
  (it "source-persists-exported-environment-changes"
    (let* ((context (make-test-builtins-context))
           (base-environment
             (nshell.application:shell-context-environment context))
           (environment
             (nshell.domain.environment:env-set
              (nshell.domain.environment:env-set
               base-environment "HOME" "/home/test" t)
              "PATH" "/usr/bin:/bin" t)))
      (setf (nshell.application:shell-context-environment context) environment)
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           (list
            "(export \"PATH=/fixture/bin:/home/test/bin:/usr/bin:/bin\")")
           "init.lisp")
        (expect 0 :to-equal code)
        (expect "" :to-equal output)
        (expect "/fixture/bin:/home/test/bin:/usr/bin:/bin" :to-equal
                (nshell.domain.environment:env-get
                 (nshell.application:shell-context-environment context)
                 "PATH"))
        (expect (nshell.domain.environment:env-exported-p
                 (nshell.application:shell-context-environment context)
                 "PATH")
                :to-be-truthy)))))

(defun %source-sequence-call-order (line first-code second-code)
  (let ((calls nil)
        (context (%make-source-sequence-test-context)))
    (let ((nshell.application::*builtin-binding-registry*
            (let ((registry (make-hash-table :test (function equal))))
              (maphash (lambda (name binding)
                         (setf (gethash name registry) binding))
                       nshell.application::*builtin-binding-registry*)
              registry)))
      (labels ((register-command (command code)
                 (nshell.application:register-builtin
                  command
                  (nshell.application:make-builtin-binding
                   (lambda (ignored-context args)
                     (declare (ignore ignored-context))
                     (expect args :to-be-null)
                     (push command calls)
                     (values "" code))
                   :argv))))
        (register-command "x01-command-a" first-code)
        (register-command "x01-command-b" second-code)
        (register-command "x01-command-c" second-code)
        (with-called-source (output code context (list line))
          (values output code (nreverse calls)))))))
(defun %make-source-sequence-test-context ()
  (make-test-builtins-context
   :filesystem (%make-test-builtins-filesystem
               :files '("/bin/x01-command-a"
                        "/bin/x01-command-b"
                        "/bin/x01-command-c"))))

(describe "builtin-tests"
  (it "source-sequence-and-short-circuits-on-failure"
    "source stops a sequence after a failing && command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "x01-command-a && x01-command-b" 1 0)
      (expect "" :to-equal output)
      (expect 1 :to-equal code)
      (expect '("x01-command-a") :to-equal calls)))

  (it "source-sequence-and-continues-on-success"
    "source continues past a successful && command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "x01-command-a && x01-command-b" 0 0)
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect '("x01-command-a" "x01-command-b") :to-equal calls)))

  (it "source-sequence-or-short-circuits-on-success"
    "source stops a sequence after a successful || command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "x01-command-a || x01-command-b" 0 0)
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect '("x01-command-a") :to-equal calls)))

  (it "source-sequence-or-continues-on-failure"
    "source continues past a failing || command."
    (multiple-value-bind (output code calls)
        (%source-sequence-call-order "x01-command-a || x01-command-b" 1 0)
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect '("x01-command-a" "x01-command-b") :to-equal calls)))

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
      (let ((context (%make-source-sequence-test-context)))
        (with-stubbed-command-builtin
            (("x01-command-b"
              (expect nil :to-equal *stubbed-command-builtin-arguments*)
              (push "x01-command-b" foreground-calls)
              (values (format nil "x01-command-b~%") 0)))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-async
               (lambda (command args &key redirects)
                 (setf spawned (list command args redirects))
                 t))
            (with-called-source (output code context
                                        (list "x01-command-a & x01-command-b"))
              (expect 0 :to-equal code)
              (expect (format nil "x01-command-b~%") :to-equal output)
              (expect (list "x01-command-b") :to-equal
                      (nreverse foreground-calls))
              (expect (list "x01-command-a" nil nil) :to-equal spawned)))))))

  (it "source-sequence-amp-spawns-background-pipeline-and-continues"
    "source runs the pipeline before & asynchronously and continues with the next command."
    (let ((foreground-calls nil)
          (spawned nil))
      (let ((context (%make-source-sequence-test-context)))
        (with-stubbed-command-builtin
            (("x01-command-c"
              (expect nil :to-equal *stubbed-command-builtin-arguments*)
              (push "x01-command-c" foreground-calls)
              (values (format nil "x01-command-c~%") 0)))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-pipeline-async
               (lambda (commands &key redirects &allow-other-keys)
                 (setf spawned
                       (list (mapcar
                              (function nshell.domain.parsing:command-node-command)
                              commands)
                             redirects))
                 commands))
            (with-called-source
                (output code context
                        (list "x01-command-a | x01-command-b & x01-command-c"))
              (expect 0 :to-equal code)
              (expect (format nil "x01-command-c~%") :to-equal output)
              (expect (list "x01-command-c") :to-equal
                      (nreverse foreground-calls))
              (expect (list (list "x01-command-a" "x01-command-b") nil) :to-equal spawned)))))))

  (it "source-sequence-amp-registers-background-command-job"
    "source registers background commands so jobs can report them."
    (let ((process :background-process))
      (let ((context (%make-source-sequence-test-context)))
        (with-stubbed-command-builtin
            (("x01-command-b"
              (expect nil :to-equal *stubbed-command-builtin-arguments*)
              (values (format nil "x01-command-b~%") 0)))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-async
               (lambda (command args &key redirects)
                 (declare (ignore redirects))
                 (expect "x01-command-a" :to-equal command)
                 (expect (list "arg") :to-equal args)
                 process))
            (with-temporary-function
                ('nshell.application::%background-process-pid
                 (lambda (proc)
                   (when (eq proc process)
                     4321)))
              (with-called-source
                  (output code context
                          (list "x01-command-a arg & x01-command-b"))
                (expect 0 :to-equal code)
                (expect (format nil "x01-command-b~%") :to-equal output)
                (let* ((entries (collect-monitor-entries
                                 (nshell.application:shell-context-job-monitor
                                  context)))
                       (entry (first entries))
                       (job-id (test-monitor-entry-job-id entry))
                       (job (test-monitor-entry-job entry)))
                  (expect 1 :to-equal (length entries))
                  (expect (list 4321) :to-equal
                          (nshell.domain.execution:job-pids job))
                  (expect 4321 :to-equal
                          (nshell.domain.execution:job-pgid job))
                  (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
                  (expect :running :to-be (nshell.domain.execution:job-state job))
                  (expect "x01-command-a arg" :to-equal
                          (nshell.domain.execution:job-command-display-string job))
                  (expect process :to-be
                          (nshell.application:shell-context-job-processes
                           context job-id))))))))))

  (it "source-sequence-amp-registers-background-pipeline-job"
    "source registers background pipelines with every spawned process."
    (let ((processes (list :left-process :right-process)))
      (let ((context (%make-source-sequence-test-context)))
        (with-stubbed-command-builtin
            (("x01-command-c"
              (expect nil :to-equal *stubbed-command-builtin-arguments*)
              (values (format nil "x01-command-c~%") 0)))
          (with-temporary-function
              ('nshell.infrastructure.acl:spawn-pipeline-async
               (lambda (commands &key redirects &allow-other-keys)
                 (declare (ignore redirects))
                 (expect (list "x01-command-a" "x01-command-b") :to-equal
                         (mapcar (function nshell.domain.parsing:command-node-command)
                                 commands))
                 processes))
            (with-temporary-function
                ('nshell.application::%background-process-pid
                 (lambda (proc)
                   (case proc
                     (:left-process 4321)
                     (:right-process 4322))))
              (with-called-source
                  (output code context
                          (list "x01-command-a left | x01-command-b right & x01-command-c"))
                (expect 0 :to-equal code)
                (expect (format nil "x01-command-c~%") :to-equal output)
                (let* ((entries (collect-monitor-entries
                                 (nshell.application:shell-context-job-monitor
                                  context)))
                       (entry (first entries))
                       (job-id (test-monitor-entry-job-id entry))
                       (job (test-monitor-entry-job entry)))
                  (expect 1 :to-equal (length entries))
                  (expect (list 4321 4322) :to-equal
                          (nshell.domain.execution:job-pids job))
                  (expect 4321 :to-equal
                          (nshell.domain.execution:job-pgid job))
                  (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
                  (expect :running :to-be (nshell.domain.execution:job-state job))
                  (expect "x01-command-a left | x01-command-b right" :to-equal
                          (nshell.domain.execution:job-command-display-string job))
                  (expect processes :to-be
                          (nshell.application:shell-context-job-processes
                           context job-id))))))))))

  (it "source-lines-skips-comments-and-keeps-command-lines"
    "source line filtering is verified through the public source-lines use case."
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           '("#!/usr/bin/env nshell" "" "  " "# a comment"
             "echo first" "echo second"))
        (expect 0 :to-equal code)
        (expect (format nil "first~%second~%") :to-equal output))))

  (it "source-lines-defines-sexp-function-and-executes-tail"
    "source executes forms around an S-expression function on the same line."
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           (list "(echo pre) (define-shell-function foo () (echo hi)) (foo) (echo tail)"))
        (expect 0 :to-equal code)
        (expect (format nil "pre~%hi~%tail~%") :to-equal output)
        (expect t :to-equal
                (nth-value
                 1
                 (nshell.application:lookup-shell-function
                  (nshell.application:context-shell-function-registry context)
                  "foo"))))))
  (it "source-sexp-function-body-runs-forms-in-order"
    "source collects a multiline function definition and runs its body in order."
    (multiple-value-bind (output code)
        (nshell.application:source-lines
         (make-test-builtins-context)
         (list "(define-shell-function foo ()"
               "(echo one)"
               "(echo two))"
               "(foo)"))
      (expect 0 :to-equal code)
      (expect (format nil "one~%two~%") :to-equal output))))
(describe "builtin-source-branch-tests"
  (it "source-without-path-reports-usage"
    (multiple-value-bind (output code)
        (call-builtin (make-test-builtins-context) "source" nil)
      (expect 1 :to-equal code)
      (expect (search "source: usage: source file" output) :to-be-truthy)))
  (it "source-lines-stream-stops-after-incomplete-reader-input"
    "source-lines stops after the new reader rejects incomplete input."
    (let ((output-stream (make-string-output-stream))
          (reader-error-p nil))
      (let ((*standard-output* output-stream))
        (handler-case
            (nshell.application:source-lines-to-stream
             (make-test-builtins-context)
             '("echo first" "(unclosed" "echo second"))
          (error (condition)
            (setf reader-error-p
                  (typep condition 'nshell.domain.parsing:sexp-reader-error)))))
      (expect (format nil "first~%") :to-equal
              (get-output-stream-string output-stream))
      (expect t :to-equal reader-error-p)))
  (it "source-missing-path-reports-open-error"
    (let ((path "/definitely/not/a/nshell-source"))
      (multiple-value-bind (output code)
          (call-builtin (make-test-builtins-context) "source" (list path))
        (expect 1 :to-equal code)
        (expect (search (format nil "source: ~a:" path) output) :to-be-truthy)))))

(describe "source-output-regression"
  (it "source-progn-keeps-format-output-and-prints-final-value"
    "source preserves explicit format output and prints the final value of a progn."
    (multiple-value-bind (output code)
        (nshell.application:source-lines
         (make-test-builtins-context)
         (list "(progn (format t \"source-progn-output~%\") 42)"))
      (expect 0 :to-equal code)
      (expect (format nil "source-progn-output~%42~%") :to-equal output))))
(describe "legacy-source-reader-function-tests"
  (it "source-lines-stores-inline-function-and-executes-tail"
    "function scanning is verified by stored definition and tail execution effects."
    (let ((context (make-test-builtins-context)))
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           '("function foo; echo hi; end; echo tail"))
        (expect 0 :to-equal code)
        (expect (format nil "tail~%") :to-equal output)
        (expect '("echo hi") :to-equal
                (gethash "foo"
                         (nshell.application:shell-context-function-table
                          context))))))
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
        (expect '("if true" "echo nested" "end") :to-equal
                (gethash "wrapped"
                         (nshell.application:shell-context-function-table
                          context))))))
  (it "a-definition-after-another-command-on-one-line-runs-whole"
    "`echo pre; function f; echo hi; end; f' must define and call f rather than
running the definition's body as top-level commands."
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           (list "echo pre; function f; echo hi; end; f"))
        (expect 0 :to-equal code)
        (expect (format nil "pre~%hi~%") :to-equal output))))
  (it "the-split-keeps-the-prefix-and-its-separators"
    (flet ((split (line)
             (multiple-value-list
              (nshell.application::source-line-function-split line))))
      (expect '("echo pre" "function f; echo hi; end")
              :to-equal (split "echo pre; function f; echo hi; end"))
      (expect '("sleep 1 &" "function f; end")
              :to-equal (split "sleep 1 & function f; end"))
      (expect '(nil) :to-equal (split "function f; echo hi; end"))
      (expect '(nil) :to-equal (split "echo plain"))
      (expect '(nil) :to-equal (split "echo \"function f\""))))
  (it "a-definition-after-a-newline-separated-statement-is-still-read-whole"
    "The submitted buffer separates commands with newlines, not only semicolons,
so the definition scanner has to treat a newline as a command boundary."
    (expect (nshell.application:function-definition-line-p
             (format nil "echo pre~%function greet~%echo hi~%end"))
            :to-be-truthy)
    (expect (nshell.application:function-definition-line-p
             (format nil "echo one~%echo two"))
            :to-be-falsy))
  (it "the-split-treats-a-newline-like-a-semicolon"
    (flet ((split (line)
             (multiple-value-list
              (nshell.application::source-line-function-split line))))
      (expect (list "echo pre" (format nil "function f~%end"))
              :to-equal (split (format nil "echo pre~%function f~%end")))))
  (it "a-single-source-line-with-newlines-keeps-the-definition-whole"
    "The segment scanner used by inline function consumption must preserve a
function body when source input arrives as one multiline string."
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           (list (format nil "echo pre~%function greet~%echo hello~%end~%greet")))
        (expect 0 :to-equal code)
        (expect (format nil "pre~%hello~%") :to-equal output))))
  (it "a-newline-separated-definition-defines-the-function"
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (nshell.application:source-lines
           context
           (list "echo pre" "function greet" "echo hello" "end" "greet"))
        (expect 0 :to-equal code)
        (expect (format nil "pre~%hello~%") :to-equal output)))))
