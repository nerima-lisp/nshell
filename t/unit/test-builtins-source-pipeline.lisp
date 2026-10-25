(in-package #:nshell/test)

(defun %make-source-pipeline-test-filesystem (&rest extra-executable-paths)
  (%make-test-builtins-filesystem
   :files (append '("/bin/echo" "/bin/sh" "/tmp/file.txt")
                  extra-executable-paths)))

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

  (it "source-pipeline-feeds-sexp-function-output-to-read"
    "source lets S-expression-defined functions participate in pipelines."
    (with-builtins-source
        (output code context
                (list "(define-shell-function produce () (echo function-value))"
                      "(| (produce) (read captured))"))
      (expect "" :to-equal output)
      (expect 0 :to-equal code)
      (expect "function-value"
              :to-equal
              (nshell.domain.environment:env-get
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

  (it "source-pipeline-redirects-sexp-function-output"
    "source redirects output from S-expression-defined functions."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-function-redirect")
      (let ((target (merge-pathnames "function.txt" root)))
        (write-test-lines
         source
         (list "(define-shell-function produce () (echo function-redirected))"
               (format nil "(produce > ~s)" (namestring target))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect "" :to-equal output)
          (expect 0 :to-equal code)
          (expect "function-redirected" :to-equal
                  (read-test-file-line target))))))

  (it "source-pipeline-redirects-internal-stderr-to-file"
    "source applies a S-expression command redirect to internal command stderr."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-stderr-redirect")
      (let ((target (merge-pathnames "stderr.txt" root)))
        (write-test-lines source
                          (list (format nil "(errcmd 2> ~s)" (namestring target))))
        (setf (nshell.application:shell-context-filesystem context)
              (%make-source-pipeline-test-filesystem "/bin/errcmd"))
        (with-stubbed-command-builtin
            (("errcmd"
              (write-line "stderr-line" *error-output*)
              (values (format nil "stdout-line~%") 7)))
          (multiple-value-bind (output code)
              (call-source-file context source)
            (expect 7 :to-equal code)
            (expect (format nil "stdout-line~%") :to-equal output)
            (expect "stderr-line" :to-equal (read-test-file-line target)))))))

  (it "source-pipeline-ampersand-redirects-internal-stdout-and-stderr"
    "source applies a S-expression command redirect to internal stdout and stderr."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-amp-redirect")
      (let ((target (merge-pathnames "combined.txt" root)))
        (write-test-lines source
                          (list (format nil "(errcmd &> ~s)" (namestring target))))
        (setf (nshell.application:shell-context-filesystem context)
              (%make-source-pipeline-test-filesystem "/bin/errcmd"))
        (with-stubbed-command-builtin
            (("errcmd"
              (write-line "stderr-line" *error-output*)
              (values (format nil "stdout-line~%") 7)))
          (multiple-value-bind (output code)
              (call-source-file context source)
            (let ((contents (host-kit:read-file-string target)))
              (expect 7 :to-equal code)
              (expect "" :to-equal output)
              (expect (search "stdout-line" contents) :to-be-truthy)
              (expect (search "stderr-line" contents) :to-be-truthy)))))))

  (it "source-pipeline-redirects-internal-stderr-to-stdout"
    "source preserves S-expression redirect order when stdout is redirected before stderr is merged."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-stderr-to-stdout")
      (let ((target (merge-pathnames "combined.txt" root)))
        (write-test-lines source
                          (list (format nil "(errcmd > ~s 2>& 1)" (namestring target))))
        (setf (nshell.application:shell-context-filesystem context)
              (%make-source-pipeline-test-filesystem "/bin/errcmd"))
        (with-stubbed-command-builtin
            (("errcmd"
              (write-line "stderr-line" *error-output*)
              (values (format nil "stdout-line~%") 7)))
          (multiple-value-bind (output code)
              (call-source-file context source)
            (let ((contents (host-kit:read-file-string target)))
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
  (it "source-pipeline-file-backed-heredoc-keeps-following-command-source-map"
    "source preserves reader spans after a file-backed here-document continuation."
    (with-builtins-source-tree
        (context root source :prefix "nshell-test-source-heredoc-map")
      (write-test-lines
       source
       (list "read captured << EOF"
             "inline-doc"
             "EOF"
             "read following <<< after"))
      (expect 0 :to-equal
              (nth-value 1 (call-source-file context source)))
      (expect "inline-doc" :to-equal
              (nshell.domain.environment:env-get
               (nshell.application:shell-context-environment context)
               "captured"))
      (expect "after" :to-equal
              (nshell.domain.environment:env-get
               (nshell.application:shell-context-environment context)
               "following"))))

  (it "source-pipeline-input-redirect-overrides-pipe-input"
    "source applies an input redirect to a S-expression pipeline stage."
    (with-builtins-source-tree (context root source :prefix "nshell-test-source-input-redirect")
      (let ((input (merge-pathnames "input.txt" root)))
        (write-test-lines input (list "from-file"))
        (write-test-lines source
                          (list (format nil "(| (echo from-pipe) (read captured < ~s))"
                                        (namestring input))))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect "" :to-equal output)
          (expect 0 :to-equal code)
          (expect "from-file" :to-equal (nshell.domain.environment:env-get
                        (nshell.application:shell-context-environment context)
                        "captured"))))))

  (it "source-pipeline-uses-source-strategy-for-external-pipelines"
    "source keeps S-expression external pipelines on the source execution path when strategy is :cps."
    (skip-in-sandbox "executes /bin/echo and /bin/cat"
      (let ((context (make-test-builtins-context)))
        (setf (nshell.application:shell-context-execution-strategy context) :cps)
        (with-temporary-function
            ('nshell.infrastructure.acl:spawn-pipeline
             (lambda (&rest _args)
               (declare (ignore _args))
               (error "spawn-pipeline should not run for :cps")))
          (with-called-source (output code context
                                      (list "(| (/bin/echo cps-strategy) (/bin/cat))"))
            (expect 0 :to-equal code)
            (expect (format nil "cps-strategy~%") :to-equal output))))))

  (it "source-pipeline-uses-os-pipes-strategy-for-external-pipelines"
    "source dispatches S-expression external pipelines to spawn-pipeline for :os-pipes."
    (let ((context (make-test-builtins-context :filesystem (%make-source-pipeline-test-filesystem "/bin/cat")))
          (called nil)
          (command-count nil)
          (captured-redirects nil))
      (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (commands &key redirects pipefail-p &allow-other-keys)
             (declare (ignore pipefail-p))
             (setf called t
                   command-count (length commands)
                   captured-redirects redirects)
             (format t "spawned-path~%")
             (values 37 '(0 37))))
        (with-called-source (output code context
                                    (list "(| (/bin/echo \"os-pipes-strategy\") (/bin/cat))"))
          (expect (null called) :to-be-falsy)
          (expect 2 :to-equal command-count)
          (expect (listp captured-redirects) :to-be-truthy)
          (expect 37 :to-equal code)
          (expect (format nil "spawned-path~%") :to-equal output)))))

  (it "source-pipeline-keeps-internal-commands-on-source-path-under-os-pipes"
    "source keeps S-expression pipelines with internal commands on the source path under :os-pipes."
    (let ((context (make-test-builtins-context)))
      (setf (nshell.application:shell-context-execution-strategy context) :os-pipes)
      (with-temporary-function
          ('nshell.infrastructure.acl:spawn-pipeline
           (lambda (&rest _args)
             (declare (ignore _args))
             (error "spawn-pipeline should not run for internal commands")))
        (with-called-source (output code context
                                    (list "(| (echo internal-value) (read captured))"))
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect "internal-value" :to-equal (nshell.domain.environment:env-get
                        (nshell.application:shell-context-environment context)
                        "captured")))))))

(describe "pipeline-execution-strategy-contract-tests"
  (it "source-pipeline-required-p-covers-strategy-and-command-kind"
    "The dispatch policy selects CPS for explicit CPS and internal stages."
    (let* ((context (make-test-builtins-context))
           (internal (nshell.domain.parsing:make-command-node "echo" nil))
           (external (nshell.domain.parsing:make-command-node "/bin/echo" nil)))
      (flet ((required-p (strategy commands)
               (setf (nshell.application:shell-context-execution-strategy context)
                     strategy)
               (nshell.application::%source-pipeline-required-p context commands)))
        (expect t :to-equal (required-p :cps (list external)))
        (expect t :to-equal (required-p :os-pipes (list internal)))
        (expect nil :to-equal (required-p :os-pipes (list external)))))))
