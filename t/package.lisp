;;; nshell test package definitions

(in-package #:cl-user)

(defpackage #:nshell/test
  (:use #:cl)
  ;; cl-weave owns describe (it shadows cl:describe).  The rest of the DSL is
  ;; imported by name so nshell's own PBT generators (gen-integer, gen-string,
  ;; ...) keep their meanings instead of colliding with cl-weave's exports.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it #:it-fails #:expect #:skip #:fail #:run-all
                ;; Table-driven cases and domain matchers -- see support/matchers.
                #:it-each #:describe-each #:defmatcher
                ;; Mutation testing -- see unit/test-mutation.
                #:run-mutations #:assert-mutation-score #:mutation-summary)
  (:export #:run-tests))
