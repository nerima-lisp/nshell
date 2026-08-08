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
        :output-null t))))
