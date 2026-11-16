(in-package #:nshell.feature.machine)

;;; ux/U6 「非対話で詰まらないように」: what machine mode and NSHELL_AGENT=1
;;; batch runs give the programs they start.

(defparameter +noninteractive-child-environment+
  '(("PAGER" . "cat")
    ("GIT_PAGER" . "cat")
    ("TERM" . "dumb")
    ("NO_COLOR" . "1"))
  "Exported variables a noninteractive run starts from, as (NAME . VALUE). They
replace what the caller's environment holds; the input can still set another
value, for one command or for the rest of the run.")
