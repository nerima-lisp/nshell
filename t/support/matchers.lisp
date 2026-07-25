;;; Domain-specific cl-weave matchers.
;;;
;;; These extend `expect' with vocabulary from nshell's own domain so table
;;; cases read as the behavior they assert -- e.g.
;;;   (expect "1 + 2 * 3" :to-evaluate-to 7)
;;;   (expect "file[0-2].lisp" :to-glob-match "file1.lisp")
;;; The matcher body receives ACTUAL (the value handed to EXPECT) and EXPECTED
;;; (the list of trailing arguments; single-value matchers take its FIRST).

(in-package #:nshell/test)

(defmatcher :to-evaluate-to (actual expected)
  "ACTUAL, a shell arithmetic expression, evaluates to the single EXPECTED
integer under the standard ARITH-ENV fixture (X=10, Y=3)."
  (eql (first expected)
       (nshell.domain.expansion:evaluate-arithmetic actual (arith-env))))

(defmatcher :to-glob-match (actual expected)
  "ACTUAL, a shell glob pattern, matches the single EXPECTED text."
  (and (nshell.domain.expansion:glob-match-p actual (first expected)) t))

(defmatcher :not-to-glob-match (actual expected)
  "ACTUAL, a shell glob pattern, does not match the single EXPECTED text."
  (not (nshell.domain.expansion:glob-match-p actual (first expected))))
