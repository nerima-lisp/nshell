;;;; The cl-prolog/weave bridge: nshell's completion rules asserted as
;;;; declarative query cases.  deftest-queries expands each spec into an
;;;; independent cl-weave `it`, rebuilding the rulebase per case so no test
;;;; leaks state into the next.

(in-package #:nshell/weave)

;;; assert-query kinds used below:
;;;   :succeeds  -- the goal has at least one proof
;;;   :fails     -- the goal has no proof
;;;   :first     -- the first solution equals the given bindings alist
;;;   :ordered   -- the full solution list equals the given value, in order
(deftest-queries completion-rulebase-bridge ((built-in-rulebase))
  ("cd is recognised as a directory-taking command"
   (suggests-dir "cd") :succeeds)
  ("source takes a file argument"
   (suggests-file "source") :succeeds)
  ("git exposes its status subcommand"
   (completes "git" "status") :succeeds)
  ("git exposes its commit subcommand"
   (completes "git" "commit") :succeeds)
  ("an unknown command completes to nothing"
   (completes "definitely-not-a-command" "status") :fails)
  ("cd does not masquerade as a file-taking command"
   (suggests-file "cd") :fails)
  ("--help carries a human-readable description"
   (describes "--help" ?description)
   :first ((?description . "show command help"))))

;;; The same bridge, but reached through assert-query inside hand-written cases
;;; so a single test can make several related assertions.
(describe "completion rulebase (assert-query)"
  (it "answers flag and self-completion facts for git"
    (let ((rulebase (built-in-rulebase)))
      (assert-query rulebase (completes "git" "git") :succeeds)
      (assert-query rulebase (has-flag "git" "--help") :succeeds)
      (assert-query rulebase (command-is "." "source") :succeeds))))
