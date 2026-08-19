;;;; Shared helpers for the cl-weave suite: rulebase construction, a foreign
;;;; predicate, and small set utilities used by the advanced query tests.

(in-package #:nshell/weave)

(defun built-in-rule-kb ()
  "The completion domain's built-in rule knowledge base (a rule-knowledge-base).

Referenced through the internal symbol on purpose: the suite verifies the
*production* knowledge base rather than a hand-rolled fixture."
  nshell.domain.completion::*built-in-rule-knowledge-base*)

(defun built-in-rulebase ()
  "Compile the built-in completion KB into a fresh cl-prolog-kit:rulebase."
  (completion-rulebase (built-in-rule-kb)))

(defun query-values (rulebase goal variable &key (max-depth 64))
  "Every binding of VARIABLE across the solutions of GOAL in RULEBASE."
  (mapcar (lambda (solution) (solution-binding variable solution))
          (query-prolog rulebase goal :max-depth max-depth)))

(defun set-equal* (a b &key (test #'equal))
  "Order-independent, duplicate-insensitive comparison of two lists."
  (and (subsetp a b :test test)
       (subsetp b a :test test)))

;;; A Lisp predicate exposed to the Prolog engine.  It lets a query filter
;;; completion candidates by string prefix entirely inside the proof search --
;;; e.g. (and (completes "git" ?c) (%string-prefix-of "c" ?c)) yields every git
;;; subcommand beginning with "c".  Foreign predicates dispatch by exact
;;; name/arity, so the namespaced name keeps it clear of the engine's builtins.
(define-foreign-predicate (%string-prefix-of prefix whole)
    (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (let ((p (logic-substitute prefix environment))
        (w (logic-substitute whole environment)))
    (when (and (stringp p) (stringp w)
               (<= (length p) (length w))
               (string= p w :end2 (length p)))
      (funcall emit environment))))
