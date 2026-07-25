(in-package #:nshell/test)

(describe "builtin-tests"
  (it "count-reports-number-of-arguments"
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

  (it "seq-prints-integer-sequences"
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

  (it "contains-tests-membership-without-output"
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

  (it "contains-index-prints-matching-value-positions"
    "contains -i prints 1-based positions within the searched values."
    (with-builtins-context (context)
      (assert-builtin-call (context "contains"
                             '("--index" "needle" "hay" "needle" "needle"))
        :code 0
        :output (format nil "2~%3~%"))
      (assert-builtin-call (context "contains" '("-i" "needle" "hay"))
        :code 1
        :output-empty t)))

  (it "contains-reports-usage-and-option-errors"
    "contains distinguishes missing operands from unknown options."
    (with-builtins-context (context)
      (assert-builtin-call (context "contains" nil)
        :code 2
        :contains '("usage"))
      (assert-builtin-call (context "contains" '("--bogus" "needle"))
        :code 2
        :contains '("unknown option --bogus"))))

  (it "pbt-contains-status-matches-generated-membership"
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

  (it "contains-match-indexes-collects-all-1-based-positions"
    "contains-match-indexes returns every matching 1-based position."
    (flet ((idx (needle &rest values)
             (nshell.application::%contains-match-indexes needle values)))
      (expect (idx "x") :to-be-null)
      (expect (idx "x" "a" "b" "c") :to-be-null)
      (expect '(1) :to-equal (idx "x" "x" "a" "b"))
      (expect '(2) :to-equal (idx "x" "a" "x" "b"))
      (expect '(1 3) :to-equal (idx "x" "x" "a" "x"))
      (expect '(1 2 3) :to-equal (idx "x" "x" "x" "x"))))

  (it "seq-parse-args-normalizes-1-2-and-3-arg-forms"
    "seq-parse-args converts 1/2/3 string args to (values FIRST STEP LAST) integers."
    (flet ((parse (&rest args)
             (multiple-value-list (nshell.application::%seq-parse-args args))))
      (expect '(1 1 5) :to-equal (parse "5"))
      (expect '(2 1 5) :to-equal (parse "2" "5"))
      (expect '(1 2 10) :to-equal (parse "1" "2" "10"))
      (expect '(5 -1 1) :to-equal (parse "5" "-1" "1"))
      (expect '(nil) :to-equal (parse "x"))
      (expect '(nil) :to-equal (parse "1" "2" "3" "4"))))

  (it "seq-values-generates-ascending-and-descending-sequences"
    "seq-values handles positive/negative step and zero guard."
    (flet ((seq (first step last)
             (nshell.application::%seq-values first step last)))
      (expect '(1 2 3) :to-equal (seq 1 1 3))
      (expect '(1 3 5) :to-equal (seq 1 2 5))
      (expect '(3 2 1) :to-equal (seq 3 -1 1))
      (expect '(5 3) :to-equal (seq 5 -2 3))
      (expect (seq 5 1 1) :to-be-null)
      (expect (seq 1 -1 3) :to-be-null)
      (expect (seq 1 0 5) :to-be-null)))

  (it "invert-status-code-flips-zero-and-nonzero"
    "invert-status-code returns 1 for zero/nil and 0 for any non-zero code."
    (flet ((inv (code) (nshell.application::%invert-status-code code)))
      (expect 1 :to-equal (inv 0))
      (expect 1 :to-equal (inv nil))
      (expect 0 :to-equal (inv 1))
      (expect 0 :to-equal (inv 127)))))
