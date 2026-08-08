(in-package #:nshell/test)

(describe "builtin-tests"
  (it "source-pipeline-feeds-builtin-output-to-read"
    "source executes builtin pipeline stages in the current shell context."
    (with-builtins-source (output code context
                                   '("echo piped-value | read captured"))
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect "piped-value" :to-equal (nshell.domain.environment:env-get
                    (nshell.application:shell-context-environment context)
                    "captured"))))

  (it "source-pipeline-feeds-function-output-to-read"
    "source lets fish-style functions participate in pipelines."
    (with-builtins-source (output code context
                                   '("function produce"
                                     "echo function-value"
                                     "end"
                                     "produce | read captured"))
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect "function-value" :to-equal (nshell.domain.environment:env-get
                    (nshell.application:shell-context-environment context)
                    "captured"))))

  (it "source-pipeline-redirects-builtin-output"
    "source supports redirection on builtin pipeline stages."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-redirect")
      (let ((target (merge-pathnames "out.txt" root)))
        (write-test-lines source
                          (list (format nil "echo redirected > ~a"
                                        (namestring target))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect "" :to-equal output)
          (expect 0 :to-equal code)
          (expect "redirected" :to-equal (read-test-file-line target))))))

  (it "source-pipeline-redirects-function-output"
    "source redirects fish-style function output from pipeline stages."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-function-redirect")
      (let ((target (merge-pathnames "function.txt" root)))
        (write-test-lines source
                          (list "function produce"
                                "echo function-redirected"
                                "end"
                                (format nil "produce > ~a" (namestring target))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect "" :to-equal output)
          (expect 0 :to-equal code)
          (expect "function-redirected" :to-equal (read-test-file-line target))))))

  (it "source-pipeline-redirects-internal-stderr-to-file"
    "source applies 2> to stderr written by internal commands."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-stderr-redirect")
      (let ((target (merge-pathnames "stderr.txt" root)))
        (write-test-lines source
                          (list (format nil "errcmd 2> ~a" (namestring target))))
        (with-stubbed-command-executor
            (("errcmd"
              (write-line "stderr-line" *error-output*)
              (values (format nil "stdout-line~%") 7)))
          (multiple-value-bind (output code)
              (call-source-file context source)
            (expect 7 :to-equal code)
            (expect (format nil "stdout-line~%") :to-equal output)
            (expect "stderr-line" :to-equal (read-test-file-line target)))))))

  (it "source-pipeline-ampersand-redirects-internal-stdout-and-stderr"
    "source applies &> to both stdout and stderr from internal commands."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-amp-redirect")
      (let ((target (merge-pathnames "combined.txt" root)))
        (write-test-lines source
                          (list (format nil "errcmd &> ~a" (namestring target))))
        (with-stubbed-command-executor
            (("errcmd"
              (write-line "stderr-line" *error-output*)
              (values (format nil "stdout-line~%") 7)))
          (multiple-value-bind (output code)
              (call-source-file context source)
            (let ((contents (uiop:read-file-string target)))
              (expect 7 :to-equal code)
              (expect "" :to-equal output)
              (expect (search "stdout-line" contents) :to-be-truthy)
              (expect (search "stderr-line" contents) :to-be-truthy)))))))

  (it "source-pipeline-redirects-internal-stderr-to-stdout"
    "source applies 2>&1 after stdout has been redirected."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-stderr-to-stdout")
      (let ((target (merge-pathnames "combined.txt" root)))
        (write-test-lines source
                          (list (format nil "errcmd > ~a 2>&1" (namestring target))))
        (with-stubbed-command-executor
            (("errcmd"
              (write-line "stderr-line" *error-output*)
              (values (format nil "stdout-line~%") 7)))
          (multiple-value-bind (output code)
              (call-source-file context source)
            (let ((contents (uiop:read-file-string target)))
              (expect 7 :to-equal code)
              (expect "" :to-equal output)
              (expect (search "stdout-line" contents) :to-be-truthy)
              (expect (search "stderr-line" contents) :to-be-truthy)))))))

  (it "source-pipeline-here-string-feeds-builtin-stdin"
    "source applies here-strings to builtin pipeline stages."
    (with-builtins-source (output code context
                                   '("read captured <<< inline-value"))
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect "inline-value" :to-equal (nshell.domain.environment:env-get
                    (nshell.application:shell-context-environment context)
                    "captured"))))

  (it "source-pipeline-here-document-feeds-builtin-stdin"
    "source accumulates here-document bodies before executing the command."
    (with-builtins-source (output code context
                                   '("read captured << EOF"
                                     "inline-doc"
                                     "EOF"))
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect "inline-doc" :to-equal (nshell.domain.environment:env-get
                    (nshell.application:shell-context-environment context)
                    "captured"))))
  (it "source-pipeline-tabbed-here-document-feeds-builtin-stdin"
    "source strips leading tabs from here-document bodies before executing the command."
    (with-builtins-source (output code context
                                   (list "read captured <<- EOF"
                                         (format nil "~cinline-doc" #\Tab)
                                         (format nil "~cEOF" #\Tab)))
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect "inline-doc" :to-equal (nshell.domain.environment:env-get
                    (nshell.application:shell-context-environment context)
                    "captured"))))

  (it "source-pipeline-here-document-continues-after-delimiter"
    "source leaves commands after a here-document delimiter for normal execution."
    (with-builtins-source (output code context
                                   '("read captured << EOF"
                                     "inline-doc"
                                     "EOF"
                                     "echo after"))
      (expect (format nil "after~%") :to-equal output)
      (expect 0 :to-equal code)
      (expect "inline-doc" :to-equal (nshell.domain.environment:env-get
                    (nshell.application:shell-context-environment context)
                    "captured"))))

  (it "source-pipeline-input-redirect-overrides-pipe-input"
    "source applies input redirects on builtin pipeline stages."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-input-redirect")
      (let ((input (merge-pathnames "input.txt" root)))
        (write-test-lines input '("from-file"))
        (write-test-lines source
                          (list (format nil "echo from-pipe | read captured < ~a"
                                        (namestring input))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect "" :to-equal output)
          (expect 0 :to-equal code)
          (expect "from-file" :to-equal (nshell.domain.environment:env-get
                        (nshell.application:shell-context-environment context)
                        "captured"))))))

  (it "source-pipeline-uses-source-strategy-for-external-pipelines"
    "source keeps external pipelines on the source execution path when strategy is :cps."
    (skip-in-sandbox "executes /bin/echo and /bin/cat"
    (let ((context (make-test-builtins-context)))
      (setf (nshell.application:shell-context-execution-strategy context) :cps)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (&rest _args)
             (declare (ignore _args))
             (error "spawn-pipeline should not run for :cps")))
        (with-called-source (output code context
                                    '("/bin/echo cps-strategy | /bin/cat"))
          (expect 0 :to-equal code)
          (expect (format nil "cps-strategy~%") :to-equal output))))))

  (it "source-pipeline-uses-os-pipes-strategy-for-external-pipelines"
    "source dispatches external pipelines to spawn-pipeline when strategy is :os-pipes."
    (let ((context (make-test-builtins-context))
          (called nil)
          (command-count nil)
          (captured-redirects nil))
      (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (commands &key redirects)
             (setf called t
                   command-count (length commands)
                   captured-redirects redirects)
             (format t "spawned-path~%")
             37))
        (with-called-source (output code context
                                    '("/bin/echo os-pipes-strategy | /bin/cat"))
          (expect (null called) :to-be-falsy)
          (expect 2 :to-equal command-count)
          (expect (listp captured-redirects) :to-be-truthy)
          (expect 37 :to-equal code)
          (expect (format nil "spawned-path~%") :to-equal output)))))

  (it "source-pipeline-keeps-internal-commands-on-source-path-under-os-pipes"
    "source still executes pipelines with internal commands through the source path even when strategy is :os-pipes."
    (let ((context (make-test-builtins-context)))
      (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (&rest _args)
             (declare (ignore _args))
             (error "spawn-pipeline should not run for internal commands")))
        (with-called-source (output code context
                                    '("echo internal-value | read captured"))
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect "internal-value" :to-equal (nshell.domain.environment:env-get
                        (nshell.application:shell-context-environment context)
                        "captured")))))))
