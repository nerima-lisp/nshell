(in-package #:nshell/test)
(in-suite e2e-tests)

(test e2e-pipeline-smoke
  "Verify pipeline execution via spawn-pipeline"
  (let* ((cmd1 (nshell.domain.parsing:make-command-node "echo" '("hello")))
         (pipe (nshell.domain.parsing:make-pipeline-node (list cmd1)))
         (exit (nshell.infrastructure.acl:spawn-pipeline
                (nshell.domain.parsing:pipeline-node-commands pipe))))
    (is (= 0 exit))))

(test e2e-pipeline-redirections-apply-per-stage
  "Pipeline stages should apply their own input and output redirects."
  (with-repl-test-state
    (let* ((root (merge-pathnames (format nil "nshell-pipeline-redir-~d/"
                                          (random 1000000))
                                  (uiop:temporary-directory)))
           (input (merge-pathnames "input.txt" root))
           (output (merge-pathnames "output.txt" root))
           (content "pipeline redirection"))
      (unwind-protect
           (progn
             (ensure-directories-exist root)
             (with-open-file (stream input
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-string content stream))
             (let ((line (format nil "cat < ~a | cat > ~a"
                                 (namestring input)
                                 (namestring output))))
               (with-complete-command-line (result ast line)
                (multiple-value-bind (output-text code)
                    (call-repl-execute-ast ast)
                  (declare (ignore output-text))
                  (is (= 0 code)))
                (is (probe-file output))
                 (with-open-file (stream output :direction :input)
                   (let ((actual (make-string (file-length stream))))
                     (read-sequence actual stream)
                     (is (string= content actual)))))))
        (handler-case
            (when (probe-file root)
              (uiop:delete-directory-tree root :validate t))
          (error ()))))))

(test e2e-syntax-error-stops-before-execution
  "A parse error prevents command execution."
  (with-parsed-command-line (result "| echo should-not-run")
    (is (not (nshell.domain.parsing:parse-complete-p result)))
    (is (eq :missing-command
            (nshell.domain.parsing:parse-diagnostic-kind
             (first (nshell.domain.parsing:parse-errors result)))))))

(test e2e-external-command
  "External command execution returns correct exit code."
  (is (= 0 (nshell.infrastructure.acl:run-external "true" '())))
  (is (not (= 0 (nshell.infrastructure.acl:run-external "false" '())))))
