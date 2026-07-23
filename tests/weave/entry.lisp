;;;; Entry point for the cl-weave suite.

(in-package #:nshell/weave)

(defun run (&key (reporter :spec))
  "Run every registered cl-weave test and return true when all pass.

Loading this system registers the suite's describe/it forms into cl-weave's
global registry; RUN simply drives them through the chosen REPORTER."
  (run-all :reporter reporter))
