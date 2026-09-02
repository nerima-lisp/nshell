(in-package #:nshell/test)

(describe "test builtin"
  (it "evaluates unary, string, numeric, and bracket expressions"
    "The predicate table is exercised through the public builtin registry."
    (with-builtins-context (context)
      (dolist (args '( ("-n" "text") ("-z" "")
                       ("text" "=" "text") ("text" "!=" "other")
                       ("2" "-eq" "2") ("1" "-lt" "2")
                       ("2" "-le" "2") ("3" "-gt" "2")
                       ("3" "-ge" "2") ("2" "-ne" "3")))
        (assert-builtin-call (context "test" args) :code 0))
      (assert-builtin-call (context "[" '("text" "=" "text" "]"))
        :code 0)
      (assert-builtin-call (context "test" nil) :code 1)
      (assert-builtin-call (context "test" '("text" "=")) :code 2
        :contains '("unknown operator"))))

  (it "reports invalid numeric and unknown expressions"
    "Numeric predicates reject malformed operands and unsupported operators."
    (with-builtins-context (context)
      (assert-builtin-call (context "test" '("x" "-eq" "1"))
        :code 2 :contains '("integer expression expected: x"))
      (assert-builtin-call (context "test" '("1" "-eq" "x"))
        :code 2 :contains '("integer expression expected: x"))
      (assert-builtin-call (context "test" '("a" "?" "b"))
        :code 2 :contains '("unknown operator"))
      (assert-builtin-call (context "[" '("text" "="))
        :code 2 :contains '("missing ]"))
      (assert-builtin-call (context "test" '("a" "b" "c" "d"))
        :code 1 :output-null t))))

(describe "builtin runtime helpers"
  (it "joins printable arguments without changing their values"
    (expect "alpha::2" :to-equal
            (nshell.application::%string-join '("alpha" 2) "::"))
    (expect "" :to-equal
            (nshell.application::%string-join nil "::")))

  (it "parses command modes, sentinel operands, and option failures"
    (multiple-value-bind (mode operands error status)
        (nshell.application::%parse-command-options '("-v" "--" "-V"))
      (expect :short :to-equal mode)
      (expect '("-V") :to-equal operands)
      (expect error :to-be-null)
      (expect status :to-be-null))
    (multiple-value-bind (mode operands error status)
        (nshell.application::%parse-command-options '("-V" "-v"))
      (declare (ignore mode operands))
      (expect error :to-be-truthy)
      (expect 2 :to-equal status))
    (multiple-value-bind (mode operands error status)
        (nshell.application::%parse-command-options '("--unknown"))
      (declare (ignore mode operands))
      (expect error :to-be-truthy)
      (expect 2 :to-equal status)))

  (it "formats every command resolution mode"
    (expect (format nil "/bin/echo~%") :to-equal
            (nshell.application::%format-command-resolution
             "echo" :path "/bin/echo" :short))
    (expect (format nil "echo is a function~%") :to-equal
            (nshell.application::%format-command-resolution
             "echo" :function nil :verbose))
    (expect (format nil "echo is a shell builtin~%") :to-equal
            (nshell.application::%format-command-resolution
             "echo" :builtin "echo" :verbose))
    (expect (format nil "echo is /bin/echo~%") :to-equal
            (nshell.application::%format-command-resolution
             "echo" :path "/bin/echo" :verbose))
    (expect (nshell.application::%format-command-resolution
             "echo" :builtin "echo" :execute)
            :to-be-null)))

(describe "test predicate boundaries"
  (it "covers unary and numeric false branches"
    "Predicate helpers preserve shell test semantics at their direct boundaries."
    (let ((context (make-test-shell-context)))
      (expect (nshell.application::%test-unary-predicate-p context "-n" "value")
              :to-be-truthy)
      (expect (nshell.application::%test-unary-predicate-p context "-n" "")
              :to-be-falsy)
      (expect (nshell.application::%test-unary-predicate-p context "-z" "")
              :to-be-truthy)
      (expect (nshell.application::%test-unary-predicate-p context "-z" "value")
              :to-be-falsy)
      (expect (nshell.application::%test-unary-predicate-p context "-f" "/missing")
              :to-be-falsy)
      (expect (nshell.application::%test-unary-predicate-p context "-d" "/missing")
              :to-be-falsy)
      (expect (nshell.application::%test-unary-predicate-p context "-e" "/missing")
              :to-be-falsy)
      (expect (nshell.application::%test-unary-predicate-p context "?" "value")
              :to-be-falsy))
    (multiple-value-bind (output code)
        (nshell.application::%test-binary-numeric-result "2" "-lt" "1")
      (expect output :to-be-null)
      (expect 1 :to-equal code))))

(describe "command and eval dispatch"
  (it "reports command paths and executes the selected command"
    (with-builtins-context (context)
      (assert-builtin-call (context "command" '("-v" "echo"))
        :code 0 :contains '("echo"))
      (assert-builtin-call (context "command" '("-v"))
        :code 1 :output-null t)
      (assert-builtin-call (context "command" '("-V" "echo" "missing"))
        :code 1 :contains '("echo is a shell builtin" "missing: not found"))
      (assert-builtin-call (context "command" nil) :code 0 :output-null t)
      (with-stubbed-command-executor
          (("echo" (values "ran: hello" 7)))
        (multiple-value-bind (output code)
            (call-builtin context "command" '("echo" "hello"))
          (expect "ran: hello" :to-equal output)
          (expect 7 :to-equal code)))))

  (it "prefers functions and falls back to external commands"
    (with-builtins-context (context)
      (let ((table (nshell.application:shell-context-function-table context)))
        (setf (gethash "greet" table) '("echo" "hello")))
      (with-test-external-capture-runner
          (lambda (command args)
            (values (format nil "external ~a ~{~a~^,~}" command args) 3))
        (multiple-value-bind (output code)
            (nshell.application::%execute-command-by-name-in-context
             context "greet" nil)
          (expect (search "external hello" output) :to-be-truthy)
          (expect code :to-be-truthy))
        (multiple-value-bind (output code)
            (nshell.application::%execute-command-by-name-in-context
             context "unknown" '("arg"))
          (expect output :to-equal "external unknown arg")
          (expect code :to-be-truthy)))))

  (it "evaluates complete, empty, and malformed command lines"
    (with-builtins-context (context)
      (with-stubbed-command-executor
          (("echo" (values "echoed hello" 0)))
        (assert-builtin-call (context "eval" '("echo" "hello"))
          :code 0 :output "echoed hello")
        (assert-builtin-call (context "eval" nil) :code 0 :output-null t)
        (assert-builtin-call (context "eval" '("echo" "|"))
          :code 2 :contains '("eval: parse error"))
        (assert-builtin-call (context "eval" '("echo" ")"))
          :code 2 :contains '("eval: parse error")))))

  (it "exposes command path metadata"
    (expect (nshell.application::%command-path-spec "type")
            :to-be-truthy)
    (expect (nshell.application::%command-path-spec "not-a-command")
            :to-be-null)))
