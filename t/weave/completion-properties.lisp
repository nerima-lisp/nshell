;;;; Property-based tests, fixtures, and a benchmark over the *live* completion
;;;; entry points (complete / prove-all), driven by the built-in rule KB.

(in-package #:nshell/weave)

(defvar *fixture-rulebase* nil
  "Rulebase shared across a describe block, populated by a before-all hook.")

(describe "complete/prove-all invariants (property-based)"

  (it-property "complete never errors and always returns a list"
      ((input (gen-string :max-length 24)))
    (expect (listp (complete (built-in-rule-kb) input)) :to-be-truthy))

  (it-property "complete returns candidates with string text"
      ((input (gen-string :max-length 24)))
    (expect (every (lambda (candidate)
                     (stringp (candidate-text candidate)))
                   (complete (built-in-rule-kb) input))
            :to-be-truthy))

  (it-property "complete is deterministic for a given input"
      ((input (gen-one-of (gen-member '("" "g" "gi" "git " "cd " "ls -"))
                          (gen-string :max-length 12))))
    ;; complete returns fresh candidate structs, so compare by value (equalp
    ;; recurses into struct slots) rather than by identity (equal).
    (let ((kb (built-in-rule-kb)))
      (expect (equalp (complete kb input) (complete kb input)) :to-be-truthy)))

  (it-property "prove-all binds command completions to strings"
      ((_ (gen-integer :min 0 :max 0)))          ; run the invariant a few times
    (declare (ignore _))
    (let ((solutions (prove-all (built-in-rule-kb)
                                '(completes ?command ?completion))))
      (expect (every (lambda (solution)
                       (and (stringp (solution-binding '?command solution))
                            (stringp (solution-binding '?completion solution))))
                     solutions)
              :to-be-truthy))))

(describe "completion fixtures"
  ;; before-all runs once for the block; the built rulebase is reused below.
  (before-all (setf *fixture-rulebase* (built-in-rulebase)))
  (after-each (expect (rulebase-p *fixture-rulebase*) :to-be-truthy))

  (it "sees the rulebase prepared by before-all"
    (expect (rulebase-p *fixture-rulebase*) :to-be-truthy)
    (expect (prolog-succeeds-p *fixture-rulebase* '(completes "git" "status"))
            :to-be-truthy)))

(describe "completion performance"
  (it "benchmarks a prefix completion without error"
    (let* ((kb (built-in-rule-kb))
           (result (benchmark (:samples 5 :warmup 1)
                     (complete kb "gi"))))
      ;; A benchmark yields one timing sample per configured run.
      (expect (length (benchmark-result-samples result)) :to-equal 5)
      (expect (mean-ms result) :to-satisfy #'realp)
      (expect (maximum-ms result) :to-satisfy (lambda (ms) (>= ms 0))))))
