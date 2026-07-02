(in-package #:nshell/test)
(in-suite builtin-tests)

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

(test contains-match-indexes-collects-all-1-based-positions
  "contains-match-indexes returns every matching 1-based position."
  (flet ((idx (needle &rest values)
           (nshell.application::%contains-match-indexes needle values)))
    (is (null (idx "x")))
    (is (null (idx "x" "a" "b" "c")))
    (is (equal '(1) (idx "x" "x" "a" "b")))
    (is (equal '(2) (idx "x" "a" "x" "b")))
    (is (equal '(1 3) (idx "x" "x" "a" "x")))
    (is (equal '(1 2 3) (idx "x" "x" "x" "x")))))

(test seq-parse-args-normalizes-1-2-and-3-arg-forms
  "seq-parse-args converts 1/2/3 string args to (values FIRST STEP LAST) integers."
  (flet ((parse (&rest args)
           (multiple-value-list (nshell.application::%seq-parse-args args))))
    (is (equal '(1 1 5)   (parse "5")))
    (is (equal '(2 1 5)   (parse "2" "5")))
    (is (equal '(1 2 10)  (parse "1" "2" "10")))
    (is (equal '(5 -1 1)  (parse "5" "-1" "1")))
    (is (equal '(nil)     (parse "x")))
    (is (equal '(nil)     (parse "1" "2" "3" "4")))))

(test seq-values-generates-ascending-and-descending-sequences
  "seq-values handles positive/negative step and zero guard."
  (flet ((seq (first step last)
           (nshell.application::%seq-values first step last)))
    (is (equal '(1 2 3)   (seq 1 1 3)))
    (is (equal '(1 3 5)   (seq 1 2 5)))
    (is (equal '(3 2 1)   (seq 3 -1 1)))
    (is (equal '(5 3)     (seq 5 -2 3)))
    (is (null             (seq 5 1 1)))
    (is (null             (seq 1 -1 3)))
    (is (null             (seq 1 0 5)))))

(test invert-status-code-flips-zero-and-nonzero
  "invert-status-code returns 1 for zero/nil and 0 for any non-zero code."
  (flet ((inv (code) (nshell.application::%invert-status-code code)))
    (is (= 1 (inv 0)))
    (is (= 1 (inv nil)))
    (is (= 0 (inv 1)))
    (is (= 0 (inv 127)))))
