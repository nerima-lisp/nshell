;;;; Advanced cl-prolog-kit usage over nshell's real completion knowledge.
;;;;
;;;; These cases go past yes/no proof search: aggregation with findall,
;;;; negation-as-failure, solution ordering, and a Lisp foreign predicate
;;;; composed with domain facts inside a single query.

(in-package #:nshell/weave)

(describe "completion knowledge via advanced cl-prolog-kit"

  (it "aggregates every completes/2 solution into one list with findall"
    (let* ((rulebase (built-in-rulebase))
           (all (solution-binding
                 '?all
                 (query-prolog-first
                  rulebase `(findall ?c (completes "git" ?c) ?all))))
           (enumerated (query-values rulebase `(completes "git" ?c) '?c)))
      ;; findall collects one list holding every solution ...
      (expect (listp all) :to-be-truthy)
      (expect all :to-contain "status")
      (expect all :to-contain "commit")
      (expect all :to-contain "git")            ; the command completes to itself
      ;; ... in exactly the order backtracking would visit them.
      (expect all :to-equal enumerated)))

  (it "returns completes/2 solutions in a stable, repeatable order"
    ;; Solution order is a function of clause order, so identical queries over
    ;; freshly built rulebases must enumerate identically.
    (expect (query-values (built-in-rulebase) `(completes "git" ?c) '?c)
            :to-equal
            (query-values (built-in-rulebase) `(completes "git" ?c) '?c)))

  (it "uses negation-as-failure to reject flags git does not define"
    (let ((rulebase (built-in-rulebase)))
      ;; \+ Goal succeeds exactly when Goal has no proof.
      (expect (prolog-succeeds-p rulebase `(|\\+| (has-flag "git" "--no-such-flag")))
              :to-be-truthy)
      (expect (prolog-succeeds-p rulebase `(|\\+| (has-flag "git" "--help")))
              :to-be-null)))

  (it "composes a Lisp foreign predicate with domain facts in one query"
    (let* ((rulebase (built-in-rulebase))
           (c-subcommands
             (query-values rulebase
                           `(and (completes "git" ?c)
                                 (%string-prefix-of "c" ?c))
                           '?c)))
      ;; The prefix filter runs inside proof search: every result starts "c".
      (expect (plusp (length c-subcommands)) :to-be-truthy)
      (expect (every (lambda (s) (char= #\c (char s 0))) c-subcommands)
              :to-be-truthy)
      ;; The obvious git subcommands survive the filter.
      (expect (subsetp '("commit" "clone" "checkout") c-subcommands :test #'equal)
              :to-be-truthy))))
