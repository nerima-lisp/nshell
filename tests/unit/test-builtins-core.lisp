(in-package #:nshell/test)

(in-suite builtin-tests)

(test type-and-which-resolve-builtins-aliases-functions-and-path
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

(test builtin-registry-exposes-executable-builtins-at-load-time
  "lookup-builtin returns the executable builtin handlers immediately after load."
  (dolist (name '("echo" "exit" "ls" "pwd" "string" "type" "not"))
    (is (nshell.application:lookup-builtin name))))

(test builtin-registry-covers-the-canonical-builtin-catalog
  "Every builtin listed in the canonical catalog should be registered at load time."
  (dolist (entry nshell.domain.completion::+builtin-command-catalog+)
    (let ((command (getf entry :command)))
      (is (nshell.application:lookup-builtin command)
          command))))

(test type-colorizes-only-the-function-definition-branch
  "type --color colors the function definition block without changing short output."
  (with-builtins-context (context)
    (call-builtin context "function" '("hi" "echo" "hello" "end"))
    (multiple-value-bind (output code)
        (call-builtin context "type" '("--color" "hi"))
      (is (= 0 code))
      (is (search "hi is a function" output))
      (is (search "echo" output))
      (is (search "hello" output))
      (is (search (string (code-char 27)) output)))
    (assert-builtin-call (context "type" '("--short" "--color" "hi"))
      :code 0
      :output "hi is a function
")))

(test type-p-returns-source-path-or-builtin-status-for-sourced-functions
  "type -p returns the source path for sourced functions, builtin status for builtins, and no output for inline shadowed names."
  (with-builtins-context (context)
    (with-test-source-file (source nil)
      (write-test-lines source
                        '("function sourced-hi"
                          "  echo hello"
                          "end"))
      (multiple-value-bind (output code)
          (call-source-file context source)
        (is (= 0 code))
        (is (string= "" output)))
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

(test type-f-and-p-prefer-path-when-functions-shadow-commands
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

(test type-a-enumerates-all-path-hits
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

(test help-reports-which-using-canonical-placeholder-style
  "help keeps which aligned with the canonical NAME placeholder style."
  (with-builtins-context (context)
    (assert-builtin-call (context "help" '("which"))
      :code 0
      :output "which NAME [...] - show command path
")))

(test help-reports-type-using-canonical-placeholder-style
  "help keeps type aligned with the canonical OPTIONS/NAME placeholder style."
  (with-builtins-context (context)
    (assert-builtin-call (context "help" '("type"))
      :code 0
      :output "type [OPTIONS] NAME [...] - show command type
")))

(test help-reports-overview-specific-help-and-missing-entries
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

(test test-and-bracket-cover-file-directory-and-string-predicates
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

(test not-inverts-command-status-and-preserves-output
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

(test not-inverts-external-runner-status
  "not uses the process adapter for non-builtin commands."
  (let* ((seen nil)
         (context (make-test-builtins-context
                   :external-runner
                   (lambda (command args)
                     (setf seen (list command args))
                     7))))
    (multiple-value-bind (output code)
        (call-builtin context "not" '("external-cmd" "one" "two"))
      (is (null output))
      (is (= 0 code))
      (is (equal '("external-cmd" ("one" "two")) seen)))))

(test not-preserves-captured-external-output
  "not preserves captured external command output while flipping its status."
  (let* ((seen nil)
         (context (make-test-builtins-context
                   :external-capture-runner
                   (lambda (command args)
                     (setf seen (list command args))
                     (values (format nil "captured output~%") 0)))))
    (multiple-value-bind (output code)
        (call-builtin context "not" '("external-cmd" "one" "two"))
      (is (string= (format nil "captured output~%") output))
      (is (= 1 code))
      (is (equal '("external-cmd" ("one" "two")) seen)))))

(test fg-and-bg-builtins-propagate-status-and-missing-job-errors
  "fg/bg builtins return job status and surface missing-job failures."
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
      (assert-builtin-call-prints (context "bg" '("42"))
        :code 1
        :output-null t
        :stdout-contains '("bg: no such job: 42"))
      (assert-builtin-call-prints (context "fg" '("42"))
        :code 1
        :output-null t
        :stdout-contains '("fg: no such job: 42")))))

(test jobs-and-disown-builtins-use-context-monitor
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
      (is (null (nshell.domain.job-control:monitor-find-job monitor job-id)))
      (assert-builtin-call (context "disown" (list (format nil "~d" job-id)))
        :code 1
        :output (format nil "disown: job [~d] not found~%" job-id)))))

(test count-reports-number-of-arguments
  "count prints the argument count, exiting 0 when non-empty and 1 when empty."
  (with-builtins-context (context)
    (assert-builtin-call (context "count" '("a" "b" "c"))
      :code 0
      :output (format nil "3~%"))
    (assert-builtin-call (context "count" '("only"))
      :code 0
      :output (format nil "1~%"))
    (assert-builtin-call (context "count" '())
      :code 1
      :output (format nil "0~%"))))

(test seq-prints-integer-sequences
  "seq prints integer ranges with optional first/step, one per line."
  (with-builtins-context (context)
    (assert-builtin-call (context "seq" '("3"))
      :code 0 :output (format nil "1~%2~%3~%"))
    (assert-builtin-call (context "seq" '("2" "5"))
      :code 0 :output (format nil "2~%3~%4~%5~%"))
    (assert-builtin-call (context "seq" '("2" "2" "8"))
      :code 0 :output (format nil "2~%4~%6~%8~%"))
    (assert-builtin-call (context "seq" '("3" "-1" "1"))
      :code 0 :output (format nil "3~%2~%1~%"))
    ;; descending with positive step yields nothing
    (assert-builtin-call (context "seq" '("5" "1"))
      :code 0 :output-null t)
    (assert-builtin-call (context "seq" '("1" "0" "5"))
      :code 2 :output (format nil "seq: STEP must not be zero~%"))
    (assert-builtin-call (context "seq" '("x"))
      :code 2 :output (format nil "seq: arguments must be integers~%"))))

(test contains-tests-membership-without-output
  "contains returns success when the needle appears in the value list."
  (with-builtins-context (context)
    (assert-builtin-call (context "contains" '("needle" "hay" "needle" "stack"))
      :code 0
      :output-null t)
    (assert-builtin-call (context "contains" '("needle" "hay" "stack"))
      :code 1
      :output-null t)
    (assert-builtin-call (context "contains" '("--" "-n" "-x" "-n"))
      :code 0
      :output-null t)))

(test contains-index-prints-matching-value-positions
  "contains -i prints 1-based positions within the searched values."
  (with-builtins-context (context)
    (assert-builtin-call (context "contains"
                           '("--index" "needle" "hay" "needle" "needle"))
      :code 0
      :output (format nil "2~%3~%"))
    (assert-builtin-call (context "contains" '("-i" "needle" "hay"))
      :code 1
      :output-empty t)))

(test contains-reports-usage-and-option-errors
  "contains distinguishes missing operands from unknown options."
  (with-builtins-context (context)
    (assert-builtin-call (context "contains" nil)
      :code 2
      :contains '("usage"))
    (assert-builtin-call (context "contains" '("--bogus" "needle"))
      :code 2
      :contains '("unknown option --bogus"))))

(test pbt-contains-status-matches-generated-membership
  "contains agrees with string= membership for generated shell words."
  (assert-builtin-property (context)
      ((needle (gen-shell-word :max-length 8))
       (values (lambda ()
                 (loop repeat (funcall (gen-in-range 0 8))
                       collect (funcall (gen-shell-word :max-length 8))))))
    (multiple-value-bind (output code)
        (call-builtin context "contains" (append (list "--" needle) values))
      (and (null output)
           (= code (if (member needle values :test #'string=) 0 1))))))

