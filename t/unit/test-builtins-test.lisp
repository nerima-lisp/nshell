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
