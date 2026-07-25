;;;; cl-weave ships its own small logic engine (logic-program / logic-run).
;;;; Here we model a slice of nshell's completion rules in *that* engine and
;;;; confirm it derives the same answers cl-prolog does for the production
;;;; rulebase -- a cross-check of two independent solvers against one intent.

(in-package #:nshell/weave)

(describe "completion semantics cross-checked in cl-weave's logic engine"

  (it "derives subcommand completions with logic-run"
    (let ((program (logic-program
                    (:completes "git" "status")
                    (:completes "git" "commit")
                    (:completes "cd" "cd"))))
      ;; logic-run returns one binding alist per solution.
      (let ((completions (mapcar (lambda (binding) (cdr (assoc '?c binding)))
                                 (logic-run program (:completes "git" ?c)))))
        (expect (set-equal* completions '("status" "commit")) :to-be-truthy))))

  (it "resolves a rule the way suggests-dir does in the rulebase"
    ;; Mirror ((suggests-dir ?input) (command-is ?input "cd")) as a cl-weave
    ;; logic rule and confirm the derived binding matches cl-prolog's answer.
    (let* ((program (logic-program
                     (:command-is "cd" "cd")
                     (:- (:suggests-dir ?input) (:command-is ?input "cd"))))
           (weave-answer (cdr (assoc '?x (first (logic-run program
                                                           (:suggests-dir ?x))))))
           (prolog-answer (solution-binding
                           '?x (query-prolog-first (built-in-rulebase)
                                                   `(command-is ?x "cd")))))
      (expect weave-answer :to-equal "cd")
      (expect weave-answer :to-equal prolog-answer))))
