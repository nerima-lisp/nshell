;;;; Package for the cl-weave regression suite.
;;;;
;;;; This suite is a focused, complementary test surface to the primary suite
;;;; in nshell/test.  It exists to exercise two libraries at an advanced level:
;;;;
;;;;   * cl-weave      -- describe/it/expect, property-based testing, fixtures,
;;;;                      benchmarks, and cl-weave's own embedded logic engine.
;;;;   * cl-prolog     -- nshell's completion knowledge base compiled into a
;;;;                      first-class cl-prolog:rulebase and queried with the
;;;;                      full engine API (query-prolog, findall, negation-as-
;;;;                      failure, foreign predicates), plus the cl-prolog/weave
;;;;                      bridge (deftest-queries / assert-query).
;;;;
;;;; Predicate symbols such as COMPLETES are imported from
;;;; nshell.domain.completion so goal literals unify against the very symbols
;;;; the rulebase stores -- Prolog predicates are data, and in Common Lisp that
;;;; means symbol (package) identity has to line up.

(defpackage #:nshell/weave
  (:use #:cl)
  ;; describe collides with cl:describe; cl-weave owns it here.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it #:it-property
                #:expect
                #:before-all #:before-each #:after-each #:around-each
                #:benchmark #:mean-ms #:maximum-ms #:benchmark-result-samples
                #:gen-string #:gen-integer #:gen-member #:gen-one-of
                #:gen-such-that #:gen-list
                #:logic-program #:logic-run
                #:run-all)
  ;; The cl-prolog/weave bridge: declarative query cases as cl-weave tests.
  (:import-from #:cl-prolog/weave
                #:deftest-queries #:assert-query)
  ;; Raw cl-prolog engine surface for the advanced query tests.
  (:import-from #:cl-prolog
                #:query-prolog #:query-prolog-first #:prolog-succeeds-p
                #:solution-binding
                #:make-rulebase #:make-clause #:rulebase-insert-clause!
                #:rulebase-p
                #:define-foreign-predicate #:logic-substitute
                #:findall #:|\\+|)
  ;; nshell's completion domain: the public rulebase builder, the completion
  ;; entry points, and the exported logic predicate vocabulary.
  (:import-from #:nshell.domain.completion
                #:completion-rulebase
                #:complete #:prove-all
                #:builtin-rule-facts #:builtin-rule-rules
                #:make-fact #:make-rule
                #:completes #:describes #:has-flag
                #:command-is #:suggests-dir #:suggests-file)
  (:export #:run))
