(in-package #:nshell/test)

(describe "builtin-tests"
  (it "echo-prints-args-joined-by-spaces"
    "echo prints all arguments separated by spaces followed by a newline."
    (with-builtins-context (context)
      (assert-builtin-call (context "echo" '("hello" "world"))
        :code 0
        :output (format nil "hello world~%"))
      (assert-builtin-call (context "echo" '("single"))
        :code 0
        :output (format nil "single~%"))
      (assert-builtin-call (context "echo" nil)
        :code 0
        :output (format nil "~%"))))

  (it "printf-formats-common-conversions-and-repeats"
    "printf expands escapes, formats values, and reuses a format for remaining arguments."
    (with-builtins-context (context)
      (assert-builtin-call (context "printf" '("%s=%d\\n" "answer" "7"))
        :code 0
        :output (format nil "answer=7~%"))
      (assert-builtin-call (context "printf" '("%05d" "7"))
        :code 0
        :output "00007")
      (assert-builtin-call (context "printf" '("%s" "a" "b"))
        :code 0
        :output "ab")
      (assert-builtin-call (context "printf" '("literal\\n"))
        :code 0
        :output (format nil "literal~%"))))

  (it "pwd-returns-current-working-directory"
    "pwd returns the context cwd as a string with a trailing newline."
    (with-builtins-context (context)
      (assert-builtin-call (context "pwd" nil)
        :code 0
        :output (format nil "/tmp/~%"))))

  (it "cd-with-no-args-uses-home"
    "cd with no arguments resolves HOME from the shell context environment."
    (with-builtins-context-environment
        (context (make-test-builtins-context)
                 ("HOME" "/home/test"))
      (let* ((original-fns (nshell.application:shell-context-filesystem-fns context))
             (seen-path nil))
        (setf (nshell.application:shell-context-filesystem-fns context)
              (list* :chdir (lambda (path)
                              (setf seen-path path))
                     original-fns))
        (assert-builtin-call (context "cd" nil)
          :code 0
          :output-null t)
        (expect "/home/test" :to-equal seen-path))))

  (it "cd-with-no-args-fails-without-home"
    "cd with no arguments reports a clear error when HOME is unset."
    (with-builtins-context (context)
      (setf (nshell.application:shell-context-environment context)
            (nshell.domain.environment:env-unset
             (nshell.application:shell-context-environment context)
             "HOME"))
      (assert-builtin-call (context "cd" nil)
        :code 1
        :contains '("cd:" "HOME is not set"))))

  (it "cd-with-valid-path-succeeds"
    "cd with a path arg delegates to :chdir and exits 0 on success."
    (with-builtins-context (context)
      (assert-builtin-call (context "cd" '("/tmp"))
        :code 0
        :output-null t)))

  (it "cd-maintains-pwd-and-oldpwd-and-supports-dash"
    "cd updates PWD and OLDPWD, and cd - returns to the previous directory."
    (with-builtins-context-environment
        (context (make-test-builtins-context)
                 ("HOME" "/home/test"))
      (let* ((current-cwd "/tmp/")
             (original-fns (nshell.application:shell-context-filesystem-fns context)))
        (setf (nshell.application:shell-context-filesystem-fns context)
              (list* :cwd (lambda () (pathname current-cwd))
                     :chdir (lambda (path)
                              (setf current-cwd (namestring (pathname path))))
                     original-fns))
        (assert-builtin-call (context "cd" '("/work"))
          :code 0
          :output-null t)
        (let ((environment (nshell.application:shell-context-environment context)))
          (expect "/work" :to-equal (nshell.domain.environment:env-get environment "PWD"))
          (expect "/tmp/" :to-equal (nshell.domain.environment:env-get environment "OLDPWD")))
        (assert-builtin-call (context "cd" '("-"))
          :code 0
          :output (format nil "/tmp/~%"))
        (let ((environment (nshell.application:shell-context-environment context)))
          (expect "/tmp/" :to-equal (nshell.domain.environment:env-get environment "PWD"))
          (expect "/work" :to-equal (nshell.domain.environment:env-get environment "OLDPWD"))))))

  (it "cd-surfaces-filesystem-errors"
    "cd returns exit 1 and an error message when :chdir signals an error."
    (let* ((context (make-test-builtins-context))
           (original-fns (nshell.application:shell-context-filesystem-fns context)))
      (setf (nshell.application:shell-context-filesystem-fns context)
            (list* :chdir (lambda (path)
                            (declare (ignore path))
                            (error "no such directory"))
                   original-fns))
      (assert-builtin-call (context "cd" '("/missing"))
        :code 1
        :contains '("cd:" "no such directory"))))

  (it "ls-lists-directory-contents"
    "ls emits one filename per line for each entry returned by :list-dir."
    (let* ((context (make-test-builtins-context))
           (original-fns (nshell.application:shell-context-filesystem-fns context)))
      (setf (nshell.application:shell-context-filesystem-fns context)
            (list* :list-dir (lambda (d)
                               (declare (ignore d))
                               (list #p"/opt/bin/foo" #p"/opt/bin/bar"))
                   original-fns))
      (assert-builtin-call (context "ls" nil)
        :code 0
        :output (format nil "foo~%bar~%"))))

  (it "ls-returns-exit-1-when-list-dir-errors"
    "ls returns exit 1 and an error message when :list-dir signals an error."
    (let* ((context (make-test-builtins-context))
           (original-fns (nshell.application:shell-context-filesystem-fns context)))
      (setf (nshell.application:shell-context-filesystem-fns context)
            (list* :list-dir (lambda (d)
                               (declare (ignore d))
                               (error "permission denied"))
                   original-fns))
      (assert-builtin-call (context "ls" nil)
        :code 1
        :contains '("ls:" "permission denied"))))

  (it "true-exits-zero-with-no-output"
    "true always returns exit code 0 and nil output regardless of arguments."
    (with-builtins-context (context)
      (assert-builtin-call (context "true" nil)
        :code 0
        :output-null t)
      (assert-builtin-call (context "true" '("ignored"))
        :code 0
        :output-null t)))

  (it "false-exits-one-with-no-output"
    "false always returns exit code 1 and nil output regardless of arguments."
    (with-builtins-context (context)
      (assert-builtin-call (context "false" nil)
        :code 1
        :output-null t)
      (assert-builtin-call (context "false" '("ignored"))
        :code 1
        :output-null t)))

  (it "runtime-adapters-report-missing-functions-and-use-host-fallbacks"
    "Runtime helpers report required adapter omissions and use documented host fallbacks."
    (let ((context (make-test-shell-context :filesystem-fns nil)))
      (expect (lambda () (nshell.application::%filesystem-fn context :stat))
              :to-throw 'error)
      (expect (nshell.application::%stat-path context "/missing") :to-be-null)
      (expect (nshell.application::%path-directory-p
               context
               (host-kit:temporary-directory))
              :to-be-truthy))
    (let ((context (make-test-shell-context :process-fns nil)))
      (expect (lambda () (nshell.application::%process-fn context :run-external))
              :to-throw 'error))
    (with-test-source-file (source nil)
      (write-test-lines source '("runtime fallback"))
      (let ((context
              (make-test-shell-context
               :filesystem-fns
               (list :stat
                     (lambda (path)
                       (declare (ignore path))
                       t)))))
        (expect (nshell.application::%path-file-p context source)
                :to-be-truthy)))))

  (it "runtime-adapters-select-optional-filesystem-predicates"
    "Optional file and directory predicates are used when supplied by the context."
    (let ((file-context
            (make-test-shell-context
             :filesystem-fns
             (list :file-exists-p
                   (lambda (path)
                     (declare (ignore path))
                     t))))
          (missing-file-context
            (make-test-shell-context
             :filesystem-fns
             (list :file-exists-p
                   (lambda (path)
                     (declare (ignore path))
                     nil))))
          (directory-context
            (make-test-shell-context
             :filesystem-fns
             (list :directory-exists-p
                   (lambda (path)
                     (declare (ignore path))
                     t))))
          (missing-directory-context
            (make-test-shell-context
             :filesystem-fns
             (list :directory-exists-p
                   (lambda (path)
                     (declare (ignore path))
                     nil))))
          (stat-missing-context
            (make-test-shell-context
             :filesystem-fns
             (list :stat
                   (lambda (path)
                     (declare (ignore path))
                     nil)))))
      (expect (nshell.application::%path-file-p file-context "/virtual/file")
              :to-be-truthy)
      (expect (nshell.application::%path-file-p missing-file-context "/virtual/file")
              :to-be-falsy)
      (expect (nshell.application::%path-directory-p directory-context "/virtual/dir")
              :to-be-truthy)
      (expect (nshell.application::%path-directory-p missing-directory-context "/virtual/dir")
              :to-be-falsy)
      (expect (nshell.application::%path-file-p stat-missing-context "/virtual/file")
              :to-be-falsy)))
