(in-package #:nshell/test)
(in-suite builtin-tests)

(test source-pipeline-feeds-builtin-output-to-read
  "source executes builtin pipeline stages in the current shell context."
  (with-builtins-source (output code context
                                 '("echo piped-value | read captured"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "piped-value"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-feeds-function-output-to-read
  "source lets fish-style functions participate in pipelines."
  (with-builtins-source (output code context
                                 '("function produce"
                                   "echo function-value"
                                   "end"
                                   "produce | read captured"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "function-value"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-redirects-builtin-output
  "source supports redirection on builtin pipeline stages."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-redirect")
    (let ((target (merge-pathnames "out.txt" root)))
      (write-test-lines source
                        (list (format nil "echo redirected > ~a"
                                      (namestring target))))
      (multiple-value-bind (output code)
          (call-source-file context source)
        (is (string= "" output))
        (is (= 0 code))
        (is (string= "redirected" (read-test-file-line target)))))))

(test source-pipeline-redirects-function-output
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
        (is (string= "" output))
        (is (= 0 code))
        (is (string= "function-redirected"
                     (read-test-file-line target)))))))

(test source-pipeline-redirects-internal-stderr-to-file
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
          (is (= 7 code))
          (is (string= (format nil "stdout-line~%") output))
          (is (string= "stderr-line" (read-test-file-line target))))))))

(test source-pipeline-ampersand-redirects-internal-stdout-and-stderr
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
            (is (= 7 code))
            (is (string= "" output))
            (is (search "stdout-line" contents))
            (is (search "stderr-line" contents))))))))

(test source-pipeline-redirects-internal-stderr-to-stdout
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
            (is (= 7 code))
            (is (string= "" output))
            (is (search "stdout-line" contents))
            (is (search "stderr-line" contents))))))))

(test source-pipeline-here-string-feeds-builtin-stdin
  "source applies here-strings to builtin pipeline stages."
  (with-builtins-source (output code context
                                 '("read captured <<< inline-value"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "inline-value"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-here-document-feeds-builtin-stdin
  "source accumulates here-document bodies before executing the command."
  (with-builtins-source (output code context
                                 '("read captured << EOF"
                                   "inline-doc"
                                   "EOF"))
    (is (string= "" output))
    (is (= 0 code))
    (is (string= "inline-doc"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-here-document-continues-after-delimiter
  "source leaves commands after a here-document delimiter for normal execution."
  (with-builtins-source (output code context
                                 '("read captured << EOF"
                                   "inline-doc"
                                   "EOF"
                                   "echo after"))
    (is (string= (format nil "after~%") output))
    (is (= 0 code))
    (is (string= "inline-doc"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "captured")))))

(test source-pipeline-input-redirect-overrides-pipe-input
  "source applies input redirects on builtin pipeline stages."
  (with-builtins-source-tree (context root source :prefix "nshell-test-source-input-redirect")
    (let ((input (merge-pathnames "input.txt" root)))
      (write-test-lines input '("from-file"))
      (write-test-lines source
                        (list (format nil "echo from-pipe | read captured < ~a"
                                      (namestring input))))
      (multiple-value-bind (output code)
          (call-source-file context source)
        (is (string= "" output))
        (is (= 0 code))
        (is (string= "from-file"
                     (nshell.domain.environment:env-get
                      (nshell.application:shell-context-environment context)
                      "captured")))))))

(test source-pipeline-uses-source-strategy-for-external-pipelines
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
        (is (= 0 code))
        (is (string= (format nil "cps-strategy~%") output)))))))

(test source-pipeline-uses-os-pipes-strategy-for-external-pipelines
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
        (is (not (null called)))
        (is (= 2 command-count))
        (is (listp captured-redirects))
        (is (= 37 code))
        (is (string= (format nil "spawned-path~%") output))))))

(test source-pipeline-keeps-internal-commands-on-source-path-under-os-pipes
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
        (is (= 0 code))
        (is (string= "" output))
        (is (string= "internal-value"
                     (nshell.domain.environment:env-get
                      (nshell.application:shell-context-environment context)
                      "captured")))))))

(test pbt-source-pipeline-keeps-external-only-pipelines-on-source-path-under-cps
  "Generated external-only pipelines stay on the source path when strategy is :cps."
  (skip-in-sandbox "executes /bin/echo and /bin/cat"
  (check-property (:trials 50)
      ((payload (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text))
    (let ((context (make-test-builtins-context))
          (spawned nil))
      (setf (nshell.application:shell-context-execution-strategy context) :cps)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (&rest _args)
             (declare (ignore _args))
             (setf spawned t)
             (error "spawn-pipeline should not run for :cps")))
        (with-called-source (output code context
                                (list (format nil "/bin/echo ~a | /bin/cat" payload)))
          (is (not spawned))
          (is (= 0 code))
          (is (string= (format nil "~a~%" payload) output))))))))

(test pbt-source-pipeline-routes-external-only-pipelines-to-spawn-pipeline-under-os-pipes
  "Generated external-only pipelines route through spawn-pipeline when strategy is :os-pipes."
  (check-property (:trials 50)
      ((payload (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text))
    (let ((context (make-test-builtins-context))
          (called nil))
      (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (commands &key redirects)
             (setf called t)
             (is (= 2 (length commands)))
             (is (listp redirects))
             (format t "spawned-path~%")
             37))
        (with-called-source (output code context
                                (list (format nil "/bin/echo ~a | /bin/cat" payload)))
          (is (not (null called)))
          (is (= 37 code))
          (is (search "spawned-path" output)))))))
