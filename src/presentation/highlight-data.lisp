;;; Highlight data tables: builtin names, operator token types, and the
;;; fallback (theme-less) ANSI role palette used by highlight.lisp.
(in-package #:nshell.presentation)

(defvar *builtin-commands*
  '("echo" "pwd" "ls" "cd" "exit" "fg" "bg" "jobs" "disown"
    "set" "export" "alias" "abbr" "function" "source" "exec"
    "true" "false" "contains" "test" "type" "which" "history" "help")
  "Commands built into nshell that get distinct highlighting.")

(defparameter +operator-token-types+
  '(:pipe :and :or :semicolon :ampersand :redirect))

(defparameter +fallback-highlight-ansi+
  '((:command . "~C[34m")
    (:builtin . "~C[34;1m")
    (:argument . "~C[37m")
    (:option . "~C[36m")
    (:operator . "~C[33m")
    (:error . "~C[31m")
    (:comment . "~C[2;37m")
    (:quote . "~C[33m")
    (:normal . "~C[0m")))
