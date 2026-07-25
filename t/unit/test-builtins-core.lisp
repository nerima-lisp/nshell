(in-package #:nshell/test)

(describe "builtin-tests"
  (it "type-and-which-resolve-builtins-aliases-functions-and-path"
    "type reports aliases, functions, builtins, and commands discovered through PATH."
    (with-builtins-context (context)
      (call-builtin context "alias" '("ll" "ls" "-l"))
      (call-builtin context "function" '("hi" "echo" "hello" "end"))
      (call-builtin context "abbr" '("-a" "gs" "git status"))
      (assert-builtin-call (context "type" '("echo" "ll" "hi" "gs" "/bin/echo" "missing"))
        :code 0
        :contains '("echo is a shell builtin"
                    "ll is an alias for ls -l"
                    "hi is a function"
                    "function hi"
                    "echo hello"
                    "gs is an abbreviation for git status"
                    "/bin/echo is /bin/echo"
                    "missing: not found"))
      (assert-builtin-call (context "type" '("-q" "echo" "missing"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "type" '("-q" "missing"))
        :code 1
        :output-null t)
      (assert-builtin-call (context "type" '("-t" "echo" "ll" "hi" "gs" "/bin/echo"))
        :code 0
        :contains '("builtin" "alias" "function" "abbreviation" "file"))
      (assert-builtin-call (context "type" '("-s" "hi"))
        :code 0
        :output "hi is a function
")
      (assert-builtin-call (context "which" '("echo" "missing"))
        :code 1
        :contains '("shell built-in command" "no missing in PATH"))))

  (it "builtin-registry-exposes-executable-builtins-at-load-time"
    "lookup-builtin returns the executable builtin handlers immediately after load."
    (dolist (name '("echo" "exit" "ls" "pwd" "string" "type" "not"))
      (expect (nshell.application:lookup-builtin name) :to-be-truthy)))

  (it "builtin-registry-covers-the-canonical-builtin-catalog"
    "Every builtin listed in the canonical catalog should be registered at load time."
    (dolist (entry nshell.domain.completion::+builtin-command-catalog+)
      (let ((command (nshell.domain.completion::%catalog-command-entry-command entry)))
        (expect (nshell.application:lookup-builtin command) :to-be-truthy))))

  (it "exit-stops-the-current-shell-context"
    "exit mutates only the current application shell context running flag."
    (with-builtins-context (context)
      (setf (nshell.application:shell-context-running context) t)
      (assert-builtin-call (context "exit" nil) :code 0 :output-null t)
      (expect (nshell.application:shell-context-running context) :to-be-falsy)))

  (it "type-colorizes-only-the-function-definition-branch"
    "type --color colors the function definition block without changing short output."
    (with-builtins-context (context)
      (call-builtin context "function" '("hi" "echo" "hello" "end"))
      (multiple-value-bind (output code)
          (call-builtin context "type" '("--color" "hi"))
        (expect 0 :to-equal code)
        (expect (search "hi is a function" output) :to-be-truthy)
        (expect (search "echo" output) :to-be-truthy)
        (expect (search "hello" output) :to-be-truthy)
        (expect (search (string (code-char 27)) output) :to-be-truthy))
      (assert-builtin-call (context "type" '("--short" "--color" "hi"))
        :code 0
        :output "hi is a function
")))

  (it "type-p-returns-source-path-or-builtin-status-for-sourced-functions"
    "type -p returns the source path for sourced functions, builtin status for builtins, and no output for inline shadowed names."
    (with-builtins-context (context)
      (with-test-source-file (source nil)
        (write-test-lines source
                          '("function sourced-hi"
                            "  echo hello"
                            "end"))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect 0 :to-equal code)
          (expect "" :to-equal output))
        (assert-builtin-call (context "type" '("-p" "sourced-hi"))
          :code 0
          :output (format nil "~a~%" (namestring source)))
        (assert-builtin-call (context "type" '("-p" "echo"))
          :code 0
          :output (format nil "echo is a builtin~%"))
        (assert-builtin-call (context "type" '("-t" "sourced-hi"))
          :code 0
          :output (format nil "function~%"))
        (call-builtin context "function" '("sourced-hi" "echo" "updated" "end"))
        (assert-builtin-call (context "type" '("-p" "sourced-hi"))
          :code 0
          :output-empty t))))

  (it "type-f-and-p-prefer-path-when-functions-shadow-commands"
    "type -f still reports PATH entries when a shell function shadows the command, while type -P prints only the path."
    (let ((context (make-test-builtins-context
                    :path "/opt/bin"
                    :files '("/opt/bin/shadowed")
                    :dirs '("/opt/bin")
                    :function-table (make-hash-table :test #'equal))))
      (call-builtin context "function" '("shadowed" "echo" "shadowed" "end"))
      (assert-builtin-call (context "type" '("-f" "shadowed"))
        :code 0
        :output "shadowed is /opt/bin/shadowed
")
      (assert-builtin-call (context "type" '("-P" "shadowed"))
        :code 0
        :output "/opt/bin/shadowed
")))

  (it "type-a-enumerates-all-path-hits"
    "type -a lists every executable match discovered through PATH."
    (let ((context (make-test-builtins-context
                    :files '("/bin/echo" "/usr/bin/echo")
                    :dirs '("/bin" "/usr/bin"))))
      (assert-builtin-call (context "type" '("-a" "echo"))
        :code 0
        :output "echo is a shell builtin
echo is /bin/echo
echo is /usr/bin/echo
")))

  (it "help-reports-which-using-canonical-placeholder-style"
    "help keeps which aligned with the canonical NAME placeholder style."
    (with-builtins-context (context)
      (assert-builtin-call (context "help" '("which"))
        :code 0
        :output "which NAME [...] - show command path
")))

  (it "help-reports-type-using-canonical-placeholder-style"
    "help keeps type aligned with the canonical OPTIONS/NAME placeholder style."
    (with-builtins-context (context)
      (assert-builtin-call (context "help" '("type"))
        :code 0
        :output "type [OPTIONS] NAME [...] - show command type
")))

  (it "help-reports-overview-specific-help-and-missing-entries"
    "help prints the builtin overview, command-specific help, and missing-entry errors."
    (with-builtins-context (context)
      (assert-builtin-call (context "help" nil)
        :code 0
        :contains '("nshell builtin commands:" "echo [string ...] - print arguments"
                    "help [command] - show help"
                    "history [search [--prefix|--contains|--exact|--case-sensitive] query | delete command | clear | size] - show and manage command history"
                    "contains [-i|--index] string [values...] - test whether a value is present"))
        (assert-builtin-call (context "help" '("string"))
          :code 0
          :output "string collect|length|lower|upper|join|split|replace|match|repeat|sub|trim ...; string replace|match|repeat|sub|trim ... - manipulate strings
")
        (assert-builtin-call (context "help" '("missing"))
          :code 1
          :contains '("help: no help for missing"))))

  (it "test-and-bracket-cover-file-directory-and-string-predicates"
    "test/[ support -f, -d, =, -n, and -z predicates."
    (with-builtins-context (context)
      (assert-builtin-call (context "test" '("-f" "/tmp/file.txt")) :code 0)
      (assert-builtin-call (context "test" '("-f" "/tmp")) :code 1)
      (assert-builtin-call (context "test" '("-d" "/tmp")) :code 0)
      (assert-builtin-call (context "test" '("abc" "=" "abc")) :code 0)
      (assert-builtin-call (context "test" '("abc" "=" "def")) :code 1)
      (assert-builtin-call (context "test" '("-n" "abc")) :code 0)
      (assert-builtin-call (context "test" '("-z" "")) :code 0)
      (assert-builtin-call (context "[" '("abc" "=" "abc" "]")) :code 0)
      (assert-builtin-call (context "[" '("abc" "=" "abc")) :code 2)))

  (it "not-inverts-command-status-and-preserves-output"
    "not dispatches a command and flips only its exit status."
    (with-builtins-context (context)
      (assert-builtin-call (context "not" '("false")) :code 0 :output-null t)
      (assert-builtin-call (context "not" '("true")) :code 1 :output-null t)
      (assert-builtin-call (context "not" '("test" "-f" "/tmp/file.txt"))
        :code 1
        :output-null t)
      (assert-builtin-call (context "not" '("test" "-f" "/tmp/missing"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "not" '("echo" "hello"))
        :code 1
        :output (format nil "hello~%"))
      (assert-builtin-call (context "not" nil)
        :code 2
        :contains '("usage"))))

  (it "not-inverts-external-runner-status"
    "not uses the process adapter for non-builtin commands."
    (let* ((seen nil)
           (context (make-test-builtins-context
                     :external-runner
                     (lambda (command args)
                       (setf seen (list command args))
                       7))))
      (multiple-value-bind (output code)
          (call-builtin context "not" '("external-cmd" "one" "two"))
        (expect output :to-be-null)
        (expect 0 :to-equal code)
        (expect '("external-cmd" ("one" "two")) :to-equal seen))))

  (it "not-preserves-captured-external-output"
    "not preserves captured external command output while flipping its status."
    (let* ((seen nil)
           (context (make-test-builtins-context
                     :external-capture-runner
                     (lambda (command args)
                       (setf seen (list command args))
                       (values (format nil "captured output~%") 0)))))
      (multiple-value-bind (output code)
          (call-builtin context "not" '("external-cmd" "one" "two"))
        (expect (format nil "captured output~%") :to-equal output)
        (expect 1 :to-equal code)
        (expect '("external-cmd" ("one" "two")) :to-equal seen))))

  (it "fg-and-bg-builtins-propagate-status-and-missing-job-errors"
    "fg/bg builtins return job status and missing-job failures."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (job (make-test-job 0 "sleep"))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job)))
      (let ((nshell.application:*job-monitor*
              (nshell.domain.job-control:make-job-monitor)))
        (assert-builtin-call (context "bg" (list (format nil "~d" job-id)))
          :code 0
          :output-null t)
        (assert-builtin-call (context "fg" (list (format nil "~d" job-id)))
          :code 0
          :output-null t)))
    (let ((context (make-test-builtins-context))
          (monitor (nshell.domain.job-control:make-job-monitor)))
      (let ((nshell.application:*job-monitor* monitor))
        (assert-builtin-call (context "bg" '("42"))
          :code 1
          :output (format nil "bg: no such job: 42~%"))
        (assert-builtin-call (context "fg" '("42"))
          :code 1
          :output (format nil "fg: no such job: 42~%")))))

  (it "jobs-and-disown-builtins-use-context-monitor"
    "jobs/disown builtins operate on the shell context monitor, not the global monitor."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (job (make-test-job 0 "sleep" :args '("10")))
           (job-id (nshell.domain.job-control:monitor-add-job monitor job)))
      (let ((nshell.application:*job-monitor*
              (nshell.domain.job-control:make-job-monitor)))
        (assert-builtin-call (context "jobs" nil)
          :code 0
          :contains (list (format nil "[~d]" job-id) "Created" "sleep 10"))
        (assert-builtin-call (context "disown" (list (format nil "~d" job-id)))
          :code 0
          :output-null t)
        (expect (nshell.domain.job-control:monitor-find-job monitor job-id) :to-be-null)
        (assert-builtin-call (context "disown" (list (format nil "~d" job-id)))
          :code 1
          :output (format nil "disown: job [~d] not found~%" job-id)))))
  (it "type-option-p-recognizes-dash-prefixed-strings"
    "type-option-p returns true only for strings starting with a dash of length >= 2."
    (flet ((opt-p (s) (nshell.application::%type-option-p s)))
      (expect (opt-p "-t") :to-be-truthy)
      (expect (opt-p "--all") :to-be-truthy)
      (expect (opt-p "--color=auto") :to-be-truthy)
      (expect (opt-p "word") :to-be-falsy)
      (expect (opt-p "") :to-be-falsy)
      (expect (opt-p "-") :to-be-falsy)))

  (it "type-option-kind-maps-known-flags"
    "type-option-kind returns the correct keyword for each recognized flag."
    (flet ((kind (s) (nshell.application::%type-option-kind s)))
      (expect :all :to-be (kind "-a"))
      (expect :all :to-be (kind "--all"))
      (expect :short :to-be (kind "-s"))
      (expect :no-functions :to-be (kind "-f"))
      (expect :color :to-be (kind "--color"))
      (expect :color :to-be (kind "--color=always"))
      (expect :query :to-be (kind "-q"))
      (expect :path :to-be (kind "-p"))
      (expect :force-path :to-be (kind "-P"))
      (expect :type :to-be (kind "-t"))
      (expect (kind "--bogus") :to-be-null)))

  (it "type-color-enabled-p-accepts-known-color-values"
    "type-color-enabled-p is true for --color and --color=always/auto, false for --color=never."
    (flet ((col (s) (nshell.application::%type-color-enabled-p s)))
      (expect (col "--color") :to-be-truthy)
      (expect (col "--color=always") :to-be-truthy)
      (expect (col "--color=auto") :to-be-truthy)
      (expect (col "--color=never") :to-be-falsy)
      (expect (col "--bogus") :to-be-falsy)))

  (it "string-lines-splits-on-newlines"
    "string-lines returns a list of lines; each newline creates one split."
    (flet ((lines (text) (nshell.application::%string-lines text)))
      (expect '("hello") :to-equal (lines "hello"))
      (expect '("a" "b" "c") :to-equal (lines (format nil "a~%b~%c")))
      (expect '("" "b") :to-equal (lines (format nil "~%b")))
      ;; collect happens before while guard: "" yields ("") and "\n" yields ("" "")
      (expect '("") :to-equal (lines ""))
      (expect '("" "") :to-equal (lines (format nil "~%")))
      (expect '("a" "" "") :to-equal (lines (format nil "a~%~%"))))))
