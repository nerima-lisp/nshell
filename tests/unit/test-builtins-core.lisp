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

(test string-builtin-covers-core-fish-style-subcommands
  "string provides common fish-style string transformation subcommands."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("length" "abc" "")
       :code 0
       :output (format nil "3~%0~%"))
      ('("lower" "HeLLo" "WORLD")
       :code 0
       :output (format nil "hello~%world~%"))
      ('("upper" "Hello")
       :code 0
       :output (format nil "HELLO~%"))
      ('("join" "," "a" "b" "c")
       :code 0
       :output (format nil "a,b,c~%"))
      ('("split" "," "a,b,,c")
       :code 0
       :output (format nil "a~%b~%~%c~%"))
      ('("trim" "  hi  ")
       :code 0
       :output (format nil "hi~%")))))

(test string-builtin-collect-cases
  "string collect normalizes input streams and handles empty-input options."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("collect" "alpha" "beta")
       :code 0
       :output (format nil "alpha~%beta~%"))
      ((list "collect" (format nil "alpha~%~%"))
       :code 0
       :output (format nil "alpha~%"))
      ((list "collect" "-N" (format nil "alpha~%~%"))
       :code 0
       :output (format nil "alpha~%~%~%"))
      ('("collect" "")
       :code 1
       :output-empty t)
      ('("collect" "--allow-empty" "")
       :code 1
       :output (format nil "~%"))
      ('("collect" "--" "-value")
       :code 0
       :output (format nil "-value~%"))
      ('("collect" "--bogus" "value")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-replace-cases
  "string replace covers replacement, case-folding, quiet mode, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("replace" "fish" "nshell" "fish shell fish")
       :code 0
       :output (format nil "nshell shell fish~%"))
      ('("replace" "--all" "fish" "nshell" "fish shell fish")
       :code 0
       :output (format nil "nshell shell nshell~%"))
      ('("replace" "--ignore-case" "fish" "nshell" "FiSh shell")
       :code 0
       :output (format nil "nshell shell~%"))
      ('("replace" "--quiet" "fish" "nshell" "fish shell")
       :code 0
       :output-empty t)
      ('("replace" "--quiet" "fish" "nshell" "bash shell")
       :code 1
       :output-empty t)
      ('("replace" "--" "-old" "new" "-old value")
       :code 0
       :output (format nil "new value~%"))
      ('("replace" "--bogus" "x" "y" "x")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-match-cases
  "string match covers globbing, quiet mode, case folding, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("match" "git*" "git" "status" "git status")
       :code 0
       :output (format nil "git~%git status~%"))
      ('("match" "no*" "git")
       :code 1
       :output-empty t)
      ('("match" "-q" "git*" "git status")
       :code 0
       :output-empty t)
      ('("match" "--quiet" "no*" "git")
       :code 1
       :output-empty t)
      ('("match" "--ignore-case" "git*" "GIT status")
       :code 0
       :output (format nil "GIT status~%"))
      ('("match" "--all" "git*" "git")
       :code 1
       :contains '("unknown option --all"))
      ('("match" "--" "-*" "-abc" "abc")
       :code 0
       :output (format nil "-abc~%"))
      ('("match" "--bogus" "x" "x")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-repeat-cases
  "string repeat covers count, maximum length, quiet mode, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("repeat" "2" "ab")
       :code 1
       :contains '("usage"))
      ('("repeat" "-n" "2" "ab" "c")
       :code 0
       :output (format nil "abab~%cc~%"))
      ('("repeat" "--count=3" "--max" "5" "ab")
       :code 0
       :output (format nil "ababa~%"))
      ('("repeat" "-m5" "ab")
       :code 0
       :output (format nil "ababa~%"))
      ('("repeat" "-n2" "--" "-ab")
       :code 0
       :output (format nil "-ab-ab~%"))
      ('("repeat" "-N" "-n2" "ab" "c")
       :code 0
       :output (format nil "abab~%cc"))
      ('("repeat" "--quiet" "-n" "2" "ab")
       :code 0
       :output-empty t)
      ('("repeat" "-n" "0" "ab")
       :code 1
       :output-empty t)
      ('("repeat" "-m" "0" "ab")
       :code 1
       :output-empty t)
      ('("repeat" "--bogus" "2" "ab")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-sub-cases
  "string sub covers positive and negative slices, quiet mode, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("sub" "--length" "2" "abcde")
       :code 0
       :output (format nil "ab~%"))
      ('("sub" "-s" "2" "-l" "2" "abcde")
       :code 0
       :output (format nil "bc~%"))
      ('("sub" "--start=-2" "abcde")
       :code 0
       :output (format nil "de~%"))
      ('("sub" "--end=3" "abcde")
       :code 0
       :output (format nil "abc~%"))
      ('("sub" "-e" "-1" "abcde")
       :code 0
       :output (format nil "abcd~%"))
      ('("sub" "-s" "-3" "-e" "-2" "abcde")
       :code 0
       :output (format nil "c~%"))
      ('("sub" "-q" "-s" "2" "abcde")
       :code 0
       :output-empty t)
      ('("sub" "-s2" "--" "-abc")
       :code 0
       :output (format nil "abc~%"))
      ('("sub" "-l" "1" "-e" "2" "abcde")
       :code 1
       :contains '("mutually exclusive"))
      ('("sub" "--bogus" "abcde")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-rejects-invalid-integer-options
  "string repeat/sub surface integer parsing errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("repeat" "-n" "nope" "ab")
       :code 1
       :contains '("invalid integer for -n: nope"))
      ('("sub" "-s")
       :code 1
       :contains '("string: -s requires an integer")))))

(test string-builtin-supports-joined-and-assigned-integer-options
  "string repeat/sub accept --opt=value and -oN forms for integer options."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("repeat" "--count=2" "--" "ab")
       :code 0
       :output (format nil "abab~%"))
      ('("repeat" "-n2" "--" "ab")
       :code 0
       :output (format nil "abab~%"))
      ('("sub" "--start=2" "--" "abcde")
       :code 0
       :output (format nil "bcde~%"))
      ('("sub" "-s2" "--" "abcde")
       :code 0
       :output (format nil "bcde~%")))))

(test pbt-string-match-ignore-case-matches-generated-words
  "string match -i agrees with case-insensitive equality for generated shell words."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 8)))
    (let ((candidate (string-upcase word)))
      (multiple-value-bind (output code)
          (call-string-builtin context
                        (list "match" "-i" "--" word candidate))
        (and (= code 0)
             (string= (format nil "~A~%" candidate) output))))))

(test pbt-string-replace-ignore-case-replaces-generated-words
  "string replace -i replaces generated shell words regardless of case."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 8)))
    (let ((candidate (string-upcase word)))
      (multiple-value-bind (output code)
          (call-string-builtin context
                        (list "replace" "-i" "--" word "X" candidate))
        (and (= code 0)
             (string= (format nil "X~%") output))))))

(test pbt-string-repeat-count-controls-generated-output-length
  "string repeat -n produces count copies for generated shell words."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 6))
       (count (gen-in-range 1 6)))
    (multiple-value-bind (output code)
        (call-string-builtin context
                      (list "repeat" "-n" (write-to-string count) "--" word))
      (and (= code 0)
           (= (length output)
              (1+ (* (length word) count)))))))

(test pbt-string-repeat-max-bounds-generated-output-length
  "string repeat -m caps generated output before the trailing newline."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 6))
       (max (gen-in-range 1 12)))
    (multiple-value-bind (output code)
        (call-string-builtin context
                      (list "repeat" "-m" (write-to-string max) "--" word))
      (and (= code 0)
           (= (length output) (1+ max))))))

(test pbt-string-collect-default-trims-generated-trailing-newlines
  "string collect trims generated trailing newlines by default."
  (is
   (assert-string-builtin-property (context)
       ((word (gen-shell-word :min-length 1 :max-length 10))
        (newline-count (gen-in-range 1 4)))
     (let ((input (concatenate 'string
                                word
                                (make-string newline-count
                                             :initial-element #\Newline))))
       (multiple-value-bind (output code)
           (call-string-builtin context (list "collect" "--" input))
         (and (= code 0)
              (string= (format nil "~A~%" word) output)))))))

(test pbt-string-sub-positive-start-and-length-control-output-length
  "string sub -s/-l returns the generated positive-index slice length."
  (is
   (assert-string-builtin-property (context)
       ((word (gen-shell-word :min-length 1 :max-length 12))
        (start (gen-in-range 1 12))
        (requested-length (gen-in-range 1 12)))
     (let* ((expected-length
              (min requested-length
                   (max 0 (- (length word) (1- start)))))
            (expected-code (if (plusp (length word)) 0 1)))
       (multiple-value-bind (output code)
           (call-string-builtin context
                         (list "sub" "-s" (write-to-string start)
                               "-l" (write-to-string requested-length)
                               "--" word))
         (and (= code expected-code)
              (= (length output) (1+ expected-length))))))))

(test read-stores-stdin-line-in-current-environment
  "read consumes one stdin line and stores it as a shell variable."
  (with-builtins-context (context)
    (with-input-from-string (*standard-input* (format nil "hello world~%"))
      (multiple-value-bind (output code) (call-builtin context "read" '("answer"))
        (is (null output))
        (is (= 0 code))))
    (is (string= "hello world"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "answer")))))

(test set-supports-fish-style-options-and-multiple-values
  "set supports fish-style export, erase, query, listing, and multi-token values."
  (with-builtins-context (context)
    (assert-builtin-cases (context "set")
      (("--export" "NSHELL_TEST_EXPORTED" "one" "two")
       :code 0
       :output-null t)
      (("NSHELL_TEST_LOCAL" "alpha" "beta")
       :code 0
       :output-null t)
      (("NSHELL_TEST_EMPTY")
       :code 0
       :output-null t))
    (let ((env (nshell.application:shell-context-environment context)))
      (is (string= "one two"
                   (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED")))
      (is (equal '("one" "two")
                 (nshell.domain.environment:env-get-values env "NSHELL_TEST_EXPORTED")))
      (is (string= "alpha beta"
                   (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL")))
      (is (equal '("alpha" "beta")
                 (nshell.domain.environment:env-get-values env "NSHELL_TEST_LOCAL")))
      (is (string= ""
                   (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY")))
      (is (null (nshell.domain.environment:env-get-values env "NSHELL_TEST_EMPTY")))
      (is (equal '("NSHELL_TEST_EXPORTED" . "one two")
                 (assoc "NSHELL_TEST_EXPORTED"
                        (nshell.domain.environment:env-list env)
                        :test #'string=))))
    (assert-builtin-cases (context "set")
      (("--query" "NSHELL_TEST_EXPORTED" "NSHELL_TEST_LOCAL")
       :code 0
       :output-null t)
      (("--query" "NSHELL_TEST_MISSING")
       :code 1
       :output-null t)
      (nil
       :code 0
       :contains '("set -x NSHELL_TEST_EXPORTED one two"
                   "set NSHELL_TEST_LOCAL alpha beta"
                   "set NSHELL_TEST_EMPTY "))
      (("--erase"
        "NSHELL_TEST_EXPORTED"
        "NSHELL_TEST_LOCAL"
        "NSHELL_TEST_EMPTY")
       :code 0
       :output-null t))
    (let ((env (nshell.application:shell-context-environment context)))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED")))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL")))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY"))))))

(test alias-adds-lists-queries-and-erases-expansions
  "alias stores fish-style multi-token command expansions in the current context."
  (with-builtins-context (context)
    (assert-fish-style-table-builtin-roundtrip
        (context "alias" (nshell.application:shell-context-alias-table context)
                 "ll" "ls -l /tmp" '("ll" "ls" "-l" "/tmp")
                 "alias ll=ls -l /tmp"
                 "alias: -e requires a name
"
                 '("-e" "ll")
                 "missing"))))

(test alias-accepts-inline-name-value-assignment
  "alias accepts the familiar name=value form while preserving remaining tokens."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "alias" '("gs=git" "status" "--short"))
      (is (null output))
      (is (= 0 code)))
    (is (string= "git status --short"
                 (gethash "gs"
                          (nshell.application:shell-context-alias-table
                           context))))))

(test source-expands-multi-token-aliases-from-context
  "source execution expands aliases before dispatching commands."
  (with-builtins-context (context)
    (call-builtin context "alias" '("say" "echo" "from" "alias"))
    (with-called-source (output code context '("say script"))
      (is (= 0 code))
      (is (string= (format nil "from alias script~%") output)))))

(test abbr-adds-lists-queries-and-erases-expansions
  "abbr stores fish-style multi-token expansions in the current shell context."
  (with-builtins-context (context)
    (assert-fish-style-table-builtin-roundtrip
        (context "abbr" (nshell.application:shell-context-abbreviation-table context)
                 "gco" "git checkout" '("-a" "gco" "git" "checkout")
                 "abbr -a gco git checkout"
                 "abbr: -e requires a name
"
                 '("-e" "gco")
                 "missing"))))

(test abbr-accepts-fish-style-long-options
  "abbr accepts long option names for add, query, list, show, and erase."
  (with-builtins-context (context)
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--add" "gst" "git" "status")))))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--query" "gst")))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--list"))
      (is (= 0 code))
      (is (search "gst" output))
      (is (not (search "git status" output))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a gst git status" output)))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--erase" "gst")))))
    (is (= 1 (nth-value 1 (call-builtin context "abbr"
                                         '("--query" "gst")))))))

(test abbr-adds-position-scoped-expansions
  "abbr stores optional fish-style position metadata for expansion-time checks."
  (with-builtins-context (context)
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--add" "--position" "command"
                                           "gco" "git" "checkout")))))
    (let ((value (gethash "gco"
                          (nshell.application:shell-context-abbreviation-table
                           context))))
      (is (nshell.domain.abbreviation:abbreviation-p value))
      (is (string= "git checkout"
                   (nshell.domain.abbreviation:abbreviation-expansion value)))
      (is (eq :command
              (nshell.domain.abbreviation:abbreviation-position value))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a --position command gco git checkout" output)))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("-a" "-p" "anywhere"
                                           "gst" "git" "status")))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a --position anywhere gst git status" output)))))

(test abbr-rejects-invalid-position-option
  "abbr rejects missing or unknown --position values."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "abbr" '("-a" "--position" "middle"
                                       "gco" "git" "checkout"))
      (is (= 2 code))
      (is (search "command or anywhere" output)))
    (multiple-value-bind (output code)
        (call-builtin context "abbr" '("-a" "-p"))
      (is (= 2 code))
      (is (search "requires" output)))))

(test complete-builtin-adds-command-and-argument-completions
  "complete updates the session knowledge base used by interactive completion."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "complete"
                      '("-c" "deploy" "-f" "--dry-run" "-f" "--target"
                        "-d" "release service"))
      (is (null output))
      (is (= 0 code)))
    (multiple-value-bind (output code)
        (call-builtin context "complete"
                      '("--command" "deploy" "--flag" "--dry-run"
                        "--flag" "--target" "--description" "release service"))
      (is (null output))
      (is (= 0 code)))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (command (find "deploy"
                          (nshell.domain.completion:complete kb "dep")
                          :key #'nshell.domain.completion:candidate-text
                          :test #'string=))
           (arguments (mapcar #'nshell.domain.completion:candidate-text
                              (nshell.domain.completion:complete kb "deploy --"))))
      (is (not (null command)))
      (is (string= "release service"
                   (nshell.domain.completion:candidate-description command)))
      (is (equal '("--dry-run" "--target") arguments)))
    (multiple-value-bind (output code)
        (call-builtin context "complete"
                      '("-c" "deploy" "-l" "color" "-s" "o"
                        "-a" "always auto never"))
      (is (null output))
      (is (= 0 code)))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (candidates (nshell.domain.completion:complete kb "deploy --color=")))
      (is (equal '("--color=always" "--color=auto" "--color=never")
                 (mapcar #'nshell.domain.completion:candidate-text candidates))))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (candidates (nshell.domain.completion:complete kb "deploy --color a")))
      (is (equal '("always" "auto")
                 (mapcar #'nshell.domain.completion:candidate-text candidates))))
    (let* ((kb (nshell.application:shell-context-knowledge-base context))
           (candidates (nshell.domain.completion:complete kb "deploy -o n")))
      (is (equal '("never")
                 (mapcar #'nshell.domain.completion:candidate-text candidates))))))

(test complete-builtin-rejects-missing-command
  "complete requires an explicit command name."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "complete" '("-f" "--bad"))
      (is (= 1 code))
      (is (search "usage" output)))))

(test complete-builtin-erases-command-completions
  "complete -e removes session completion metadata for a command."
  (with-builtins-context (context)
    (let ((command "__nshell-deploy"))
      (multiple-value-bind (output code)
          (call-builtin context "complete"
                        (list "-c" command "-f" "--dry-run"
                              "-l" "color" "-a" "always auto"
                              "-d" "test-only deploy command"))
        (is (null output))
        (is (= 0 code)))
      (let ((kb (nshell.application:shell-context-knowledge-base context)))
        (is (not (null (nshell.domain.completion:kb-query kb command)))))
      (multiple-value-bind (output code)
          (call-builtin context "complete" (list "-c" command "--erase"))
        (is (null output))
        (is (= 0 code)))
      (let ((kb (nshell.application:shell-context-knowledge-base context)))
        (is (null (nshell.domain.completion:kb-query kb command)))
        (is (not (member command
                         (mapcar #'nshell.domain.completion:candidate-text
                                 (nshell.domain.completion:complete
                                  kb "__nshell-"))
                         :test #'string=)))))))

(test complete-builtin-rejects-missing-arguments
  "complete reports missing arguments for each required option."
  (with-builtins-context (context)
    (assert-builtin-cases (context "complete")
      (("-c") :code 2 :output (format nil "complete: -c requires command~%"))
      (("--command") :code 2 :output (format nil "complete: --command requires command~%"))
      (("-f") :code 2 :output (format nil "complete: -f requires flag~%"))
      (("--flag") :code 2 :output (format nil "complete: --flag requires flag~%"))
      (("-l") :code 2 :output (format nil "complete: -l requires option~%"))
      (("--long-option") :code 2 :output (format nil "complete: --long-option requires option~%"))
      (("-s") :code 2 :output (format nil "complete: -s requires option~%"))
      (("--short-option") :code 2 :output (format nil "complete: --short-option requires option~%"))
      (("-a") :code 2 :output (format nil "complete: -a requires arguments~%"))
      (("--arguments") :code 2 :output (format nil "complete: --arguments requires arguments~%"))
      (("-d") :code 2 :output (format nil "complete: -d requires description~%"))
      (("--description") :code 2 :output (format nil "complete: --description requires description~%")))))

(test function-builtin-stores-and-manages-inline-body
  "function builtin stores inline fish-style bodies and exposes management operations."
  (with-builtins-context (context)
    (assert-fish-style-table-builtin-roundtrip
        (context "function" (nshell.application:shell-context-function-table context)
                 "hi" '("echo hello")
                 '("hi" "echo" "hello" "end")
                 "function hi"
                 "function: -e requires a name
"
                 '("-e" "hi")
                 "missing"
                 :body-contains ("  echo hello" "end")))))

(test history-builtin-searches-deletes-clears-and-reports-size
  "history builtin exposes fish-style in-memory history management."
  (let* ((context (make-test-builtins-context))
         (history (nshell.application:shell-context-history context)))
    (nshell.domain.history:history-add history "Git status")
    (nshell.domain.history:history-add history "git status")
    (nshell.domain.history:history-add history "docker ps")
    (nshell.domain.history:history-add history "git commit")
    (nshell.domain.history:history-add history "git status --short")
    (assert-builtin-cases (context "history")
      (nil :code 0 :output (format nil "Git status~%git status~%docker ps~%git commit~%git status --short~%"))
      ('("search" "git") :code 0 :output (format nil "git status --short~%git commit~%git status~%Git status~%"))
      ('("search" "--prefix" "git") :code 0 :output (format nil "git status --short~%git commit~%git status~%Git status~%"))
      ('("search" "--case-sensitive" "git") :code 0
       :output (format nil "git status --short~%git commit~%git status~%"))
      ('("search" "--contains" "status --") :code 0
       :output (format nil "git status --short~%"))
      ('("search" "--exact" "--case-sensitive" "Git status") :code 0
       :output (format nil "Git status~%"))
      ('("delete" "docker" "ps") :code 0 :output (format nil "1~%"))
      ('("size") :code 0 :output (format nil "4~%"))
      ('("clear") :code 0 :output-null t)
      ('("bogus") :code 1
       :output (format nil "history: usage: history [search [--prefix|--contains|--exact|--case-sensitive] query | delete command | clear | size]~%")))
    (is (= 0 (nshell.domain.history:history-size history)))))
