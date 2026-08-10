(in-package #:nshell.feature.command-line)

(defparameter +usage-synopsis+
  "Usage: nshell [OPTIONS] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]"
  "The stable synopsis shared by the CLI presentation and its tests.")

(defun usage-synopsis ()
  "Return the command-line synopsis without presentation formatting."
  +usage-synopsis+)
