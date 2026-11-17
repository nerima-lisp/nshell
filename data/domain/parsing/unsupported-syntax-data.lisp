(in-package #:nshell.domain.parsing)

;;; Bare-line syntax that v0.8 rejects with E_UNSUPPORTED_SYNTAX before any of
;;; the input runs, and the equivalent S-expression to show
;;; (language/L5-bare-line.md 5.3, language/L7-diff-and-migration.md 7.2).
;;;
;;; Each row is a plist. :HEAD is a command name the row rejects at the head of
;;; a bare-line command written unquoted and without ^. :REWRITE is the L5.3
;;; S-expression shown when none can be built from the commands around the
;;; head; :ADVICE replaces it for a row L5.3 gives no S-expression for.
;;; The other L5.3 rows (if, for, while, switch, begin, !, here-docs) belong in
;;; this table too.
(defparameter +unsupported-bare-line-syntax+
  '((:head "and" :rewrite "(and (cmd1) (cmd2))")
    (:head "or" :rewrite "(or (cmd1) (cmd2))")
    (:head "not" :rewrite "(not (cmd))")
    (:head "break" :rewrite "(return)")
    (:head "continue"
     :advice "no S-expression corresponds to it; restructure the loop body with (when …) or (unless …)")
    (:head "function" :rewrite "(defcmd f () …)")))

;;; The options of fish's function that take a value, given by the next word
;;; or attached (-ddesc, --description=desc). The function's name in the
;;; rewrite is its first argument that is neither an option nor such a value.
(defparameter +fish-function-value-options+
  '("-d" "--description" "-a" "--argument-names" "-w" "--wraps"
    "-e" "--on-event" "-v" "--on-variable" "-j" "--on-job-exit"
    "-p" "--on-process-exit" "-s" "--on-signal" "-V" "--inherit-variable"))
