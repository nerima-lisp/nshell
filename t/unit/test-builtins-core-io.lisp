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

  (it "printf-preserves-case-sensitive-numeric-conversions"
    "printf keeps lower- and upper-case hexadecimal conversions distinct."
    (with-builtins-context (context)
      (assert-builtin-call (context "printf" '("%#x%#X" "42" "42"))
        :code 0
        :output "0x2A0X2A")))

  (it "pwd-returns-current-working-directory"
    "pwd returns the context cwd as a string with a trailing newline."
    (with-temporary-function
        ('host-kit:getcwd (lambda () #p"/tmp/"))
      (with-builtins-context (context)
        (assert-builtin-call (context "pwd" nil)
          :code 0
          :output (format nil "/tmp/~%")))))

  (it "cd-with-no-args-uses-home"
    "cd with no arguments resolves HOME from the shell context environment."
    (with-builtins-context-environment
        (context (make-test-builtins-context)
                 ("HOME" "/home/test"))
      (let ((seen-path nil))
        (with-temporary-functions
            (('host-kit:getcwd (lambda () #p"/tmp/"))
             ('host-kit:chdir (lambda (path)
                                (setf seen-path path))))
          (assert-builtin-call (context "cd" nil)
            :code 0
            :output-null t)
          (expect "/home/test" :to-equal seen-path)))))

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
    (with-temporary-function
        ('host-kit:chdir (lambda (path) (declare (ignore path)) t))
      (with-builtins-context (context)
        (assert-builtin-call (context "cd" '("/tmp"))
          :code 0
          :output-null t))))

  (it "cd-rejects-multiple-directories"
    "cd reports usage when more than one directory argument is supplied."
    (with-builtins-context (context)
      (assert-builtin-call (context "cd" '("/tmp" "/work"))
        :code 1
        :contains '("usage: cd" "cd [directory]"))))

  (it "cd-dash-fails-without-oldpwd"
    "cd - reports a clear error when OLDPWD is unset."
    (with-builtins-context (context)
      (setf (nshell.application:shell-context-environment context)
            (nshell.domain.environment:env-unset
             (nshell.application:shell-context-environment context)
             "OLDPWD"))
      (assert-builtin-call (context "cd" '("-"))
        :code 1
        :contains '("cd:" "OLDPWD is not set"))))

  (it "cd-maintains-pwd-and-oldpwd-and-supports-dash"
    "cd updates PWD and OLDPWD, and cd - returns to the previous directory."
    (with-builtins-context-environment
        (context (make-test-builtins-context)
                 ("HOME" "/home/test"))
      (let ((current-cwd "/tmp/"))
        (with-temporary-functions
            (('host-kit:getcwd (lambda () (pathname current-cwd)))
             ('host-kit:chdir (lambda (path)
                                (setf current-cwd (namestring (pathname path))))))
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
            (expect "/work" :to-equal (nshell.domain.environment:env-get environment "OLDPWD")))))))

  (it "cd-surfaces-filesystem-errors"
    "cd returns exit 1 and an error message when :chdir signals an error."
    (with-temporary-function
        ('host-kit:chdir (lambda (path)
                           (declare (ignore path))
                           (error "no such directory")))
      (let ((context (make-test-builtins-context)))
        (assert-builtin-call (context "cd" '("/missing"))
          :code 1
          :contains '("cd:" "no such directory")))))

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

  (it "runtime-boundary-uses-host-filesystem"
    "Runtime path helpers use the host boundary without session state."
    (let ((context (make-test-shell-context)))
      (expect (nshell.application::%stat-path "/missing") :to-be-null)
      (expect (nshell.application::%path-directory-p
               context
               (host-kit:temporary-directory))
              :to-be-truthy))
    (with-test-source-file (source nil)
      (write-test-lines source '("runtime fallback"))
      (let ((context (make-test-shell-context)))
        (expect (nshell.application::%path-file-p context source)
                :to-be-truthy)))))

  (it "runtime-boundary-distinguishes-files-and-directories"
    "Runtime path helpers classify actual host filesystem entries."
    (with-test-source-file (source nil)
      (write-test-lines source '("runtime fallback"))
      (let ((context (make-test-shell-context)))
        (expect (nshell.application::%path-file-p context source)
                :to-be-truthy)
        (expect (nshell.application::%path-file-p
                 context
                 (host-kit:temporary-directory))
                :to-be-falsy)
        (expect (nshell.application::%path-directory-p
                 context
                 (host-kit:temporary-directory))
                :to-be-truthy))))
