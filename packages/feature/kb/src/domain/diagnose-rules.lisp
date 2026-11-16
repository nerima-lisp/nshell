(in-package #:nshell.feature.kb)

;;; Built-in diagnosis rules (proposal/06 C).  P1 carries only diagnose/typo
;;; (D-82); P4-3 adds the rest here.
;;;
;;; diagnose(Failure, fix(Input), Rule, Evidence) holds for every fix a rule
;;; proposes.  The evaluator describes the failure with status/2, input/2,
;;; command-span/3, and command-name/2, and the runnable names with
;;; candidate-command/1.  diagnose/typo holds for every name one or two edits
;;; away; the evaluator reports only the names at the smallest distance found.

(defparameter *builtin-diagnose-rulebase*
  (cl-prolog-kit:prolog
    ((retype ?r ?good ?new)
     (input ?r ?text) (command-span ?r ?start ?end)
     (splice-text ?text ?start ?end ?good ?new))
    ((diagnose ?r (fix ?new) "diagnose/typo" (distance ?d))
     (status ?r 127) (command-name ?r ?bad)
     (candidate-command ?good)
     (string-edit-distance ?bad ?good ?d) (:when (<= 1 ?d 2))
     (retype ?r ?good ?new))))
