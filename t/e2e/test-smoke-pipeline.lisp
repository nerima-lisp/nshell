(in-package #:nshell/test)

(describe "e2e-tests"
  (it "e2e-pipeline-smoke"
    "Verify pipeline execution via spawn-pipeline"
    (let* ((cmd1 (nshell.domain.parsing:make-command-node "echo" '("hello")))
           (pipe (nshell.domain.parsing:make-pipeline-node (list cmd1)))
           (exit (nshell.infrastructure.acl:spawn-pipeline
                  (nshell.domain.parsing:pipeline-node-commands pipe))))
      (expect 0 :to-equal exit)))

  (it "e2e-pipeline-redirections-apply-per-stage"
    "Pipeline stages should apply their own input and output redirects."
    (with-repl-test-state
      (let* ((root (merge-pathnames (format nil "nshell-pipeline-redir-~d/"
                                            (get-internal-real-time))
                                    (host-kit:temporary-directory)))
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
                    (expect 0 :to-equal code))
                  (expect (wait-for-file-content (namestring output) content)
                          :to-be-truthy))))
          (handler-case
              (when (probe-file root)
                (host-kit:delete-directory-tree root :validate t))
            (error ()))))))

  (it "e2e-syntax-error-stops-before-execution"
    "A parse error prevents command execution."
    (with-parsed-command-line (result "| echo should-not-run")
      (expect (nshell.domain.parsing:parse-complete-p result) :to-be-falsy)
      (expect :missing-command :to-be (nshell.domain.parsing:parse-diagnostic-kind
               (first (nshell.domain.parsing:parse-errors result))))))

  (it "e2e-external-command"
    "External command execution returns correct exit code."
    (expect 0 :to-equal (nshell.infrastructure.acl:run-external "true" '()))
    (expect (= 0 (nshell.infrastructure.acl:run-external "false" '())) :to-be-falsy)))
