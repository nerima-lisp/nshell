(in-package #:nshell/test)

(in-suite builtin-tests)

(defun %source-sequence-call-order (separator first-code second-code)
  (let ((context (make-test-builtins-context))
        (calls nil))
    (with-temporary-function
        ('nshell.application::execute-ast-in-context
         (lambda (_context ast)
           (declare (ignore _context))
           (let ((command (nshell.domain.parsing:command-node-command ast)))
             (push command calls)
             (values nil (if (string= command "first")
                             first-code
                             second-code)))))
      (let ((ast (nshell.domain.parsing::make-sequence-node
                  (list (nshell.domain.parsing:make-command-node "first" nil)
                        (nshell.domain.parsing:make-command-node "second" nil))
                  (list separator))))
        (multiple-value-bind (output code)
            (nshell.application::%execute-sequence-node-in-context context ast)
          (values output code (nreverse calls)))))))

(test source-sequence-and-short-circuits-on-failure
  "source stops a sequence after a failing && command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :and 1 0)
    (is (string= "" output))
    (is (= 1 code))
    (is (equal '("first") calls))))

(test source-sequence-and-continues-on-success
  "source continues past a successful && command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :and 0 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first" "second") calls))))

(test source-sequence-or-short-circuits-on-success
  "source stops a sequence after a successful || command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :or 0 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first") calls))))

(test source-sequence-or-continues-on-failure
  "source continues past a failing || command."
  (multiple-value-bind (output code calls)
      (%source-sequence-call-order :or 1 0)
    (is (string= "" output))
    (is (= 0 code))
    (is (equal '("first" "second") calls))))

(test source-sequence-amp-spawns-background-command-and-continues
  "source runs the command before & asynchronously and continues with the next command."
  (let ((context (make-test-builtins-context))
        (foreground-calls nil)
        (spawned nil))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-async
         (lambda (command args &key redirects)
           (setf spawned (list command args redirects))
           t))
      (with-temporary-function
          ('nshell.application::execute-ast-in-context
           (lambda (_context ast)
             (declare (ignore _context))
             (let ((command (nshell.domain.parsing:command-node-command ast)))
               (push command foreground-calls)
               (values (format nil "~a~%" command) 0))))
           (let ((ast (nshell.domain.parsing::make-sequence-node
                       (list (nshell.domain.parsing:make-command-node
                              "first" nil)
                             (nshell.domain.parsing:make-command-node "second" nil))
                       (list :amp))))
          (multiple-value-bind (output code)
              (nshell.application::%execute-sequence-node-in-context context ast)
            (is (= 0 code))
            (is (string= (format nil "second~%") output))
            (is (equal '("second") (nreverse foreground-calls)))
            (is (equal '("first" nil nil) spawned))))))))

(test source-sequence-amp-spawns-background-pipeline-and-continues
  "source runs the pipeline before & asynchronously and continues with the next command."
  (let ((context (make-test-builtins-context))
        (foreground-calls nil)
        (spawned nil))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-pipeline-async
         (lambda (commands &key redirects)
           (setf spawned (list (mapcar #'nshell.domain.parsing:command-node-command
                                       commands)
                               redirects))
           commands))
      (with-temporary-function
          ('nshell.application::execute-ast-in-context
           (lambda (_context ast)
             (declare (ignore _context))
             (let ((command (nshell.domain.parsing:command-node-command ast)))
               (push command foreground-calls)
               (values (format nil "~a~%" command) 0))))
        (let* ((pipeline (nshell.domain.parsing:make-pipeline-node
                          (list (nshell.domain.parsing:make-command-node "first" nil)
                                (nshell.domain.parsing:make-command-node "second" nil))))
               (ast (nshell.domain.parsing::make-sequence-node
                     (list pipeline
                           (nshell.domain.parsing:make-command-node "third" nil))
                     (list :amp))))
          (multiple-value-bind (output code)
              (nshell.application::%execute-sequence-node-in-context context ast)
            (is (= 0 code))
            (is (string= (format nil "third~%") output))
            (is (equal '("third") (nreverse foreground-calls)))
              (is (equal '(("first" "second") (nil nil)) spawned))))))))

(test source-sequence-amp-registers-background-command-job
  "source registers background commands so jobs can report them."
  (let ((context (make-test-builtins-context))
        (process :background-process))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-async
         (lambda (command args &key redirects)
           (declare (ignore command args redirects))
           process))
      (with-temporary-function
          ('nshell.application::%background-process-pid
           (lambda (proc)
             (when (eq proc process)
               4321)))
        (with-temporary-function
            ('nshell.application::execute-ast-in-context
             (lambda (_context ast)
               (declare (ignore _context))
               (values (format nil "~a~%"
                               (nshell.domain.parsing:command-node-command ast))
                       0)))
          (let ((ast (nshell.domain.parsing::make-sequence-node
                      (list (nshell.domain.parsing:make-command-node
                             "first" (list "arg"))
                            (nshell.domain.parsing:make-command-node "second" nil))
                      (list :amp))))
            (multiple-value-bind (output code)
                (nshell.application::%execute-sequence-node-in-context context ast)
              (is (= 0 code))
              (is (string= (format nil "second~%") output))
              (let* ((entries (collect-monitor-entries
                               (nshell.application:shell-context-job-monitor
                                context)))
                     (entry (first entries))
                     (job-id (car entry))
                     (job (cdr entry)))
                (is (= 1 (length entries)))
                (is (equal '(4321) (nshell.domain.execution:job-pids job)))
                (is (= 4321 (nshell.domain.execution:job-pgid job)))
                (is (nshell.domain.execution:job-background-p job))
                (is (eq :running (nshell.domain.execution:job-state job)))
                (is (string= "first arg"
                             (nshell.domain.execution:job-command-display-string
                              job)))
                (is (eq process
                        (gethash job-id
                                 (nshell.application:shell-context-process-registry
                                  context))))))))))))

(test source-sequence-amp-registers-background-pipeline-job
  "source registers background pipelines with every spawned process."
  (let ((context (make-test-builtins-context))
        (processes '(:left-process :right-process)))
    (with-temporary-function
        ('nshell.infrastructure.acl:spawn-pipeline-async
         (lambda (commands &key redirects)
           (declare (ignore commands redirects))
           processes))
      (with-temporary-function
          ('nshell.application::%background-process-pid
           (lambda (proc)
             (case proc
               (:left-process 4321)
               (:right-process 4322))))
        (with-temporary-function
            ('nshell.application::execute-ast-in-context
             (lambda (_context ast)
               (declare (ignore _context))
               (values (format nil "~a~%"
                               (nshell.domain.parsing:command-node-command ast))
                       0)))
           (let* ((pipeline (nshell.domain.parsing:make-pipeline-node
                            (list (nshell.domain.parsing:make-command-node
                                   "first" (list "left"))
                                  (nshell.domain.parsing:make-command-node
                                   "second" (list "right")))))
                 (ast (nshell.domain.parsing::make-sequence-node
                       (list pipeline
                             (nshell.domain.parsing:make-command-node
                              "third" nil))
                       (list :amp))))
            (multiple-value-bind (output code)
                (nshell.application::%execute-sequence-node-in-context context ast)
              (is (= 0 code))
              (is (string= (format nil "third~%") output))
              (let* ((entries (collect-monitor-entries
                               (nshell.application:shell-context-job-monitor
                                context)))
                     (entry (first entries))
                     (job-id (car entry))
                     (job (cdr entry)))
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
                        (gethash job-id
                                 (nshell.application:shell-context-process-registry
                                  context))))))))))))

(test comment-or-blank-source-line-p-skips-empty-and-hash-lines
  "comment-or-blank-source-line-p returns true for blank lines, comments, and shebangs."
  (flet ((cbp (line) (nshell.application::%comment-or-blank-source-line-p line)))
    (is (cbp ""))
    (is (cbp "  "))
    (is (cbp "# a comment"))
    (is (cbp "#!/usr/bin/env nshell"))
    (is (not (cbp "echo hello")))
    (is (not (cbp "x=1")))))

(test function-start-p-detects-function-keyword-and-returns-name
  "function-start-p returns the function name when a line starts with 'function NAME'."
  (flet ((fst (line) (nshell.application::%function-start-p line)))
    (is (string= "greet" (fst "function greet")))
    (is (string= "greet" (fst "function greet --description 'say hi'")))
    (is (null             (fst "echo hello")))
    (is (null             (fst "# function foo")))))

(test source-definition-line-depth-delta-counts-opening-and-end-keywords
  "source-definition-line-depth-delta returns +1 for block openers, -1 for end."
  (flet ((delta (line) (nshell.application::%source-definition-line-depth-delta line)))
    (is (= +1 (delta "if true")))
    (is (= +1 (delta "for x in a b")))
    (is (= -1 (delta "end")))
    (is (=  0 (delta "echo hello")))
    (is (=  0 (delta "")))))
