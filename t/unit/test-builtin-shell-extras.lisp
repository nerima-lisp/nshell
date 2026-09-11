(in-package #:nshell/test)

(describe "builtin-math-tests"
  (it "math-evaluates-the-four-basic-operators-with-standard-precedence"
    "* and / bind tighter than + and -, and parentheses override precedence."
    (with-builtins-context (context)
      (assert-builtin-cases (context "math")
        (("1+2") :code 0 :output (format nil "3~%"))
        (("5-2") :code 0 :output (format nil "3~%"))
        (("2*3+4") :code 0 :output (format nil "10~%"))
        (("2+3*4") :code 0 :output (format nil "14~%"))
        (("(2+3)*4") :code 0 :output (format nil "20~%")))))

  (it "math-supports-exponent-modulo-and-unary-minus"
    "^ is right-associative exponentiation (not $((...))'s bitwise XOR), and
unary minus binds looser than ^ but tighter than the following * / %."
    (with-builtins-context (context)
      (assert-builtin-cases (context "math")
        (("2^10") :code 0 :output (format nil "1024~%"))
        (("10 % 3") :code 0 :output (format nil "1~%"))
        (("-3+5") :code 0 :output (format nil "2~%"))
        (("-2^2") :code 0 :output (format nil "-4~%"))
        (("2^-1") :code 0 :output (format nil "0.5~%")))))

  (it "math-formats-decimals-with-up-to-six-fraction-digits-trimmed"
    "Non-integral results render as decimals, trailing zeros trimmed, exact
rational arithmetic underneath so 10/4 never picks up floating-point noise."
    (with-builtins-context (context)
      (assert-builtin-cases (context "math")
        (("10 / 4") :code 0 :output (format nil "2.5~%"))
        (("1 / 3") :code 0 :output (format nil "0.333333~%"))
        (("1 / 8") :code 0 :output (format nil "0.125~%")))))

  (it "math-reports-division-by-zero-distinctly"
    "Division or modulo by zero is its own error, not folded into a parse error."
    (with-builtins-context (context)
      (assert-builtin-call (context "math" '("1/0"))
        :code 1
        :output (format nil "math: division by zero~%"))
      (assert-builtin-call (context "math" '("1%0"))
        :code 1
        :output (format nil "math: division by zero~%"))))

  (it "math-reports-parse-errors"
    "An incomplete expression or an unrecognized character is a parse error, exit 2."
    (with-builtins-context (context)
      (assert-builtin-call (context "math" '("1+"))
        :code 2
        :contains '("math: error:"))
      (assert-builtin-call (context "math" '("1+@"))
        :code 2
        :contains '("math: error:"))))

  (it "math-requires-an-expression"
    "math with no arguments reports usage rather than evaluating nothing."
    (with-builtins-context (context)
      (assert-builtin-call (context "math" nil)
        :code 2
        :contains '("math: usage:")))))

(describe "builtin-directory-stack-tests"
  (it "pushd-and-popd-round-trip-the-directory-stack"
    "pushd DIR changes directory and remembers the old one; popd reverses it."
    (let ((nshell.application::*directory-stack* nil)
          (nshell.application::*directory-history* nil)
          (nshell.application::*directory-history-index* 0)
          (current-cwd "/start"))
      (with-temporary-functions
          (('host-kit:getcwd (lambda () (pathname current-cwd)))
           ('host-kit:chdir (lambda (path) (setf current-cwd (namestring (pathname path))))))
        (with-builtins-context (context)
          (assert-builtin-call (context "pushd" '("/a"))
            :code 0 :output-null t)
          (expect "/a" :to-equal current-cwd)
          (assert-builtin-call (context "dirs" nil)
            :code 0 :output (format nil "/a /start~%"))
          (assert-builtin-call (context "popd" nil)
            :code 0 :output-null t)
          (expect "/start" :to-equal current-cwd)
          (assert-builtin-call (context "popd" nil)
            :code 1 :contains '("popd: directory stack empty"))))))

  (it "pushd-with-no-argument-swaps-current-directory-with-stack-top"
    "A bare pushd swaps the current directory with the top of the stack."
    (let ((nshell.application::*directory-stack* nil)
          (nshell.application::*directory-history* nil)
          (nshell.application::*directory-history-index* 0)
          (current-cwd "/start"))
      (with-temporary-functions
          (('host-kit:getcwd (lambda () (pathname current-cwd)))
           ('host-kit:chdir (lambda (path) (setf current-cwd (namestring (pathname path))))))
        (with-builtins-context (context)
          (assert-builtin-call (context "pushd" '("/a"))
            :code 0 :output-null t)
          (assert-builtin-call (context "pushd" nil)
            :code 0 :output-null t)
          (expect "/start" :to-equal current-cwd)
          (assert-builtin-call (context "dirs" nil)
            :code 0 :output (format nil "/start /a~%"))))))

  (it "pushd-with-no-argument-and-an-empty-stack-fails"
    "pushd with no argument and nothing on the stack has nowhere to swap to."
    (let ((nshell.application::*directory-stack* nil))
      (with-builtins-context (context)
        (assert-builtin-call (context "pushd" nil)
          :code 1 :contains '("pushd: no other directory")))))

  (it "pushd-popd-and-dirs-reject-extra-arguments"
    "Each builtin's own usage form is reported before any directory is touched."
    (with-builtins-context (context)
      (assert-builtin-call (context "pushd" '("/a" "/b"))
        :code 2 :contains '("usage: pushd"))
      (assert-builtin-call (context "popd" '("extra"))
        :code 2 :contains '("usage: popd"))
      (assert-builtin-call (context "dirs" '("extra"))
        :code 2 :contains '("usage: dirs"))))

  (it "dirs-collapses-the-home-prefix-to-a-tilde"
    "dirs shortens any stack entry under $HOME the way the prompt does."
    (let ((nshell.application::*directory-stack* nil)
          (current-cwd "/home/test/project"))
      (with-temporary-function
          ('host-kit:getcwd (lambda () (pathname current-cwd)))
        (with-builtins-context-environment
            (context (make-test-builtins-context) ("HOME" "/home/test"))
          (assert-builtin-call (context "dirs" nil)
            :code 0 :output (format nil "~~/project~%"))))))

  (it "prevd-and-nextd-navigate-directory-history-without-touching-the-pushd-stack"
    "prevd/nextd move a pointer through every directory visited via pushd/popd."
    (let ((nshell.application::*directory-stack* nil)
          (nshell.application::*directory-history* nil)
          (nshell.application::*directory-history-index* 0)
          (current-cwd "/start"))
      (with-temporary-functions
          (('host-kit:getcwd (lambda () (pathname current-cwd)))
           ('host-kit:chdir (lambda (path) (setf current-cwd (namestring (pathname path))))))
        (with-builtins-context (context)
          (assert-builtin-call (context "pushd" '("/a")) :code 0 :output-null t)
          (assert-builtin-call (context "pushd" '("/b")) :code 0 :output-null t)
          (expect "/b" :to-equal current-cwd)
          (assert-builtin-call (context "prevd" nil) :code 0 :output-null t)
          (expect "/a" :to-equal current-cwd)
          (assert-builtin-call (context "prevd" nil) :code 0 :output-null t)
          (expect "/start" :to-equal current-cwd)
          (assert-builtin-call (context "prevd" nil)
            :code 1 :contains '("prevd: no previous directory"))
          (assert-builtin-call (context "nextd" '("2")) :code 0 :output-null t)
          (expect "/b" :to-equal current-cwd)
          (assert-builtin-call (context "nextd" nil)
            :code 1 :contains '("nextd: no next directory")))))))

(describe "builtin-functions-tests"
  (it "functions-with-no-arguments-lists-names-only-sorted"
    "Bare `functions` lists just the names, one per line, unlike `function`'s
full-definition listing."
    (with-builtins-context (context)
      (let ((table (nshell.application:shell-context-function-table context)))
        (setf (gethash "greet" table) '("echo hi")
              (gethash "bye" table) '("echo bye")))
      (assert-builtin-call (context "functions" nil)
        :code 0
        :output (format nil "bye~%greet~%"))))

  (it "functions-with-a-name-prints-its-reconstructed-source"
    "functions NAME shows the source file (when known) and the function body."
    (with-builtins-context (context)
      (let ((table (nshell.application:shell-context-function-table context))
            (source-table (nshell.application:shell-context-function-source-table context)))
        (setf (gethash "greet" table) '("echo hi")
              (gethash "greet" source-table) "/tmp/greet.fish"))
      (multiple-value-bind (output code) (call-builtin context "functions" '("greet"))
        (expect 0 :to-equal code)
        (expect (search "# Defined in /tmp/greet.fish" output) :to-be-truthy)
        (expect (search "function greet" output) :to-be-truthy)
        (expect (search "echo hi" output) :to-be-truthy)
        (expect (search "end" output) :to-be-truthy))
      (assert-builtin-call (context "functions" '("missing"))
        :code 1
        :contains '("functions: missing: not a function"))))

  (it "functions-erase-removes-a-defined-function"
    "functions -e NAME erases the function; without a name it reports usage."
    (with-builtins-context (context)
      (let ((table (nshell.application:shell-context-function-table context)))
        (setf (gethash "greet" table) '("echo hi")))
      (assert-builtin-call (context "functions" '("-e" "greet"))
        :code 0 :output-null t)
      (expect (nth-value 1 (gethash "greet"
                                    (nshell.application:shell-context-function-table context)))
              :to-be-falsy)
      (assert-builtin-call (context "functions" '("-e"))
        :code 2
        :contains '("functions: -e requires a name"))))

  (it "builtin-bypasses-functions-and-aliases"
    "builtin NAME dispatches straight to the registered handler, ignoring any
function of the same name."
    (with-builtins-context (context)
      (let ((table (nshell.application:shell-context-function-table context)))
        (setf (gethash "echo" table) '("echo shadowed")))
      (assert-builtin-call (context "builtin" '("echo" "real"))
        :code 0 :output (format nil "real~%"))
      (assert-builtin-call (context "builtin" '("not-a-builtin"))
        :code 1 :contains '("builtin: not-a-builtin: not a builtin"))
      (assert-builtin-call (context "builtin" nil)
        :code 2 :contains '("usage: builtin")))))

(describe "builtin-and-or-tests"
  (it "and-runs-its-command-only-after-a-success-status"
    "and executes its command when $status is 0, and otherwise passes that
prior nonzero status through unchanged without running anything."
    (with-builtins-context (context)
      (setf (nshell.application:shell-context-last-exit-code context) 0)
      (assert-builtin-call (context "and" '("echo" "ran"))
        :code 0 :output (format nil "ran~%"))
      (setf (nshell.application:shell-context-last-exit-code context) 7)
      (assert-builtin-call (context "and" '("echo" "should-not-run"))
        :code 7 :output-null t)
      (assert-builtin-call (context "and" nil)
        :code 2 :contains '("usage: and"))))

  (it "or-runs-its-command-only-after-a-failure-status"
    "or executes its command when $status is nonzero, and otherwise passes
that prior success status through unchanged without running anything."
    (with-builtins-context (context)
      (setf (nshell.application:shell-context-last-exit-code context) 1)
      (assert-builtin-call (context "or" '("echo" "ran"))
        :code 0 :output (format nil "ran~%"))
      (setf (nshell.application:shell-context-last-exit-code context) 0)
      (assert-builtin-call (context "or" '("echo" "should-not-run"))
        :code 0 :output-null t)
      (assert-builtin-call (context "or" nil)
        :code 2 :contains '("usage: or")))))

(describe "builtin-history-nil-tests"
  (it "history-subcommands-treat-a-nil-history-as-empty-rather-than-crashing"
    "Batch mode (`nshell -c ...`) builds a context with no history object;
every subcommand must degrade to empty results instead of signalling."
    (let ((context (make-test-shell-context :history nil)))
      (assert-builtin-call (context "history" nil)
        :code 0 :output-null t)
      (assert-builtin-call (context "history" '("search" "git"))
        :code 0 :output-null t)
      (assert-builtin-call (context "history" '("delete" "git" "status"))
        :code 0 :output (format nil "0~%"))
      (assert-builtin-call (context "history" '("clear"))
        :code 0 :output-null t)
      (assert-builtin-call (context "history" '("size"))
        :code 0 :output (format nil "0~%"))
      (assert-builtin-call (context "history" '("search"))
        :code 1 :contains '("history: usage:")))))

(describe "builtin-complete-line-tests"
  (it "complete-C-lists-completions-for-the-given-line-one-per-line"
    "complete -C LINE is the scriptable completion entry point: it prints
candidates, one per line, and exits 0."
    (with-builtins-context (context)
      (multiple-value-bind (output code) (call-builtin context "complete" '("-C" "ech"))
        (expect 0 :to-equal code)
        (expect (search "echo" output) :to-be-truthy))))

  (it "complete-C-falls-back-instead-of-crashing-on-a-nil-knowledge-base"
    "Batch mode never seeds a knowledge base; -C must still exit 0 -- falling
back to PATH/filesystem candidates -- rather than signalling on a NIL kb."
    (let ((context (make-test-shell-context :knowledge-base nil)))
      (assert-builtin-call (context "complete" '("-C" "ech"))
        :code 0)))

  (it "complete-C-requires-a-line-argument"
    "complete -C with no line reports a usage error rather than crashing."
    (with-builtins-context (context)
      (assert-builtin-call (context "complete" '("-C"))
        :code 2
        :contains '("complete: -C requires a line"))))

  (it "complete-c-lazily-creates-a-knowledge-base-when-the-session-has-none"
    "complete -c ... (registering a completion) must not crash in batch mode
either, where the session's knowledge base starts out NIL."
    (let ((context (make-test-shell-context :knowledge-base nil)))
      (assert-builtin-call (context "complete" '("-c" "deploy" "-f" "--dry-run"))
        :code 0 :output-null t)
      (expect (nshell.application:shell-context-knowledge-base context) :to-be-truthy)
      (assert-builtin-call (context "complete" '("-c" "deploy" "--erase"))
        :code 0 :output-null t))))

(describe "batch-session-seeding-tests"
  (it "batch-state-seeds-status-and-the-completion-knowledge-base"
    "A batch session starts with $status at 0 and a knowledge base, so scripts can
read $status and call complete -C without an interactive session."
    (with-repl-test-state
      (nshell.presentation::%initialize-batch-state)
      (expect "0" :to-equal
              (nshell.domain.environment:env-get nshell.presentation::*environment* "status"))
      (expect "0" :to-equal
              (nshell.domain.environment:env-get nshell.presentation::*environment* "?"))
      (expect (nshell.domain.completion:kb-command-present-p nshell.presentation::*kb* "echo")
              :to-be-truthy)
      (expect (nshell.domain.configuration:config-p nshell.presentation::*config*)
              :to-be-truthy)
      (expect (functionp nshell.application:*theme-apply-handler*) :to-be-truthy)
      (expect (functionp nshell.application:*bind-table-handler*) :to-be-truthy)
      (expect (functionp nshell.application:*prompt-format-apply-handler*)
              :to-be-truthy))))

(describe "directory-listing-cache-tests"
  (it "repeated-listings-of-an-unchanged-directory-read-the-directory-once"
    "Completion lists a directory per keystroke, so the second read of an
unchanged directory must come from the cache."
    (let ((reads 0))
      (nshell.infrastructure.acl:clear-directory-listing-cache)
      (with-rebound-function (host-kit:directory-files
                              (lambda (directory)
                                (declare (ignore directory))
                                (incf reads)
                                (list "a.txt")))
        (expect '("a.txt") :to-equal
                (nshell.infrastructure.acl::cached-directory-files "/tmp/"))
        (expect '("a.txt") :to-equal
                (nshell.infrastructure.acl::cached-directory-files "/tmp/"))
        (expect 1 :to-equal reads))))

  (it "a-changed-directory-write-date-invalidates-the-entry"
    (let ((reads 0)
          (stamp 1))
      (nshell.infrastructure.acl:clear-directory-listing-cache)
      (with-rebound-function (host-kit:directory-files
                              (lambda (directory)
                                (declare (ignore directory))
                                (incf reads)
                                (list "a.txt")))
        (with-rebound-function (nshell.infrastructure.acl::%directory-listing-stamp
                                (lambda (directory)
                                  (declare (ignore directory))
                                  stamp))
          (nshell.infrastructure.acl::cached-directory-files "/tmp/")
          (setf stamp 2)
          (nshell.infrastructure.acl::cached-directory-files "/tmp/")
          (expect 2 :to-equal reads)))))

  (it "an-unreadable-directory-name-bypasses-the-cache"
    (let ((reads 0))
      (nshell.infrastructure.acl:clear-directory-listing-cache)
      (with-rebound-function (host-kit:subdirectories
                              (lambda (directory)
                                (declare (ignore directory))
                                (incf reads)
                                nil))
        (with-rebound-function (nshell.infrastructure.acl::%directory-listing-cache-key
                                (lambda (kind directory)
                                  (declare (ignore directory))
                                  (cons kind nil)))
          (nshell.infrastructure.acl::cached-subdirectories "/tmp/")
          (nshell.infrastructure.acl::cached-subdirectories "/tmp/")
          (expect 2 :to-equal reads))))))
